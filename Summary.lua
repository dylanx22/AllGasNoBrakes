local _, ns = ...
ns = ns or __AGNB_NS
ns.Summary = ns.Summary or {}
local SM = ns.Summary

-- Last boss of each TBC raid/instance, keyed by ENCOUNTER_END encounter name.
SM.FINAL_BOSSES = {
  ["Prince Malchezaar"] = true,   -- Karazhan
  ["Gruul the Dragonkiller"] = true,
  ["Magtheridon"] = true,
  ["Lady Vashj"] = true,          -- Serpentshrine Cavern
  ["Kael'thas Sunstrider"] = true,-- Tempest Keep (The Eye)
  ["Archimonde"] = true,          -- Hyjal
  ["Illidan Stormrage"] = true,   -- Black Temple
  ["Zul'jin"] = true,             -- Zul'Aman
  ["Kil'jaeden"] = true,          -- Sunwell Plateau
}

function SM.FinalBoss(name) return (name and SM.FINAL_BOSSES[name]) == true end

-- DEV broadcasters: grants the LOCAL user broadcast/dev rights. Empty by default so the
-- public build ships no hardcoded dev names. Unlock per-character with `/agnb dev on`
-- (persists in ns.db.devUnlocked); the OnInit below injects the local name into this
-- table so the name-based CanBroadcast check still works without a backdoor.
SM.DEV_BROADCASTERS = {}
SM.DEV_BATTLETAG = nil  -- cleared for public release (was a personal BattleTag)

function SM.CanBroadcast(isLeader, isAssist, localName, battleTag)
  if isLeader or isAssist then return true end
  if localName and SM.DEV_BROADCASTERS[localName] then return true end
  if battleTag and SM.DEV_BATTLETAG and battleTag == SM.DEV_BATTLETAG then return true end
  return false
end

-- seconds between start..end -> "Hh Mm" or "Mm".
function SM.Duration(startTime, endTime)
  local secs = math.max(0, math.floor((endTime or 0) - (startTime or 0)))
  local h = math.floor(secs / 3600)
  local m = math.floor((secs % 3600) / 60)
  if h > 0 then return h .. "h" .. m .. "m" end
  return m .. "m"
end

-- ----- WoW glue: end-of-raid screen + triggers + broadcast -----
local function localCanBroadcast()
  local isL = UnitIsGroupLeader and UnitIsGroupLeader("player") or false
  local isA = UnitIsGroupAssistant and UnitIsGroupAssistant("player") or false
  local name = UnitName and UnitName("player") or nil
  local tag = nil
  if BNGetInfo then local _, bt = BNGetInfo(); tag = bt end
  return SM.CanBroadcast(isL, isA, name, tag)
end

local function classColor(name)
  if not (UnitClass and UnitName) then return 0.9, 0.86, 0.72 end
  local function colorFor(unit)
    if UnitName(unit) ~= name then return nil end
    local _, class = UnitClass(unit)
    local c = class and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
  end
  local r, g, b = colorFor("player"); if r then return r, g, b end
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
  for i = 1, n do r, g, b = colorFor(prefix .. i); if r then return r, g, b end end
  return 0.9, 0.86, 0.72
end

local function summaryData()
  local demo = ns.Demo and ns.Demo.active
  local store = demo and ns.Demo.store or (ns.db and ns.db.store)
  local raidId = demo and ns.Demo.raidId or (ns.Tracking and ns.Tracking.raidId)
  return store, raidId
end

local RANKS = { "1st", "2nd", "3rd" }
local BARCOLOR = { { 0.85, 0.68, 0.20 }, { 0.62, 0.62, 0.66 }, { 0.66, 0.45, 0.22 } } -- gold/silver/bronze

