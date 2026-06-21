local _, ns = ...
ns = ns or __AGNB_NS
ns.Sync = ns.Sync or {}
local SY = ns.Sync

SY.PREFIX = "AGNB"
local FIELDS = { "player","time","sourceName","ability","isEnv","envType","boss","pullId","classification","id" }

local function esc(s) return (tostring(s):gsub("\\", "\\b"):gsub("|", "\\p")) end
local function unesc(s)
  return (s:gsub("\\(.)", function(c)
    if c == "b" then return "\\" elseif c == "p" then return "|" else return c end
  end))
end

-- Stable, clock-independent death id. Only the single authoritative broadcaster assigns one,
-- so the id space is collision-free without coordinating clocks: "<myShortName>#<counter>".
local deathCounter = 0
function SY.NextDeathId()
  deathCounter = deathCounter + 1
  local me = (UnitName and UnitName("player")) or "?"
  return me .. "#" .. deathCounter
end
function SY.StampId(death)
  if death and death.id == nil and SY.AmBroadcaster() then death.id = SY.NextDeathId() end
  return death and death.id or nil
end

-- Encode a death record to a single pipe-delimited line: "D|field|field|...".
function SY.Encode(death)
  local parts = { "D" }
  for _, f in ipairs(FIELDS) do
    local v = death[f]
    if v == nil then v = ""
    elseif v == true then v = "1"
    elseif v == false then v = "0" end
    parts[#parts+1] = esc(v)
  end
  return table.concat(parts, "|")
end

-- Decode a wire line back to a death record, or nil if malformed.
function SY.Decode(line)
  if type(line) ~= "string" then return nil end
  local parts = {}
  for token in (line .. "|"):gmatch("(.-)|") do parts[#parts+1] = token end
  if parts[1] ~= "D" then return nil end
  -- length-tolerant for mixed versions: map the known fields that are present, default a
  -- missing trailing field (older sender), and ignore any extra trailing fields (newer sender).
  local d = {}
  for i, f in ipairs(FIELDS) do
    local raw = parts[i + 1]
    if raw == nil then
      d[f] = nil
    else
      raw = unesc(raw)
      if f == "time" or f == "pullId" then d[f] = tonumber(raw)
      elseif f == "isEnv" then d[f] = (raw == "1")
      elseif raw == "" then d[f] = nil
      else d[f] = raw end
    end
  end
  if not d.player or not d.time then return nil end
  return d
end

-- ----- WoW glue: broadcast + receive -----
function SY.Channel()
  if IsInRaid and IsInRaid() then return "RAID"
  elseif IsInGroup and IsInGroup() then return "PARTY" end
  return nil
end

-- Only the authoritative broadcaster (raid leader / assist, or an unlocked dev) syncs
-- deaths, so a death goes on the wire ONCE instead of being rebroadcast by every client
-- that saw it (which made wipe traffic O(raiders^2)). Non-broadcasters still record their
-- own local combat-log observations; they just don't put copies on the wire.
function SY.AmBroadcaster()
  local isL = UnitIsGroupLeader and UnitIsGroupLeader("player") or false
  local isA = UnitIsGroupAssistant and UnitIsGroupAssistant("player") or false
  local name = UnitName and UnitName("player") or nil
  local tag; if BNGetInfo then local _, bt = BNGetInfo(); tag = bt end
  return ns.Summary and ns.Summary.CanBroadcast(isL, isA, name, tag) or false
end

function SY.Broadcast(death)
  if not (ns.cfg and ns.cfg.syncEnabled ~= false) then return end
  if not SY.AmBroadcaster() then ns.Log("dev", "sync tx death skipped: not the broadcaster"); return end
  local chan = SY.Channel()
  if not chan or not C_ChatInfo then ns.Log("dev", "sync tx death skipped: no group channel"); return end
  ns.Log("dev", ("sync tx death %s id=%s -> %s"):format(tostring(death.player), tostring(death.id), chan))
  C_ChatInfo.SendAddonMessage(SY.PREFIX, SY.Encode(death), chan)
end

-- ----- WoW glue: show-banner / show-summary broadcasts -----
local lastShown = 0
local function throttledShow(kind, payload)
  local now = (GetTime and GetTime()) or 0
  if now - lastShown < 5 then return end   -- accept at most one popup / 5s
  lastShown = now
  ns.Log("debug", "broadcast shown: " .. tostring(kind))
  if kind == "BANNER" and ns.Banner then
    ns.Banner.Show({ tagline = (ns.cfg and ns.cfg.wipeTagline), statline = payload })
  elseif kind == "SUMMARY" and ns.Summary then
    ns.Summary.Show()
  end
end

function SY.MaybeBroadcastBanner(ctx)
  local chan = SY.Channel()
  if not chan or not C_ChatInfo then return end
  C_ChatInfo.SendAddonMessage(SY.PREFIX, "SB|" .. esc(ctx.statline or ""), chan)
end

function SY.BroadcastSummary()
  local chan = SY.Channel()
  if not chan or not C_ChatInfo then return end
  C_ChatInfo.SendAddonMessage(SY.PREFIX, "SS|", chan)
end

-- ----- addon presence / version (for the Raid Info view) -----
-- Each client announces its version; everyone records peers' versions. Announcing on
-- roster change means a joiner and the existing raid learn each other within a few seconds.
SY.peerVersions = SY.peerVersions or {}   -- short name -> { version = "1.2.0", time = GetTime }
local lastVerAnnounce = 0
function SY.AnnounceVersion()
  local chan = SY.Channel(); if not (chan and C_ChatInfo) then return end
  local now = (GetTime and GetTime()) or 0
  if now - lastVerAnnounce < 8 then return end   -- throttle a roster-update storm
  lastVerAnnounce = now
  C_ChatInfo.SendAddonMessage(SY.PREFIX, "VER|" .. (ns.version or "?"), chan)
end

-- A peer not heard from within VER_TTL is treated as no-addon, so the Raid Info view doesn't
-- show stale "has the addon" rows for players who left or logged.
local VER_TTL = 90
function SY.FreshPeerVersion(name, now)
  local p = SY.peerVersions and SY.peerVersions[name]
  if not p then return nil end
  if now and p.time and (now - p.time) > VER_TTL then return nil end
  return p.version
end

-- Ask the group to (re)announce their versions, so opening Raid Info populates promptly
-- instead of waiting for the next roster change.
function SY.RequestVersions()
  local chan = SY.Channel(); if not (chan and C_ChatInfo) then return end
  C_ChatInfo.SendAddonMessage(SY.PREFIX, "VREQ|", chan)
end

-- ----- mid-raid catch-up: a joiner asks for state, the broadcaster resends recent deaths -----
-- Reuses the normal death wire format + RecordDeath de-dup, so no new parser/chunking is
-- needed. Both sides throttle, and only the authoritative broadcaster answers, so the
-- whole exchange is one request + a bounded burst of recent deaths.
local lastSnapshot, lastRequest = 0, 0

-- `requester` (short name) is whispered the snapshot directly so the rest of the raid
-- doesn't receive a redundant burst; falls back to the group channel if it's missing.
-- Re-injection is now idempotent: every stored death carries the broadcaster-assigned stable
-- id (see SY.StampId), so a re-sent copy dedups by id regardless of clock skew -- the reason
-- this was previously disabled. The whisper-to-requester path means present members (who have
-- their own id-less local copies) don't receive the burst.
-- Is `name` a current group broadcaster (leader/assist, or a dev)? Used for the leader-reload
-- fallback below.
function SY.IsBroadcasterName(name)
  if not name or name == "" then return false end
  if ns.Summary and ns.Summary.DEV_BROADCASTERS and ns.Summary.DEV_BROADCASTERS[name] then return true end
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
  for i = 1, n do
    local unit = prefix .. i
    if UnitName and UnitName(unit) == name then
      return (UnitIsGroupLeader and UnitIsGroupLeader(unit))
          or (UnitIsGroupAssistant and UnitIsGroupAssistant(unit)) or false
    end
  end
  return false
end

function SY.SendSnapshot(requester)
  if not C_ChatInfo then return end
  -- Normally only the broadcaster answers. Fallback: if the REQUESTER is itself a broadcaster
  -- (the leader reloaded mid-raid, with no one above it to ask), a raid ASSISTANT answers
  -- instead. Capped to assists (1-3 in a raid) so a big raid doesn't storm the requester; stable
  -- ids make the duplicate answers idempotent on the receiver.
  if not SY.AmBroadcaster() then
    local iAmAssist = UnitIsGroupAssistant and UnitIsGroupAssistant("player") or false
    if not (iAmAssist and SY.IsBroadcasterName(requester)) then
      ns.Log("dev", "snapshot skipped: not broadcaster / not a fallback assist")
      return
    end
  end
  local now = (GetTime and GetTime()) or 0
  if now - lastSnapshot < 15 then ns.Log("dev", "snapshot throttled (<15s since last)"); return end
  lastSnapshot = now
  local store = ns.db and ns.db.store
  local raidId = ns.Tracking and ns.Tracking.raidId
  local recent = (store and raidId and ns.DB.DeathLog(store, raidId, 40)) or {}
  local toWhisper = requester and requester ~= ""
  local chan = (not toWhisper) and SY.Channel() or nil
  if not toWhisper and not chan then return end
  ns.Log("dev", ("sync tx snapshot: %d deaths -> %s"):format(#recent, toWhisper and ("whisper " .. requester) or chan))
  for _, d in ipairs(recent) do
    if toWhisper then
      C_ChatInfo.SendAddonMessage(SY.PREFIX, SY.Encode(d), "WHISPER", requester)
    else
      C_ChatInfo.SendAddonMessage(SY.PREFIX, SY.Encode(d), chan)
    end
  end
end

function SY.RequestState()
  local chan = SY.Channel()
  if not (chan and C_ChatInfo) then ns.Log("dev", "catch-up request skipped: no group channel (not grouped yet?)"); return end
  local now = (GetTime and GetTime()) or 0
  if now - lastRequest < 30 then ns.Log("dev", "catch-up request throttled (<30s since last)"); return end
  lastRequest = now
  ns.Log("dev", "sync tx DREQ (requesting catch-up) -> " .. chan)
  C_ChatInfo.SendAddonMessage(SY.PREFIX, "DREQ|" .. (ns.MyName or (UnitName and UnitName("player")) or ""), chan)
end

ns.OnInit(function()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(SY.PREFIX)
  end
  local f = CreateFrame("Frame")
  f:RegisterEvent("CHAT_MSG_ADDON")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")   -- login / zone-in: announce version + ask for catch-up
  f:RegisterEvent("GROUP_ROSTER_UPDATE")     -- someone joined/left: re-announce versions
  f:SetScript("OnEvent", ns.Debug.Guard("Sync.OnEvent", function(_, event, prefix, msg, _, sender)
    if event == "PLAYER_ENTERING_WORLD" then
      if C_Timer and C_Timer.After then
        C_Timer.After(4, SY.AnnounceVersion)
        C_Timer.After(6, SY.RequestState)   -- ask the broadcaster to backfill recent deaths
      end
      return
    elseif event == "GROUP_ROSTER_UPDATE" then
      if C_Timer and C_Timer.After then
        C_Timer.After(2, SY.AnnounceVersion)
        -- the group (re)formed -> the channel is ready now, so (re)request catch-up. The 30s
        -- throttle bounds roster churn; this is the reliable trigger (PLAYER_ENTERING_WORLD+6s
        -- often fires before the party is grouped, so its request gets skipped).
        C_Timer.After(3, SY.RequestState)
      end
      return
    end
    if prefix ~= SY.PREFIX then return end
    if sender and ns.MyName and sender:match("^[^-]+") == ns.MyName then return end -- skip own echo
    ns.Log("dev", ("sync rx %s from %s"):format(msg:match("^[^|]+") or msg:sub(1, 8),
      tostring((sender and sender:match("^[^-]+")) or sender)))
    if msg:sub(1,4) == "VER|" then
      local who = sender and sender:match("^[^-]+")
      if who then SY.peerVersions[who] = { version = msg:sub(5), time = (GetTime and GetTime()) or 0 } end
      if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
      return
    elseif msg:sub(1,5) == "VREQ|" then
      SY.AnnounceVersion()   -- someone opened Raid Info; re-announce ours (throttled)
      return
    elseif msg:sub(1,5) == "DREQ|" then
      SY.SendSnapshot(msg:sub(6))   -- a joiner asked for state; whisper them recent deaths
      return
    elseif msg:sub(1,3) == "SB|" then
      throttledShow("BANNER", unesc(msg:sub(4)))
      return
    elseif msg:sub(1,3) == "SS|" then
      throttledShow("SUMMARY")
      return
    elseif msg:sub(1,5) == "OINV|" then
      if ns.AntiPrize then ns.AntiPrize.OnInvite(msg:sub(6)) end
      return
    elseif msg:sub(1,3) == "OI|" then
      if ns.AntiPrize then ns.AntiPrize.OnSync(sender and sender:match("^[^-]+"), msg:sub(4) == "1") end
      return
    end
    local death = SY.Decode(msg)
    local store = ns.db and ns.db.store
    local raidId = ns.Tracking and ns.Tracking.raidId
    if death then
      local recorded = store and raidId and ns.DB.RecordDeath(store, raidId, death, (GetTime and GetTime()) or nil)
      ns.Log("dev", ("sync rx death %s id=%s -> %s (raid %s)"):format(tostring(death.player),
        tostring(death.id), recorded and "RECORDED" or "dup/skip", tostring(raidId)))
      if recorded and ns.UI then ns.UI.Refresh() end
    end
  end))
end)
