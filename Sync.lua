local _, ns = ...
ns = ns or __AGNB_NS
ns.Sync = ns.Sync or {}
local SY = ns.Sync

SY.PREFIX = "AGNB"
local FIELDS = { "player","time","sourceName","ability","isEnv","envType","boss","pullId","classification" }

local function esc(s) return (tostring(s):gsub("\\", "\\b"):gsub("|", "\\p")) end
local function unesc(s)
  return (s:gsub("\\(.)", function(c)
    if c == "b" then return "\\" elseif c == "p" then return "|" else return c end
  end))
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
  if parts[1] ~= "D" or #parts ~= #FIELDS + 1 then return nil end
  local d = {}
  for i, f in ipairs(FIELDS) do
    local raw = unesc(parts[i + 1])
    if f == "time" or f == "pullId" then d[f] = tonumber(raw)
    elseif f == "isEnv" then d[f] = (raw == "1")
    elseif raw == "" then d[f] = nil
    else d[f] = raw end
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
  if not SY.AmBroadcaster() then return end
  local chan = SY.Channel()
  if not chan or not C_ChatInfo then return end
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

-- ----- mid-raid catch-up: a joiner asks for state, the broadcaster resends recent deaths -----
-- Reuses the normal death wire format + RecordDeath de-dup, so no new parser/chunking is
-- needed. Both sides throttle, and only the authoritative broadcaster answers, so the
-- whole exchange is one request + a bounded burst of recent deaths.
local lastSnapshot, lastRequest = 0, 0

-- `requester` (short name) is whispered the snapshot directly so the rest of the raid
-- doesn't receive a redundant burst; falls back to the group channel if it's missing.
function SY.SendSnapshot(requester)
  if not (SY.AmBroadcaster() and C_ChatInfo) then return end
  local now = (GetTime and GetTime()) or 0
  if now - lastSnapshot < 15 then return end   -- at most one snapshot / 15s
  lastSnapshot = now
  local store = ns.db and ns.db.store
  local raidId = ns.Tracking and ns.Tracking.raidId
  local recent = (store and raidId and ns.DB.DeathLog(store, raidId, 40)) or {}
  local toWhisper = requester and requester ~= ""
  local chan = (not toWhisper) and SY.Channel() or nil
  if not toWhisper and not chan then return end
  for _, d in ipairs(recent) do
    if toWhisper then
      C_ChatInfo.SendAddonMessage(SY.PREFIX, SY.Encode(d), "WHISPER", requester)
    else
      C_ChatInfo.SendAddonMessage(SY.PREFIX, SY.Encode(d), chan)
    end
  end
end

function SY.RequestState()
  local chan = SY.Channel(); if not (chan and C_ChatInfo) then return end
  local now = (GetTime and GetTime()) or 0
  if now - lastRequest < 30 then return end    -- at most one request / 30s
  lastRequest = now
  C_ChatInfo.SendAddonMessage(SY.PREFIX, "DREQ|" .. (ns.MyName or (UnitName and UnitName("player")) or ""), chan)
end

ns.OnInit(function()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(SY.PREFIX)
  end
  local f = CreateFrame("Frame")
  f:RegisterEvent("CHAT_MSG_ADDON")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")   -- login / zone-in: ask the raid for catch-up state
  f:SetScript("OnEvent", ns.Debug.Guard("Sync.OnEvent", function(_, event, prefix, msg, _, sender)
    if event == "PLAYER_ENTERING_WORLD" then
      if C_Timer and C_Timer.After then C_Timer.After(4, SY.RequestState) end
      return
    end
    if prefix ~= SY.PREFIX then return end
    if sender and ns.MyName and sender:match("^[^-]+") == ns.MyName then return end -- skip own echo
    if msg:sub(1,5) == "DREQ|" then
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
    if death and ns.DB.RecordDeath(ns.db.store, ns.Tracking.raidId, death) then
      if ns.UI then ns.UI.Refresh() end
    end
  end))
end)