local function build()
  if SM.frame then return SM.frame end
  local f = CreateFrame("Frame", "AGNB_Summary", UIParent, "BackdropTemplate")
  f:SetSize(460, 440); f:SetPoint("CENTER"); f:SetFrameStrata("HIGH")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
    f:SetBackdropColor(0.05,0.04,0.02,0.97); f:SetBackdropBorderColor(0.23,0.18,0.09,1)
  end
  CreateFrame("Button", nil, f, "UIPanelCloseButton"):SetPoint("TOPRIGHT",2,2)

  f.title = f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT",16,-12); f.title:SetTextColor(1,0.85,0.4)
  f.sub = f:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
  f.sub:SetPoint("TOPLEFT",16,-32)

  -- podium (cols ordered 2nd, 1st, 3rd; bar heights encode rank). Columns are
  -- anchored by their BOTTOM to a baseline above the lowlights band so the bars
  -- grow UP and the name/title/rank stack on top without overlapping anything.
  f.cols = {}
  local order = { { slot=2, x=-110, h=42 }, { slot=1, x=0, h=66 }, { slot=3, x=110, h=30 } }
  for _, o in ipairs(order) do
    local c = CreateFrame("Frame", nil, f); c:SetSize(104, 170)
    c:SetPoint("BOTTOM", f, "TOP", o.x, -212)
    c.bar = c:CreateTexture(nil,"ARTWORK"); c.bar:SetWidth(74); c.bar:SetHeight(o.h)
    c.bar:SetPoint("BOTTOM",0,0)
    local bc = BARCOLOR[o.slot]; c.bar:SetColorTexture(bc[1], bc[2], bc[3], 1)
    c.count = c:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    c.count:SetPoint("CENTER", c.bar, "CENTER"); c.count:SetTextColor(0.08,0.06,0.03)
    c.name = c:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    c.name:SetPoint("BOTTOM", c.bar, "TOP", 0, 4); c.name:SetWidth(104); c.name:SetWordWrap(false)
    c.title = c:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    c.title:SetPoint("BOTTOM", c.name, "TOP", 0, 1); c.title:SetWidth(104); c.title:SetWordWrap(false)
    c.medal = c:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    c.medal:SetPoint("BOTTOM", c.title, "TOP", 0, 3)
    f.cols[o.slot] = c
  end

  -- lowlights rows
  f.lowHeader = f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  f.lowHeader:SetPoint("TOPLEFT",18,-238); f.lowHeader:SetText("LOWLIGHTS"); f.lowHeader:SetTextColor(0.7,0.62,0.36)
  f.lowRows = {}
  for i = 1, 5 do
    local lbl = f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT",24,-256 - (i-1)*20); lbl:SetJustifyH("LEFT")
    local val = f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    val:SetPoint("TOPRIGHT",-18,-256 - (i-1)*20); val:SetJustifyH("RIGHT"); val:SetWidth(260); val:SetWordWrap(false)
    f.lowRows[i] = { lbl = lbl, val = val }
  end

  f.prize = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
  f.prize:SetPoint("TOPLEFT",18,-368); f.prize:SetTextColor(1,0.85,0.4)

  local post = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  post:SetSize(110,20); post:SetPoint("BOTTOMLEFT",16,14); post:SetText("Post to chat")
  post:SetScript("OnClick", function() if ns.UI and ns.UI.DoReportType then ns.UI.DoReportType("lowlights") end end)
  local settle = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  settle:SetSize(90,20); settle:SetPoint("LEFT",post,"RIGHT",8,0); settle:SetText("Settle pot")
  settle:SetScript("OnClick", function() if ns.UI and ns.UI.SettleMail then ns.UI.SettleMail() end end)
  SM.frame = f
  return f
end

