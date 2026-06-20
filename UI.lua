local _, ns = ...
ns = ns or __AGNB_NS
ns.UI = ns.UI or {}
local UI = ns.UI

local GOLD   = { 1, 0.85, 0.4 }
local MUTED  = { 0.54, 0.49, 0.39 }
local DIM    = { 0.36, 0.32, 0.26 }
local TAN    = { 0.9, 0.86, 0.72 }

local SCOPES = { { id = "tonight", label = "Tonight" }, { id = "alltime", label = "All-Time" } }
local VIEWS  = { { id = "deaths", label = "Deaths" }, { id = "abilities", label = "Abilities" },
                 { id = "log", label = "Death Log" } }
UI.scope = "tonight"
UI.view  = "deaths"

-- Which views use the scrolling row list, and which honor the Tonight/All-Time
-- scope (only those that actually change output do).
local LIST_VIEWS   = { deaths = true, abilities = true, log = true, perboss = true, timeline = true, betting = true, raidinfo = true }
local SCOPED_VIEWS = { deaths = true, abilities = true, log = true }

local function showListChrome(f, show)
  f.contentTitle:SetShown(show)
  f.colHead.name:SetShown(show); f.colHead.sub:SetShown(show); f.colHead.ct:SetShown(show)
  f.colDivider:SetShown(show); f.content:SetShown(show); f.footer:SetShown(show)
  -- the empty-state hint only belongs to list views; never let it linger over a panel
  if not show and f.emptyHint then f.emptyHint:Hide() end
end

-- First-run / nothing-tracked-yet copy, keyed by view, so an empty window explains
-- itself instead of showing blank rows.
local EMPTY_HINTS = {
  deaths    = "No deaths tracked yet.\nThey'll show up here once the raid starts dying.",
  abilities = "No killing blows recorded yet.",
  log       = "No deaths logged yet.",
  perboss   = "No boss deaths to break down yet.",
  timeline  = "No pull to chart yet.",
  betting   = "No bets settled yet.",
}

function UI.SetView(id)
  if id == "history" then UI.history.level = "list" end
  UI.view = id
  UI.Refresh()
end

local ROWH = 19

-- ----- class color via the group roster (names aren't unit tokens) -----
-- Cached per name so a full leaderboard refresh doesn't rescan the roster for every
-- row (refresh runs on every death). Only successful lookups are cached -- a miss may
-- just mean the roster hasn't loaded yet -- and the cache is cleared on
-- GROUP_ROSTER_UPDATE (see OnInit) so newly-joined raiders pick up their color.
local classColorCache = {}
local function classColor(name)
  if not name then return unpack(TAN) end
  local cached = classColorCache[name]
  if cached then return cached[1], cached[2], cached[3] end
  if not (UnitClass and UnitName) then return unpack(TAN) end
  local function colorFor(unit)
    if UnitName(unit) ~= name then return nil end
    local _, class = UnitClass(unit)
    local c = class and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
  end
  local r, g, b = colorFor("player")
  if not r then
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
    for i = 1, n do
      r, g, b = colorFor(prefix .. i)
      if r then break end
    end
  end
  if r then classColorCache[name] = { r, g, b }; return r, g, b end
  return unpack(TAN)
end

-- demo mode swaps in an isolated store so real stats stay untouched.
local function activeData()
  local demo = ns.Demo and ns.Demo.active
  local store = demo and ns.Demo.store or (ns.db and ns.db.store)
  local raidId = demo and ns.Demo.raidId or (ns.Tracking and ns.Tracking.raidId)
  return store, raidId
end

local function brandName()
  return (ns.Brand and ns.Brand.Resolve(ns.cfg or {}, GetGuildInfo and GetGuildInfo("player") or nil))
    or "All Gas No Brakes"
end

-- Raid Info rows: every group member with whether they run the addon (+ version), their WoW
-- role, and who holds the AGNB (Book) admin. Versions come from the version pings (Sync).
local function raidInfoRows()
  if ns.Sync and ns.Sync.AnnounceVersion then ns.Sync.AnnounceVersion() end  -- nudge a fresh round
  local me = ns.MyName or (UnitName and UnitName("player"))
  local peers = (ns.Sync and ns.Sync.peerVersions) or {}
  local designated = ns.db and ns.db.designatedAdmin
  local out = {}
  local function add(unit, isSelf)
    local name = UnitName and UnitName(unit)
    if not name then return end
    local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit) or false
    local isAssist = UnitIsGroupAssistant and UnitIsGroupAssistant(unit) or false
    local version = isSelf and ns.version or (peers[name] and peers[name].version)
    out[#out + 1] = {
      player = name, isLeader = isLeader, isAssist = isAssist,
      version = version, hasAddon = version ~= nil,
      -- the AGNB admin is the appointed delegate if set, otherwise the raid leader.
      isAdmin = (designated and designated == name) or (not designated and isLeader) or false,
      online = (not UnitIsConnected) or UnitIsConnected(unit),
    }
  end
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  if n == 0 then
    add("player", true)
  else
    local inRaid = IsInRaid and IsInRaid()
    local prefix = inRaid and "raid" or "party"
    for i = 1, n do
      local unit = prefix .. i
      add(unit, UnitName and UnitName(unit) == me)
    end
    if not inRaid then add("player", true) end   -- party units exclude the player
  end
  table.sort(out, function(a, b)
    if a.isAdmin ~= b.isAdmin then return a.isAdmin end
    if a.hasAddon ~= b.hasAddon then return a.hasAddon end
    return (a.player or "") < (b.player or "")
  end)
  return out
end

-- ----- post/report shared data (used by the panel and the floating dialog) -----
local POST_TYPES = {
  { value = "tonight",   label = "Tonight leaderboard" },
  { value = "alltime",   label = "All-Time leaderboard" },
  { value = "lowlights", label = "Lowlights reel" },
  { value = "ledger",    label = "Anti-prize ledger" },
}
local function labelOf(options, v)
  for _, o in ipairs(options) do if o.value == v then return o.label end end
  return tostring(v)
end

