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

function SY.Broadcast(death)
  if not (ns.cfg and ns.cfg.syncEnabled ~= false) then return end
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

ns.OnInit(function()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(SY.PREFIX)
  end
  local f = CreateFrame("Frame")
  f:RegisterEvent("CHAT_MSG_ADDON")
  f:SetScript("OnEvent", ns.Debug.Guard("Sync.OnEvent", function(_, _, prefix, msg, _, sender)
    if prefix ~= SY.PREFIX then return end
    if sender and ns.MyName and sender:match("^[^-]+") == ns.MyName then return end -- skip own echo
    if msg:sub(1,3) == "SB|" then
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