-- Render the styled end-of-raid screen from the active (real or demo) store.
function SM.Render()
  local store, raidId = summaryData()
  local raid = store and raidId and store.raids[raidId]
  if not raid then ns.Print("No raid recorded yet.") return end
  local cfg = ns.cfg or {}
  local brand = ns.Brand.Resolve(cfg, GetGuildInfo and GetGuildInfo("player") or nil)
  local board = ns.DB.LeaderboardTonight(store, raidId)
  local low = ns.Ledger.Lowlights(raid)
  local counts = {}
  for _, b in ipairs(board) do counts[b.player] = b.deaths end
  local participants = ns.AntiPrize and ns.AntiPrize.Participants() or nil
  local settle = ns.Ledger.Settlement(counts, cfg.buyIn or 1, participants)
  -- raid.startTime is the combat-log epoch timestamp (death.time domain), so the
  -- end bound must also be epoch time() -- NOT GetTime() uptime, or the difference
  -- is hugely negative and the duration always clamps to 0m.
  local dur = SM.Duration(raid.startTime or 0, (time and time()) or 0)

  local f = build()
  f.title:SetText("End of Raid")
  f.sub:SetText(brand .. "  \194\183  " .. (low.zone or "") .. "  \194\183  " .. dur)

  local takenAwards = {}
  for slot = 1, 3 do
    local c, b = f.cols[slot], board[slot]
    if b then
      c:Show()
      local award = ns.Ledger.PodiumAward(b.player, takenAwards)
      takenAwards[award] = true
      c.medal:SetText(RANKS[slot]); c.medal:SetTextColor(unpack(BARCOLOR[slot]))
      c.name:SetText(b.player); c.name:SetTextColor(classColor(b.player))
      c.title:SetText(award); c.count:SetText(b.deaths)
    else
      c:Hide()
    end
  end

  local items = {}
  if low.feeder then items[#items+1] = { "Feeder of the Night", low.feeder .. " (" .. (low.feederDeaths or 0) .. ")" } end
  if low.deadliestAbility then items[#items+1] = { "Deadliest ability", low.deadliestAbility .. (low.deadliestSource and (" \194\183 " .. low.deadliestSource) or "") } end
  if low.faceplanter then items[#items+1] = { "Biggest faceplant", low.faceplanter } end
  if low.firstBlood then items[#items+1] = { "First blood", low.firstBlood } end
  items[#items+1] = { "Total body count", tostring(low.bodyCount or 0) }
  for i = 1, 5 do
    local row, it = f.lowRows[i], items[i]
    if it then
      row.lbl:SetText(it[1]); row.lbl:SetTextColor(0.6, 0.56, 0.45)
      row.val:SetText(it[2]); row.val:SetTextColor(0.92, 0.86, 0.7); row.lbl:Show(); row.val:Show()
    else
      row.lbl:Hide(); row.val:Hide()
    end
  end

  local nIn = ns.AntiPrize and ns.AntiPrize.Count() or 0
  if (settle.pot or 0) > 0 and settle.winner then
    f.prize:SetText(("Anti-prize pot: %dg  \194\183  fewest deaths wins: %s  \194\183  %d in")
      :format(settle.pot, settle.winner, nIn))
  else
    f.prize:SetText("Anti-prize: opt-in pot \194\183 no one has joined yet (Settings to join)")
  end

  ns.Log("info", "summary shown: " .. tostring(brand))
  f:Show()
end

function SM.Show() SM.Render() end

function SM.Broadcast()
  if not localCanBroadcast() then
    ns.Print("Only the raid leader/assist can show the summary to everyone.")
    SM.Show(); return
  end
  SM.Show()
  if ns.Sync and ns.Sync.BroadcastSummary then ns.Sync.BroadcastSummary() end
end

ns.OnInit(function()
  -- per-character dev unlock (set by `/agnb dev on`): inject the local name so the
  -- name-based CanBroadcast check grants dev rights without a hardcoded backdoor.
  if ns.db and ns.db.devUnlocked then
    local me = UnitName and UnitName("player")
    if me then SM.DEV_BROADCASTERS[me] = true end
  end
  local f = CreateFrame("Frame")
  f:RegisterEvent("ENCOUNTER_END")
  f:SetScript("OnEvent", ns.Debug.Guard("Summary.OnEvent", function(_, _, _, encounterName, _, _, success)
    local cfg = ns.cfg or {}
    if success == 1 and cfg.autoSummaryOnFinalBoss ~= false and SM.FinalBoss(encounterName) then
      ns.After(2, SM.Show)  -- let the kill settle, then pop locally
    end
  end))
end)