-- ----- frame construction -----
local function navButton(parent, label, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(96, 20)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", 10, 0); fs:SetText(label)
  b.fs = fs
  local accent = b:CreateTexture(nil, "ARTWORK")
  accent:SetColorTexture(unpack(GOLD)); accent:SetSize(2, 16); accent:SetPoint("LEFT", 0, 0); accent:Hide()
  b.accent = accent
  b:SetScript("OnClick", ns.Debug.Guard("nav:" .. tostring(label), onClick))
  return b
end

local function pillButton(parent, label, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(58, 18)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("CENTER"); fs:SetText(label)
  b.fs = fs
  b:SetScript("OnClick", ns.Debug.Guard("pill:" .. tostring(label), onClick))
  return b
end

-- ----- sectioned navigation -----
local function isDev() return ns.Demo and ns.Demo.IsDev and ns.Demo.IsDev() end
local function bookOn() return ns.cfg and ns.cfg.bookEnabled end
local function canInvite() return ns.AntiPrize and ns.AntiPrize.CanInvite() end

-- Each entry is a section header, a leaderboard view (swaps the content list), or
-- an action (opens a panel / runs a command). showIf hides admin/dev/book entries.
local NAV = {
  { header = "Leaderboards" },
  { label = "Deaths",      view = "deaths" },
  { label = "Abilities",   view = "abilities" },
  { label = "Death Log",   view = "log" },
  { header = "Overlays" },
  { label = "End of Raid", action = function() if ns.Summary then ns.Summary.Show() end end },
  { header = "The Book" },
  { label = "Wagering",    view = "book" },
  { label = "Bet Records", view = "betting" },
  { header = "Insights" },
  { label = "Per-Boss",      view = "perboss" },
  { label = "Pull Timeline", view = "timeline" },
  { header = "History" },
  { label = "Raid History", view = "history" },
  { header = "Raid" },
  { label = "Raid Info",   view = "raidinfo" },
  { header = "Actions" },
  { label = "Post Report", view = "report" },
  { label = "Settings",    view = "settings" },
  { label = "Help",        view = "help" },
}

-- Position nav widgets top-down, skipping hidden entries; highlight the active view.
local function layoutNav(f)
  local y = -60
  for _, e in ipairs(f.nav) do
    local def = e.def
    if def.showIf and not def.showIf() then
      e.widget:Hide()
    else
      e.widget:Show()
      e.widget:ClearAllPoints()
      if e.isHeader then
        y = y - 6
        e.widget:SetPoint("TOPLEFT", 12, y); y = y - 16
      else
        e.widget:SetPoint("TOPLEFT", 8, y); y = y - 21
        if def.view then
          local active = (def.view == UI.view)
          e.widget.fs:SetTextColor(unpack(active and GOLD or (def.color or TAN)))
          if e.widget.accent then e.widget.accent:SetShown(active) end
        end
      end
    end
  end
end

-- ----- In-window report panel -----
local function buildReportPanel(f)
  if UI.panels.report and UI.panels.report.frame then return UI.panels.report.frame end
  local p = CreateFrame("Frame", nil, f.host)
  p:SetAllPoints(f.host); p:Hide()

  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 4, -2); title:SetText("Post a report to chat"); title:SetTextColor(unpack(GOLD))

  p.sel, p.dds = {}, {}
  local function mkdd(label, key, options, y)
    local lbl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", 18, y); lbl:SetText(label)
    local dd = CreateFrame("Frame", "AGNB_ReportPanelDD_" .. key, p, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", 92, y + 4)
    UIDropDownMenu_SetWidth(dd, 160)
    UIDropDownMenu_Initialize(dd, function()
      for _, o in ipairs(options) do
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.value = o.label, o.value
        info.checked = (p.sel[key] == o.value)
        info.func = function()
          p.sel[key] = o.value
          UIDropDownMenu_SetSelectedValue(dd, o.value)
          UIDropDownMenu_SetText(dd, o.label)
        end
        UIDropDownMenu_AddButton(info)
      end
    end)
    p.dds[key] = { dd = dd, options = options }
  end
  mkdd("Report",  "kind",    POST_TYPES,          -28)
  mkdd("Channel", "channel", ns.Config.CHANNELS,  -74)
  mkdd("Depth",   "topN",    ns.Config.TOPN,      -120)

  local post = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  post:SetSize(120, 22); post:SetPoint("BOTTOMRIGHT", -16, 16); post:SetText("Post")
  post:SetScript("OnClick", function()
    UI.DoReportType(p.sel.kind, { channel = p.sel.channel, topN = p.sel.topN })
  end)

  UI.panels.report = {
    frame = p,
    refresh = function()
      -- sync defaults from the current scope + saved config each time the panel is shown
      p.sel.kind    = (UI.scope == "alltime") and "alltime" or "tonight"
      p.sel.channel = (ns.cfg and ns.cfg.reportChannel) or "SELF"
      p.sel.topN    = (ns.cfg and ns.cfg.reportTopN) or 5
      for key, e in pairs(p.dds) do
        UIDropDownMenu_SetSelectedValue(e.dd, p.sel[key])
        UIDropDownMenu_SetText(e.dd, labelOf(e.options, p.sel[key]))
      end
    end,
  }
  return p
end

-- ----- History browser panel (drill-down: list -> night -> killcam) -----
UI.history = { level = "list", raidId = nil, deathIdx = nil }

local function histStore() return (select(1, activeData())) end

-- A pooled, reusable clickable row inside a panel.
local function histRow(p, i)
  p.rows = p.rows or {}
  local b = p.rows[i]
  if not b then
    b = CreateFrame("Button", nil, p)
    b:SetSize(560, ROWH)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 6, 0); fs:SetJustifyH("LEFT"); b.fs = fs
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 0.85, 0.4, 0.08)
    p.rows[i] = b
  end
  b:ClearAllPoints()   -- reused rows may have been anchored differently last render
  b:Show()
  return b
end

local function histHideRowsFrom(p, n)
  for i = n, #(p.rows or {}) do p.rows[i]:Hide() end
end

local function histKind(k) return k == "heal" and "HEAL" or (k == "cast" and "CAST" or "DMG") end

local function buildHistoryPanel(f)
  if UI.panels.history and UI.panels.history.frame then return UI.panels.history.frame end
  local p = CreateFrame("Frame", nil, f.host)
  p:SetAllPoints(f.host); p:Hide()
  p:SetClipsChildren(true)   -- never let rows spill past the panel onto the action bars
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, delta)
    UI.history.scroll = (UI.history.scroll or 0) - delta * 3
    UI.RenderHistory()
  end)

  p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  p.title:SetPoint("TOPLEFT", 4, -2); p.title:SetTextColor(unpack(GOLD))

  p.back = navButton(p, "< Back", function()
    if UI.history.level == "killcam" then UI.history.level = "night"
    else UI.history.level = "list" end
    UI.Refresh()
  end)
  p.back:SetPoint("TOPRIGHT", -4, -2)

  p.exportBtn = navButton(p, "Export", function() UI.OpenExport(UI.history.raidId) end)
  p.exportBtn:SetPoint("TOPRIGHT", -90, -2)

  UI.panels.history = { frame = p, refresh = function() UI.RenderHistory() end }
  return p
end

-- Render the active drill-down level into the history panel. Each level builds a
-- flat list of row descriptors; we then draw only the slice that fits the panel
-- (the mouse wheel scrolls the rest), so a long night never spills off the window.
function UI.RenderHistory()
  local p = UI.panels.history and UI.panels.history.frame
  if not p then return end
  local store = histStore()
  local lvl = UI.history.level
  p.back:SetShown(lvl ~= "list")
  p.exportBtn:SetShown(lvl == "night")
  -- a new drill-down level starts at the top
  if UI.history._renderedLevel ~= lvl then UI.history.scroll = 0; UI.history._renderedLevel = lvl end

  local items = {}
  local function add(text, onClick, indent)
    items[#items + 1] = { text = text, onClick = onClick, indent = indent or 6 }
  end

  if lvl == "list" then
    p.title:SetText("Raid History")
    local rows = ns.History.List(store)
    if #rows == 0 then add("No raids recorded yet.") end
    for _, r in ipairs(rows) do
      local when = (date and date("%b %d %H:%M", r.startTime)) or tostring(r.startTime)
      local zone = (r.zones and r.zones[1]) or "Unknown"
      local id = r.raidId
      local pug = store and store.raids and store.raids[id] and store.raids[id].excludeAllTime
      add(zone .. "  \194\183  " .. when .. "  \194\183  " .. r.bodyCount .. " deaths  \194\183  " .. r.wipeCount .. " wipes"
        .. (pug and "  \194\183  |cff8a7d5a(pug)|r" or ""),
        function() UI.history.raidId = id; UI.history.level = "night"; UI.Refresh() end)
    end

  elseif lvl == "night" then
    local rep = ns.History.Report(store, UI.history.raidId, 1)
    if not rep then UI.history.level = "list"; return UI.RenderHistory() end
    p.title:SetText(((rep.meta.zones or {})[1]) or "Raid")
    local m = rep.meta
    add("Body count " .. m.bodyCount .. "  \194\183  " .. m.bossCount .. " bosses  \194\183  " .. m.wipeCount .. " wipes")
    -- pug toggle: keep the raid in History, but in/out of All-Time stats.
    local rid = UI.history.raidId
    local excluded = store and store.raids and store.raids[rid] and store.raids[rid].excludeAllTime
    add(excluded and "|cffd9a566\226\153\166 PUG \226\128\148 excluded from All-Time (click to include)|r"
      or "Mark as PUG \226\128\148 exclude from All-Time", function()
      if ns.DB.SetRaidExcluded then ns.DB.SetRaidExcluded(store, rid, not excluded) end
      UI.Refresh()
    end)
    local low = rep.lowlights or {}
    if low.feeder then add("Feeder: " .. low.feeder .. " (" .. (low.feederDeaths or 0) .. ")") end
    if low.deadliestAbility then add("Deadliest: " .. low.deadliestAbility .. (low.deadliestSource and (" - " .. low.deadliestSource) or "")) end
    if low.firstBlood then add("First blood: " .. low.firstBlood) end
    for _, bb in ipairs(rep.perBoss or {}) do
      add(bb.boss .. ": " .. bb.deaths .. " (" .. (bb.topCause or "?") .. ")")
    end
    add("Deaths (click for killcam):")
    local raid = store and store.raids and store.raids[UI.history.raidId]
    local deaths = (raid and raid.deaths) or {}
    for idx = #deaths, 1, -1 do
      local d = deaths[idx]
      local when = (date and date("%H:%M:%S", d.time)) or tostring(d.time)
      local capture = idx
      add(when .. "  " .. d.player .. " <- " .. (d.ability or "?"),
        function() UI.history.deathIdx = capture; UI.history.level = "killcam"; UI.Refresh() end, 18)
    end

  else -- killcam
    local raid = store and store.raids and store.raids[UI.history.raidId]
    local d = raid and raid.deaths and raid.deaths[UI.history.deathIdx]
    if not d then UI.history.level = "night"; return UI.RenderHistory() end
    p.title:SetText(d.player .. "  \194\183  " .. (d.ability or "?"))
    local rows = ns.Killcam.Format(d.killcam, d.time)
    if #rows == 0 then add("No timeline captured for this death.") end
    for _, ev in ipairs(rows) do
      local amt = ev.amount and ("  " .. ev.amount) or ""
      add(ev.rel .. "  [" .. histKind(ev.kind) .. "]  " .. (ev.spell or "?")
        .. (ev.source and ("  \194\183  " .. ev.source) or "") .. amt)
    end
  end

  -- draw only the visible slice; reserve a bottom line for the scroll hint
  local rowsFit = math.max(1, math.floor(((p:GetHeight() or 300) - 30) / ROWH))
  local overflow = #items > rowsFit
  local vis = math.max(1, overflow and (rowsFit - 1) or rowsFit)
  local maxScroll = math.max(0, #items - vis)
  UI.history._maxScroll = maxScroll
  local off = math.max(0, math.min(UI.history.scroll or 0, maxScroll))
  UI.history.scroll = off

  local n = 0
  for i = 1, vis do
    local it = items[off + i]
    if it then
      n = n + 1
      local b = histRow(p, n)
      b:SetPoint("TOPLEFT", it.indent, -26 - (i - 1) * ROWH)
      b.fs:SetText(it.text); b:SetScript("OnClick", it.onClick)
    end
  end
  if overflow then
    n = n + 1
    local b = histRow(p, n)
    b:SetPoint("BOTTOMLEFT", 6, 4)
    b.fs:SetText(("|cff8a7d5a(%d-%d of %d \194\183 scroll for more)|r"):format(off + 1, math.min(off + vis, #items), #items))
    b:SetScript("OnClick", nil)
  end
  histHideRowsFrom(p, n + 1)
end

-- ----- Export overlay: Discord text + screenshot scorecard -----
local function buildExportFrame(f)
  if UI.exportFrame then return UI.exportFrame end
  local p = CreateFrame("Frame", nil, f.host)
  p:SetAllPoints(f.host); p:SetFrameStrata("DIALOG"); p:Hide()
  local bg = p:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.05, 0.96)

  p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  p.title:SetPoint("TOPLEFT", 6, -6); p.title:SetTextColor(unpack(GOLD))
  p.title:SetText("Export - select text to copy, or screenshot the card")

  p.close = navButton(p, "Close", function() p:Hide() end)
  p.close:SetPoint("TOPRIGHT", -6, -4)

  -- Left: selectable multiline EditBox in a scroll frame.
  local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 6, -30); scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOM", -10, 10)
  local eb = CreateFrame("EditBox", nil, scroll)
  eb:SetMultiLine(true); eb:SetFontObject("GameFontHighlightSmall")
  eb:SetWidth(260); eb:SetAutoFocus(false)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  scroll:SetScrollChild(eb); p.edit = eb

  -- Right: scorecard built from Export.Card sections (FontString rows).
  local card = CreateFrame("Frame", nil, p)
  card:SetPoint("TOPLEFT", p, "TOP", 6, -30); card:SetPoint("BOTTOMRIGHT", -8, 10)
  local cbg = card:CreateTexture(nil, "BACKGROUND")
  cbg:SetAllPoints(); cbg:SetColorTexture(0.1, 0.09, 0.06, 1)
  card.head = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  card.head:SetPoint("TOP", 0, -8); card.head:SetTextColor(unpack(GOLD))
  card.lines = {}
  p.card = card

  UI.exportFrame = p
  return p
end

local function cardLine(card, i)
  local fs = card.lines[i]
  if not fs then
    fs = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT"); card.lines[i] = fs
  end
  fs:Show()
  return fs
end

function UI.OpenExport(raidId)
  local f = UI.frame; if not f then return end
  local store = histStore()
  local rep = ns.History.Report(store, raidId, 1)
  if not rep then return end
  local p = buildExportFrame(f)
  p.edit:SetText(ns.Export.Text(rep))
  p.edit:HighlightText()

  local card = p.card
  card.head:SetText("All Gas No Brakes")
  local y, i = -32, 0
  for _, sec in ipairs(ns.Export.Card(rep)) do
    i = i + 1; local h = cardLine(card, i); h:ClearAllPoints()
    h:SetPoint("TOPLEFT", 10, y); h:SetTextColor(unpack(GOLD)); h:SetText(sec.title); y = y - 16
    for _, row in ipairs(sec.rows) do
      i = i + 1; local fs = cardLine(card, i); fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", 18, y); fs:SetTextColor(unpack(TAN))
      fs:SetText(row.label .. ":  " .. row.value); y = y - 14
    end
    y = y - 4
  end
  for j = i + 1, #card.lines do card.lines[j]:Hide() end
  p:Show()
end

-- A lightweight killcam popup over the content area, driven straight off a death
-- record's stored timeline -- so it works from any view (Death Log, etc.).
function UI.ShowKillcam(death)
  local f = UI.frame
  if not (f and death) then return end
  local p = UI.killcamFrame
  if not p then
    p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", 116, -58); p:SetPoint("BOTTOMRIGHT", -10, 30)
    p:SetFrameStrata("DIALOG")
    local bg = p:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.97)
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.title:SetPoint("TOPLEFT", 6, -6); p.title:SetTextColor(unpack(GOLD))
    p.close = navButton(p, "Close", function() p:Hide() end)
    p.close:SetPoint("TOPRIGHT", -6, -4)
    p.body = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.body:SetPoint("TOPLEFT", 8, -30); p.body:SetPoint("BOTTOMRIGHT", -8, 8)
    p.body:SetJustifyH("LEFT"); p.body:SetJustifyV("TOP")
    UI.killcamFrame = p
  end
  p.title:SetText((death.player or "?") .. "  \194\183  " .. (death.ability or "?"))
  local rows = ns.Killcam.Format(death.killcam, death.time)
  if #rows == 0 then
    p.body:SetText("No timeline captured for this death.")
  else
    local lines = {}
    for _, ev in ipairs(rows) do
      local kind = ev.kind == "heal" and "HEAL" or (ev.kind == "cast" and "CAST" or "DMG")
      local amt = ev.amount and ("  " .. ev.amount) or ""
      lines[#lines + 1] = ev.rel .. "  [" .. kind .. "]  " .. (ev.spell or "?")
        .. (ev.source and ("  \194\183  " .. ev.source) or "") .. amt
    end
    p.body:SetText(table.concat(lines, "\n"))
  end
  p.shownForView = UI.view
  p:Show()
end

function UI.Build()
  if UI.frame then return UI.frame end
  local cfg = ns.cfg or {}
  local f = CreateFrame("Frame", "AGNB_Window", UIParent, "BackdropTemplate")
  f:SetSize(cfg.winW or 640, cfg.winH or 400); f:SetPoint("CENTER")
  f:Hide()   -- new frames are shown by default; build hidden so the first minimap
             -- click opens it (Toggle would otherwise hide a freshly-built frame)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.05, 0.04, 0.02, 0.96); f:SetBackdropBorderColor(0.23, 0.18, 0.09, 1)
  end

  -- resizable, with a bottom-right grip; size persists in config.
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(470, 320, 1100, 820)
  elseif f.SetMinResize then f:SetMinResize(470, 320); f:SetMaxResize(1100, 820) end
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -3, 3)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    if ns.cfg then ns.cfg.winW = math.floor(f:GetWidth() + 0.5); ns.cfg.winH = math.floor(f:GetHeight() + 0.5) end
  end)
  f:SetScript("OnSizeChanged", function() if f:IsShown() then UI.Refresh() end end)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -12); title:SetText(brandName()); title:SetTextColor(unpack(GOLD))
  f.title = title

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", 2, 2)

  -- The interactive tour's highlight + callout are parented to UIParent (so they
  -- can sit beside the window), so closing the window won't hide them on its own.
  -- End the tour when the window closes so they never linger on screen.
  f:HookScript("OnHide", function()
    if ns.Tour and ns.Tour.frame and ns.Tour.frame:IsShown() then ns.Tour.Finish() end
  end)

  -- header divider
  local hd = f:CreateTexture(nil, "ARTWORK"); hd:SetColorTexture(0.23, 0.18, 0.09, 1)
  hd:SetPoint("TOPLEFT", 10, -54); hd:SetPoint("TOPRIGHT", -10, -54); hd:SetHeight(1)

  -- scope toggle (top-right)
  f.scopeBtns = {}
  local prev
  for i = #SCOPES, 1, -1 do
    local sc = SCOPES[i]
    local b = pillButton(f, sc.label, function() UI.scope = sc.id; UI.Refresh() end)
    if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", -28, -14) end
    prev = b
    f.scopeBtns[sc.id] = b
  end

  -- sectioned navigation menu (headers + view items + actions); laid out in Refresh
  f.nav = {}
  for _, def in ipairs(NAV) do
    local entry = { def = def }
    if def.header then
      local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      fs:SetText(def.header:upper()); fs:SetTextColor(0.7, 0.62, 0.36)
      entry.widget, entry.isHeader = fs, true
    else
      local onClick = def.view and function() UI.view = def.view; UI.Refresh() end or def.action
      local b = navButton(f, def.label, onClick)
      b:SetWidth(112); b.fs:SetTextColor(unpack(def.color or TAN))
      entry.widget = b
    end
    f.nav[#f.nav + 1] = entry
  end

  -- sidebar/content divider
  local vd = f:CreateTexture(nil, "ARTWORK"); vd:SetColorTexture(0.23, 0.18, 0.09, 1)
  vd:SetPoint("TOPLEFT", 112, -58); vd:SetPoint("BOTTOMLEFT", 112, 30); vd:SetWidth(1)

  -- content header: a descriptive title of what's shown + a column-header row.
  f.contentTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.contentTitle:SetPoint("TOPLEFT", 120, -60); f.contentTitle:SetTextColor(unpack(GOLD))
  f.colHead = {}
  f.colHead.name = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.colHead.name:SetPoint("TOPLEFT", 144, -78); f.colHead.name:SetJustifyH("LEFT")
  f.colHead.ct = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.colHead.ct:SetPoint("TOPRIGHT", -14, -78); f.colHead.ct:SetWidth(52)
  f.colHead.ct:SetJustifyH("RIGHT"); f.colHead.ct:SetWordWrap(false)
  f.colHead.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.colHead.sub:SetPoint("TOPRIGHT", f.colHead.ct, "TOPLEFT", -8, 0); f.colHead.sub:SetJustifyH("RIGHT"); f.colHead.sub:SetWordWrap(false)
  f.colDivider = f:CreateTexture(nil, "ARTWORK"); f.colDivider:SetColorTexture(0.23, 0.18, 0.09, 1)
  f.colDivider:SetPoint("TOPLEFT", 120, -90); f.colDivider:SetPoint("TOPRIGHT", -12, -90); f.colDivider:SetHeight(1)

  -- scrollable list
  f.content = CreateFrame("Frame", nil, f)
  f.content:SetPoint("TOPLEFT", 120, -94); f.content:SetPoint("BOTTOMRIGHT", -12, 32)
  if f.content.SetClipsChildren then f.content:SetClipsChildren(true) end
  f.content:EnableMouseWheel(true)
  f.list = CreateFrame("Frame", nil, f.content)
  f.list:SetPoint("TOPLEFT", 0, 0); f.list:SetPoint("TOPRIGHT", 0, 0); f.list:SetHeight(1)
  f.scrollOffset = 0
  f.content:SetScript("OnMouseWheel", function(self, delta)
    local visible = self:GetHeight()
    local total = f.listHeight or 0
    local maxOff = math.max(0, total - visible)
    f.scrollOffset = math.min(maxOff, math.max(0, f.scrollOffset - delta * ROWH * 2))
    f.list:SetPoint("TOPLEFT", 0, f.scrollOffset)
  end)
  f.rows = {}

  -- footer lives under the content column (right of the divider) so it never
  -- collides with the sidebar's bottom action buttons.
  f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.footer:SetPoint("BOTTOMLEFT", 120, 13); f.footer:SetPoint("BOTTOMRIGHT", -12, 13)
  f.footer:SetJustifyH("RIGHT")

  -- centered empty-state hint, shown when the active list view has no rows
  f.emptyHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  f.emptyHint:SetPoint("TOPLEFT", f.content, "TOPLEFT", 10, -40)
  f.emptyHint:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", -10, -40)
  f.emptyHint:SetJustifyH("CENTER"); f.emptyHint:SetSpacing(3)
  f.emptyHint:Hide()

  -- panel host: custom views (Book/Report/Settings) fill the content region here;
  -- list views use f.content/f.list above. Panels are registered into UI.panels.
  f.host = CreateFrame("Frame", nil, f)
  f.host:SetPoint("TOPLEFT", 116, -58); f.host:SetPoint("BOTTOMRIGHT", -10, 30)
  f.host:Hide()
  UI.panels = UI.panels or {}   -- id -> { frame = <Frame>, refresh = function() end }
  buildReportPanel(f)
  buildHistoryPanel(f)
  if ns.Config and ns.Config.EmbedOptions then
    ns.Config.EmbedOptions(f.host)
    UI.panels.settings = { frame = ns.optionsPanel, refresh = function() if ns.Config.RefreshOptions then ns.Config.RefreshOptions() end end }
  end
  if ns.BookUI and ns.BookUI.Embed then
    ns.BookUI.Embed(f.host)
    UI.panels.book = { frame = ns.BookUI.frame, refresh = function() if ns.BookUI.Refresh then ns.BookUI.Refresh() end end }
  end
  if ns.Help and ns.Help.Embed then
    ns.Help.Embed(f.host)
    UI.panels.help = { frame = ns.Help.frame, refresh = function() if ns.Help.Refresh then ns.Help.Refresh() end end }
  end

  UI.frame = f
  return f
end

local function getRow(f, i)
  if f.rows[i] then return f.rows[i] end
  local r = CreateFrame("Frame", nil, f.list)
  r:SetHeight(ROWH); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROWH); r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROWH)

  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(unpack(GOLD)); r.bg:SetAlpha(0.06); r.bg:Hide()
  r.div = r:CreateTexture(nil, "ARTWORK"); r.div:SetColorTexture(0.12, 0.10, 0.07, 1)
  r.div:SetPoint("BOTTOMLEFT", 0, 0); r.div:SetPoint("BOTTOMRIGHT", 0, 0); r.div:SetHeight(1)

  r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.rank:SetPoint("LEFT", 2, 0); r.rank:SetWidth(20); r.rank:SetJustifyH("LEFT")

  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("LEFT", 24, 0); r.name:SetWidth(140); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)

  r.ct = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  r.ct:SetPoint("RIGHT", -2, 0); r.ct:SetWidth(52); r.ct:SetJustifyH("RIGHT")

  r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.sub:SetPoint("RIGHT", r.ct, "LEFT", -8, 0); r.sub:SetWidth(132); r.sub:SetJustifyH("RIGHT"); r.sub:SetWordWrap(false)

  -- hover a player (All-Time Deaths) to see their earned death achievements
  r:EnableMouse(true)
  r:SetScript("OnEnter", function(self)
    if self.killcamDeath then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Click for killcam", 0.8, 0.8, 0.8)
      GameTooltip:Show()
      return
    end
    if not self.achPlayer or not ns.Achievements then return end
    local store = select(1, activeData())
    local rec = store and store.allTime and store.allTime[self.achPlayer]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.achPlayer .. " - death achievements")
    local list = ns.Achievements.For(rec)
    if #list == 0 then
      GameTooltip:AddLine("None earned yet.", 0.6, 0.6, 0.6)
    else
      for _, a in ipairs(list) do
        GameTooltip:AddDoubleLine(a.name, a.desc, 1, 0.82, 0.2, 0.6, 0.6, 0.6)
      end
    end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnMouseUp", function(self) if self.killcamDeath then UI.ShowKillcam(self.killcamDeath) end end)

  f.rows[i] = r
  return r
end

local function rowsForView()
  local store, raidId = activeData()
  if not store then return {} end
  local alltime = UI.scope == "alltime"
  if UI.view == "deaths" then
    return alltime and ns.DB.LeaderboardAllTime(store) or ns.DB.LeaderboardTonight(store, raidId)
  elseif UI.view == "abilities" then
    return alltime and ns.DB.AbilityBoardAllTime(store) or ns.DB.AbilityBoard(store, raidId)
  elseif UI.view == "log" then
    return alltime and ns.DB.DeathLogAllTime(store, 50) or ns.DB.DeathLog(store, raidId, 50)
  elseif UI.view == "perboss" then
    local raid = store and raidId and store.raids[raidId]
    local rows = {}
    for _, b in ipairs(ns.Insights.ByBoss(raid and raid.deaths or {})) do
      rows[#rows + 1] = { kind = "boss", data = b }
      if b.phases then for _, ph in ipairs(b.phases) do rows[#rows + 1] = { kind = "phase", data = ph } end end
    end
    return rows
  elseif UI.view == "timeline" then
    local raid = store and raidId and store.raids[raidId]
    local pulls = (ns.Book and ns.Book.RecentPulls and ns.Book.RecentPulls(raid and raid.deaths or {})) or {}
    UI.timelinePull = pulls[1]
    if not UI.timelinePull then return {} end
    local rows = {}
    for _, e in ipairs(ns.Insights.PullTimeline(raid.deaths, UI.timelinePull)) do
      rows[#rows + 1] = { kind = "timeline", data = e }
    end
    return rows
  elseif UI.view == "betting" then
    return ns.DB.BetLeaderboard(store)
  elseif UI.view == "raidinfo" then
    return raidInfoRows()
  end
  return {}
end

local function fillRow(r, i, data, nameW, subW)
  if nameW then r.name:SetWidth(nameW) end
  if subW then r.sub:SetWidth(subW) end
  local listViews = { perboss = true, timeline = true, log = true }
  r.bg:SetShown(i == 1 and not listViews[UI.view])
  r.rank:SetTextColor(unpack(i == 1 and GOLD or DIM))
  if UI.view == "abilities" then
    r.rank:SetText(i .. ".")
    r.name:SetText(data.ability or ""); r.name:SetTextColor(unpack(TAN))
    r.sub:SetText(data.topSource or ""); r.ct:SetText(data.count or "")
  elseif UI.view == "log" then
    r.rank:SetText("")
    r.name:SetText(data.player or ""); r.name:SetTextColor(classColor(data.player))
    local src = data.sourceName and (" \194\183 " .. data.sourceName) or ""
    r.sub:SetText((data.ability or "") .. src); r.ct:SetText("")
  elseif UI.view == "perboss" then
    if data.kind == "boss" then
      local b = data.data
      r.rank:SetText(""); r.name:SetText(b.boss or ""); r.name:SetTextColor(unpack(GOLD))
      local sub = (b.topCause or "")
      if b.topSource then sub = sub .. " \194\183 " .. b.topSource end
      if b.feeder then sub = sub .. "   fed: " .. b.feeder .. " (" .. (b.feederCount or 0) .. ")" end
      r.sub:SetText(sub); r.ct:SetText(b.deaths or "")
    else
      local ph = data.data
      r.rank:SetText("")
      r.name:SetText("   " .. (ph.name or "")); r.name:SetTextColor(unpack(ph.deadliest and GOLD or DIM))
      r.sub:SetText(ph.deadliest and "deadliest" or ""); r.ct:SetText(ph.count or 0)
    end
  elseif UI.view == "timeline" then
    local e = data.data
    r.rank:SetText(""); r.name:SetText(e.player or ""); r.name:SetTextColor(classColor(e.player))
    r.sub:SetText(e.cause or "")
    local off = e.offset or 0; if off < 0 then off = 0 end
    r.ct:SetText(("+%d:%02d"):format(math.floor(off / 60), off % 60))
  elseif UI.view == "betting" then
    r.rank:SetText(i .. ".")
    r.name:SetText(data.player or ""); r.name:SetTextColor(classColor(data.player))
    r.sub:SetText(("%dW / %dL"):format(data.w or 0, data.l or 0))
    local net = data.net or 0
    r.ct:SetText((net >= 0 and "+" or "") .. net .. "g")
  elseif UI.view == "raidinfo" then
    r.rank:SetText("")
    r.name:SetText(data.player or ""); r.name:SetTextColor(classColor(data.player))
    -- role + admin + online (sub column)
    local role = data.isLeader and "Leader" or (data.isAssist and "Assist" or "")
    if data.isAdmin then role = (role ~= "" and (role .. " \194\183 ") or "") .. "|cffffd966Book admin|r" end
    if not data.online then role = (role ~= "" and (role .. " \194\183 ") or "") .. "|cff888888offline|r" end
    r.sub:SetText(role)
    -- addon version (count column); green if current, yellow if a different version
    if data.hasAddon then
      local outdated = data.version ~= ns.version
      r.ct:SetText("v" .. tostring(data.version))
      if outdated then r.ct:SetTextColor(0.95, 0.82, 0.25) else r.ct:SetTextColor(0.45, 0.9, 0.45) end
    else
      r.ct:SetText("none"); r.ct:SetTextColor(0.55, 0.42, 0.42)
    end
  else -- deaths
    r.rank:SetText(i .. ".")
    r.name:SetText(data.player or ""); r.name:SetTextColor(classColor(data.player))
    local src = data.topSource and (" \194\183 " .. data.topSource) or ""
    r.sub:SetText((data.topCause or "") .. src); r.ct:SetText(data.deaths or "")
  end
  -- achievements tooltip only meaningful on the All-Time deaths board
  r.achPlayer = (UI.scope == "alltime" and UI.view == "deaths") and data.player or nil
  -- Death Log rows are clickable to pop the killcam for that death
  r.killcamDeath = (UI.view == "log") and data or nil
end

function UI.Refresh()
  local f = UI.frame
  if not f or not f:IsShown() then return end
  f.title:SetText(brandName())

  for _, sc in ipairs(SCOPES) do
    f.scopeBtns[sc.id].fs:SetTextColor(unpack(sc.id == UI.scope and GOLD or MUTED))
    f.scopeBtns[sc.id]:SetShown(SCOPED_VIEWS[UI.view] and true or false)
  end
  layoutNav(f)

  -- the export overlay belongs only to the History view; never let it linger over
  -- another panel after the user navigates away.
  if UI.exportFrame and UI.view ~= "history" then UI.exportFrame:Hide() end
  if UI.killcamFrame and UI.killcamFrame:IsShown() and UI.killcamFrame.shownForView ~= UI.view then
    UI.killcamFrame:Hide()
  end

  local isList = LIST_VIEWS[UI.view] and true or false
  showListChrome(f, isList)
  if isList then
    f.host:Hide()
  else
    f.host:Show()
    for id, p in pairs(UI.panels) do if p.frame then p.frame:SetShown(id == UI.view) end end
    local p = UI.panels[UI.view]
    if p and p.refresh then p.refresh() end
    return   -- panels render themselves; skip the list rendering below
  end

  -- responsive column widths from the live content width. Player names are short,
  -- so cap the name column and give the rest (the long SPELL - MOB text) to the sub.
  local cw = (f.content:GetWidth() or 360)
  local avail = math.max(180, cw - 24 - 52 - 10)   -- minus rank gutter, count col, gaps
  local nameW = math.max(90, math.min(150, math.floor(avail * 0.32)))
  local subW = math.max(90, avail - nameW)

  -- descriptive title + column headers for the current scope/view
  local scopeLabel = (UI.scope == "alltime") and "All-Time" or "Tonight"
  local store0, raidId0 = activeData()
  local zone = (UI.scope ~= "alltime" and store0 and store0.raids[raidId0] and store0.raids[raidId0].zone) or nil
  local titles = { deaths = "Deaths", abilities = "Abilities", log = "Death Log",
                   perboss = "Per-Boss", timeline = "Pull Timeline", betting = "Bet Records" }
  f.contentTitle:SetText(scopeLabel .. "  \194\183  " .. (titles[UI.view] or "")
    .. (zone and ("  \194\183  " .. zone) or ""))
  if UI.view == "timeline" and UI.timelinePull then
    f.contentTitle:SetText(("Pull \194\183 %s"):format(tostring(UI.timelinePull.boss or "?")))
  end
  if UI.view == "betting" then
    f.contentTitle:SetText("Bet Records  \194\183  all-time")
  end
  if UI.view == "raidinfo" then
    f.contentTitle:SetText("Raid Info  \194\183  who's on the addon")
  end
  -- in All-Time the spell/mob column is each player's most-common killer, so label
  -- it as a nemesis rather than a single death.
  local deathsSub = (UI.scope == "alltime") and "NEMESIS" or "SPELL \194\183 MOB"
  local heads = {
    deaths    = { "PLAYER", deathsSub, "DEATHS" },
    abilities = { "ABILITY", "TOP CASTER", "DEATHS" },
    log       = { "PLAYER", "SPELL \194\183 MOB", "" },
    perboss   = { "BOSS / PHASE", "DEADLIEST \194\183 FED", "DEATHS" },
    timeline  = { "PLAYER", "CAUSE", "AT" },
    betting   = { "PLAYER", "W / L", "NET" },
    raidinfo  = { "PLAYER", "ROLE", "ADDON" },
  }
  local h = heads[UI.view] or heads.deaths
  f.colHead.name:SetText(h[1]); f.colHead.sub:SetText(h[2]); f.colHead.sub:SetWidth(subW)
  f.colHead.ct:SetText(h[3])

  local rows = rowsForView()
  if #rows == 0 then
    local msg = EMPTY_HINTS[UI.view] or "Nothing here yet."
    if UI.view == "betting" and not (ns.cfg and ns.cfg.bookEnabled) then
      msg = "Wagering is off.\nEnable it in Settings to run Over/Under, First Blood, and the Death Draft."
    end
    f.emptyHint:SetText(msg); f.emptyHint:Show()
  else
    f.emptyHint:Hide()
  end
  for i = 1, math.max(#rows, #f.rows) do
    local data = rows[i]
    if not data then
      if f.rows[i] then f.rows[i]:Hide() end
    else
      local r = getRow(f, i); r:Show(); fillRow(r, i, data, nameW, subW)
    end
  end
  f.listHeight = #rows * ROWH
  f.list:SetHeight(math.max(1, f.listHeight))
  f.scrollOffset = 0; f.list:SetPoint("TOPLEFT", 0, 0)

  local store, raidId = activeData()
  if UI.view == "raidinfo" then
    local withAddon, admin = 0, nil
    for _, m in ipairs(rows) do
      if m.hasAddon then withAddon = withAddon + 1 end
      if m.isAdmin then admin = m.player end
    end
    f.footer:SetText(("%d of %d on the addon%s"):format(withAddon, #rows,
      admin and ("  |  Admin: " .. admin) or "  |  no admin set"))
  elseif UI.scope == "alltime" then
    local total = 0
    if store then for _, p in pairs(store.allTime) do total = total + (p.deaths or 0) end end
    f.footer:SetText(("All-time body count: %d"):format(total))
  else
    local body = 0
    if store and store.raids[raidId] then
      for _, d in ipairs(store.raids[raidId].deaths) do
        if d.classification ~= "wipeCascade" then body = body + 1 end
      end
    end
    local pot = body * ((ns.cfg and ns.cfg.buyIn) or 1)
    f.footer:SetText(("%d bodies tonight  |  Pot %dg"):format(body, pot))
  end
end

function UI.Toggle()
  UI.Build()
  if UI.frame:IsShown() then UI.frame:Hide() else UI.frame:Show(); UI.Refresh() end
end

-- ----- chat reports (demo-aware) -----
-- opts (optional) overrides config for a single post: { channel, topN, emoji }.
function UI.DoReportType(kind, opts)
  local store, raidId = activeData()
  if not store then return end
  opts = opts or {}
  local cfg = ns.cfg or {}
  local brand = brandName()
  local emoji = cfg.reportEmoji ~= false
  if opts.emoji ~= nil then emoji = opts.emoji end
  local topN = opts.topN or cfg.reportTopN or 5
  local lines
  if kind == "alltime" then
    lines = ns.Report.BuildAllTime(ns.DB.LeaderboardAllTime(store), { brand = brand, topN = topN, emoji = emoji })
  elseif kind == "lowlights" then
    local raid = store.raids[raidId]
    lines = raid and ns.Report.BuildLowlights(ns.Ledger.Lowlights(raid), { brand = brand, emoji = emoji }) or {}
  elseif kind == "ledger" then
    local board = ns.DB.LeaderboardTonight(store, raidId)
    local counts = {}; for _, b in ipairs(board) do counts[b.player] = b.deaths end
    local participants = ns.AntiPrize and ns.AntiPrize.Participants() or nil
    lines = ns.Report.BuildLedger(ns.Ledger.Settlement(counts, cfg.buyIn or 1, participants), { brand = brand, emoji = emoji })
  else
    local board = ns.DB.LeaderboardTonight(store, raidId)
    local zone = (GetRealZoneText and GetRealZoneText()) or "the raid"
    lines = ns.Report.BuildTonight(board, { brand = brand, zone = zone, topN = topN, emoji = emoji })
  end
  local chan = opts.channel or cfg.reportChannel or "SELF"
  for i, line in ipairs(lines or {}) do
    ns.After((i - 1) * 0.3, function()
      if chan == "SELF" or not SendChatMessage then ns.Print(line) else SendChatMessage(line, chan) end
    end)
  end
end

-- The sidebar Report button posts the report matching the current scope/view.
function UI.DoReportCurrent()
  if UI.view == "abilities" then ns.Print("Report is for the Deaths leaderboard (Tonight/All-Time).") end
  UI.DoReportType(UI.scope == "alltime" and "alltime" or "tonight")
end

-- legacy alias kept for the /agnb path
function UI.DoReport() UI.DoReportType("tonight") end

-- Open the main window on the Settings view. Uses Build+Show (not Toggle) so
-- this always ends up shown even if the window was already open (Toggle would
-- close it instead). External callers such as the Summary popup use this path.
function UI.OpenConfig()
  UI.Build()
  UI.frame:Show()
  UI.SetView("settings")
end

-- ----- Post-to-chat dialog: pick report / channel / depth, then post -----
function UI.OpenPostDialog()
  local d = UI.postDlg
  if not d then
    d = CreateFrame("Frame", "AGNB_PostDialog", UIParent, "BackdropTemplate")
    d:SetSize(330, 224); d:SetPoint("CENTER"); d:SetFrameStrata("DIALOG"); d:SetToplevel(true)
    d:SetMovable(true); d:EnableMouse(true); d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving); d:SetScript("OnDragStop", d.StopMovingOrSizing)
    if d.SetBackdrop then
      d:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
      d:SetBackdropColor(0.05, 0.04, 0.02, 0.98); d:SetBackdropBorderColor(0.23, 0.18, 0.09, 1)
    end
    CreateFrame("Button", nil, d, "UIPanelCloseButton"):SetPoint("TOPRIGHT", 2, 2)
    local t = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -14); t:SetText("Post Report to Chat"); t:SetTextColor(unpack(GOLD))

    d.sel, d.dds = {}, {}
    local function mkdd(label, key, options, y)
      local lbl = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      lbl:SetPoint("TOPLEFT", 18, y); lbl:SetText(label)
      local dd = CreateFrame("Frame", "AGNB_PostDD_" .. key, d, "UIDropDownMenuTemplate")
      dd:SetPoint("TOPLEFT", 92, y + 4)
      UIDropDownMenu_SetWidth(dd, 160)
      UIDropDownMenu_Initialize(dd, function()
        for _, o in ipairs(options) do
          local info = UIDropDownMenu_CreateInfo()
          info.text, info.value = o.label, o.value
          info.checked = (d.sel[key] == o.value)
          info.func = function()
            d.sel[key] = o.value
            UIDropDownMenu_SetSelectedValue(dd, o.value)
            UIDropDownMenu_SetText(dd, o.label)
          end
          UIDropDownMenu_AddButton(info)
        end
      end)
      d.dds[key] = { dd = dd, options = options }
    end
    mkdd("Report", "kind", POST_TYPES, -48)
    mkdd("Channel", "channel", ns.Config.CHANNELS, -94)
    mkdd("Depth", "topN", ns.Config.TOPN, -140)

    local post = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    post:SetSize(120, 22); post:SetPoint("BOTTOMRIGHT", -16, 16); post:SetText("Post")
    post:SetScript("OnClick", function()
      UI.DoReportType(d.sel.kind, { channel = d.sel.channel, topN = d.sel.topN })
    end)
    local close = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    close:SetSize(90, 22); close:SetPoint("RIGHT", post, "LEFT", -8, 0); close:SetText("Close")
    close:SetScript("OnClick", function() d:Hide() end)
    UI.postDlg = d
  end
  -- defaults from the current scope + saved config; refresh the dropdown labels.
  d.sel.kind = (UI.scope == "alltime") and "alltime" or "tonight"
  d.sel.channel = (ns.cfg and ns.cfg.reportChannel) or "SELF"
  d.sel.topN = (ns.cfg and ns.cfg.reportTopN) or 5
  for key, e in pairs(d.dds) do
    UIDropDownMenu_SetSelectedValue(e.dd, d.sel[key])
    UIDropDownMenu_SetText(e.dd, labelOf(e.options, d.sel[key]))
  end
  d:Show()
end

-- ----- settle mail (demo-aware) -----
function UI.SettleMail()
  local store, raidId = activeData()
  local board = ns.DB.LeaderboardTonight(store, raidId)
  local counts = {}; for _, b in ipairs(board) do counts[b.player] = b.deaths end
  local participants = ns.AntiPrize and ns.AntiPrize.Participants() or nil
  local settle = ns.Ledger.Settlement(counts, (ns.cfg and ns.cfg.buyIn) or 1, participants)
  local me = UnitName and UnitName("player") or nil
  local mine = me and settle.owes[me]
  if not mine then ns.Print("You owe the pot nothing. Smug.") return end
  if not (MailFrame and MailFrame:IsShown()) then
    ns.Print(("You owe %s %dg. Open a mailbox and click Settle again to pre-fill it."):format(mine.to, mine.amount))
    return
  end
  if MailFrameTab2 then MailFrameTab2:Click() end
  if SendMailNameEditBox then SendMailNameEditBox:SetText(mine.to) end
  if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText("Anti-prize settlement") end
  if MoneyInputFrame_SetCopper and SendMailMoney then MoneyInputFrame_SetCopper(SendMailMoney, mine.amount * 10000) end
  ns.Print(("Pre-filled mail: %dg to %s. Click Send."):format(mine.amount, mine.to))
end

-- ----- minimap button -----
-- Place the button on the minimap ring at `angle` degrees.
local function minimapPosition(b, angle)
  local rad = math.rad(angle)
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(rad), 80 * math.sin(rad))
end

local function buildMinimap()
  local b = CreateFrame("Button", "AGNB_MinimapButton", Minimap)
  b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")

  -- skull icon framed by the standard tracking border. The border art frames a
  -- region offset toward the lower-right, so the icon must sit at the proven
  -- LibDBIcon offset (TOPLEFT 7,-6) -- centering it hides it behind the border ring.
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20); bg:SetPoint("TOPLEFT", 7, -5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  -- The brand's crowned skull, exported from the logo as a 32-bit uncompressed
  -- TGA (top-left origin). A bare 'INV_Misc_Bone_Skull' path failed to resolve on
  -- the Anniversary client and rendered black, so we ship our own texture. The art
  -- is already tightly framed with transparency, so no TexCoord crop is needed.
  icon:SetTexture("Interface\\AddOns\\AllGasNoBrakes\\Media\\minimap-skull-64.tga")
  icon:SetSize(20, 20); icon:SetPoint("TOPLEFT", 6, -5)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53); border:SetPoint("TOPLEFT")

  minimapPosition(b, (ns.cfg and ns.cfg.minimapAngle) or 204)

  -- drag around the ring; persist the angle.
  local function onDragUpdate(self)
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if not (mx and px and scale and scale > 0) then return end
    local a = math.deg(math.atan2(py / scale - my, px / scale - mx))
    if ns.cfg then ns.cfg.minimapAngle = a end
    minimapPosition(self, a)
  end
  b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then UI.OpenConfig() else UI.Toggle() end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("AGNB Raid Death Tracker")
    GameTooltip:AddLine("Left-click: open window", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: settings  \194\183  drag: move", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

ns.OnInit(function()
  ns.MyName = UnitName and UnitName("player") or nil
  if Minimap then buildMinimap() end
  -- drop cached class colors when the roster changes so new raiders get colored
  local rf = CreateFrame("Frame")
  rf:RegisterEvent("GROUP_ROSTER_UPDATE")
  rf:SetScript("OnEvent", function() classColorCache = {} end)
end)
