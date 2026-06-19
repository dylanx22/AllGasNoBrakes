local _, ns = ...
ns = ns or __AGNB_NS
ns.Config = ns.Config or {}
local CFG = ns.Config

CFG.DEFAULTS = {
  announceEnabled = false,     -- off until user opts in
  announceChannel = "SELF",    -- SELF/PARTY/RAID/GUILD/SAY
  announceWindow = 5,          -- burst-throttle seconds
  -- Per-announcement toggles (all opt-in) + channel (default private SELF).
  announce_death = false,        announceChan_death = "SELF",
  announce_combobreaker = false, announceChan_combobreaker = "SELF",
  announce_streak = false,       announceChan_streak = "SELF",
  announce_achievement = false,  announceChan_achievement = "SELF",
  announce_milestone = false,    announceChan_milestone = "SELF",
  announce_survival = false,     announceChan_survival = "SELF",
  soundEnabled = true,
  syncEnabled = true,
  forgiveWipeDeaths = true,
  wipeThresholdPct = 50,
  onlyInstances = true,
  raidOnly = false,            -- only raid instances (ignore 5-man dungeons)
  guildOnly = false,           -- only track deaths of guild members
  combatOnly = true,
  buyIn = 1,                   -- gold per death (ledger only)
  antiPrizeOptIn = false,      -- opt-in: never owe the anti-prize pot unless you join
  reportChannel = "SELF",
  reportTopN = 5,
  reportEmoji = true,
  showTitles = true,
  wipeBannerEnabled = true,
  wipeBannerStyle = "gold",
  wipeBannerSeconds = 4,
  wipeBannerSound = true,
  wipeTagline = "ALL GAS, NO BRAKES",
  autoSummaryOnFinalBoss = true,
  brandName = "",
  streakThreshold = 3,
  debugLevel = "error",
  winW = 580,                  -- main window size (persisted on resize)
  winH = 400,
  minimapAngle = 204,          -- minimap button position (degrees around the ring)
  seenWelcome = false,         -- first-run welcome shown once
  -- The Book (wagering)
  bookEnabled = false,         -- opt-in, off by default
  bookStakeOU = 5,             -- admin-set flat stakes (gold)
  bookStakeFB = 5,
  bookDraftAnte = 10,
  bookMaxBetPct = 50,          -- USER bankroll cap (% of gold); 0 = no cap
  bookAutoOpenOnReadyCheck = true,
  bookLineWindow = 5,          -- pulls of history used for the auto O/U line
  bookLineFallback = 0.5,      -- lowest line when there's no history
  collusionWatch = true,       -- flag suspicious bet-fixing chatter to the admin
}

-- Copy defaults into saved without overwriting existing keys. Returns saved.
function CFG.ApplyDefaults(saved)
  saved = saved or {}
  for k, v in pairs(CFG.DEFAULTS) do
    if saved[k] == nil then saved[k] = v end
  end
  return saved
end

-- Split "sub rest of args" -> "sub", "rest of args".
function CFG.ParseSlash(msg)
  msg = (msg or ""):gsub("^%s+", "")
  local sub, rest = msg:match("^(%S*)%s*(.*)$")
  return sub or "", rest or ""
end

-- ----- WoW glue: slash commands -----
local function handleSlash(msg)
  local sub, rest = CFG.ParseSlash(msg)
  if sub == "" or sub == "show" then
    ns.UI.Toggle()
  elseif sub == "report" then
    local kind = (rest ~= "" and rest:match("^%S+")) or "tonight"
    ns.UI.DoReportType(kind)
  elseif sub == "summary" then
    ns.Summary.Show()
  elseif sub == "ledger" then
    ns.UI.DoReportType("ledger")
  elseif sub == "invite" or sub == "pot" then
    if ns.AntiPrize then ns.AntiPrize.Invite() end
  elseif sub == "book" then
    local arg, arg1, arg2 = rest:match("^(%S*)%s*(%S*)%s*(%S*)")
    if arg == "open" then ns.Book.OpenRound()
    elseif arg == "draft" then ns.Book.OpenDraft()
    elseif arg == "join" then ns.Book.JoinDraft()
    elseif arg == "lock" then ns.Book.LockDraft()
    elseif arg == "report" then
      if ns.Book and ns.Book.ReportLastFlag then ns.Book.ReportLastFlag() end
    elseif arg == "close" then
      if ns.Book and ns.Book.CloseBook then ns.Book.CloseBook() end
    elseif arg == "paid" then
      if ns.Settlement and ns.Settlement.MarkPaid then ns.Settlement.MarkPaid(arg1) end
    elseif arg == "void" then
      if ns.Book and ns.Book.IgnorePull then ns.Book.IgnorePull(tonumber(arg1) or 0, tonumber(arg2) or 0) end
    elseif arg == "admin" then
      if arg1 == "clear" then if ns.Book.ClearAdmin then ns.Book.ClearAdmin() end
      elseif arg1 ~= "" then if ns.Book.SetAdmin then ns.Book.SetAdmin(arg1) end
      else ns.Print("Usage: /agnb book admin <name> | /agnb book admin clear") end
    else if ns.BookUI then ns.BookUI.Toggle() end end
  elseif sub == "mock" then
    if rest:match("off") then ns.Demo.Clear() else ns.Demo.Load() end
  elseif sub == "phasedebug" then
    if ns.PhaseTracker and ns.PhaseTracker.ToggleDebug then ns.PhaseTracker.ToggleDebug() end
  elseif sub == "void" then
    local removed, pull = ns.DB.VoidLastPull(ns.db.store, ns.Tracking.raidId)
    ns.Print(("Voided pull %d (%d death%s)."):format(pull, removed, removed == 1 and "" or "s"))
    if ns.UI then ns.UI.Refresh() end
  elseif sub == "config" or sub == "options" then
    -- Settings is embedded in the main window now; route to the in-window view.
    if ns.UI and ns.UI.OpenConfig then ns.UI.OpenConfig() end
  elseif sub == "debug" then
    local arg = rest:match("^(%S+)")
    if arg == "clear" then ns.Debug.Clear()
    elseif arg == "level" then ns.Debug.SetLevel(rest:match("^level%s+(%S+)"))
    else ns.Debug.Show() end
  elseif sub == "welcome" then
    if ns.Welcome and ns.Welcome.Show then ns.Welcome.Show() end
  elseif sub == "tour" then
    if ns.Tour and ns.Tour.Start then ns.Tour.Start() end
  else
    ns.Print("commands: /agnb [show | report <tonight|alltime|lowlights|ledger> | summary | ledger | invite | void | config | debug]")
  end
end

-- Channel choices shared by the report + announce dropdowns. SELF = print only
-- to your own chat frame (nothing is sent to others).
CFG.CHANNELS = {
  { value = "SELF",  label = "Just me (self)" },
  { value = "SAY",   label = "Say" },
  { value = "PARTY", label = "Party" },
  { value = "RAID",  label = "Raid" },
  { value = "GUILD", label = "Guild" },
}
-- Report depth. "All" is stored as a large number so math.min(topN, #board) works.
CFG.TOPN = {
  { value = 3,   label = "Top 3" },
  { value = 5,   label = "Top 5" },
  { value = 10,  label = "Top 10" },
  { value = 999, label = "Everyone" },
}
CFG.BANNER_STYLES = {
  { value = "gold",   label = "Gold" },
  { value = "redline", label = "Redline" },
  { value = "hazard", label = "Hazard" },
  { value = "frost",  label = "Frostline" },
}
CFG.DEBUG_LEVELS = {
  { value = "off",   label = "Off" },
  { value = "error", label = "Errors only" },
  { value = "info",  label = "Info" },
  { value = "debug", label = "Debug (verbose)" },
}

-- ----- declarative settings layout (drives the tabbed panel + coverage test) -----
-- Keys that MUST be surfaced as user-facing controls (excludes internal/persisted
-- state: winW/winH/minimapAngle/bookLineFallback/seenWelcome and the legacy
-- announceEnabled/announceChannel which the per-kind toggles replaced).
CFG.USER_FACING_KEYS = {
  -- tracking
  "syncEnabled", "onlyInstances", "raidOnly", "guildOnly", "combatOnly",
  "forgiveWipeDeaths", "wipeThresholdPct", "showTitles", "brandName",
  -- chat
  "soundEnabled", "announceWindow", "streakThreshold",
  "reportChannel", "reportTopN", "reportEmoji",
  "announce_death", "announceChan_death",
  "announce_combobreaker", "announceChan_combobreaker",
  "announce_streak", "announceChan_streak",
  "announce_achievement", "announceChan_achievement",
  "announce_milestone", "announceChan_milestone",
  "announce_survival", "announceChan_survival",
  -- overlays
  "wipeBannerEnabled", "wipeBannerSound", "wipeBannerStyle", "wipeBannerSeconds",
  "wipeTagline", "autoSummaryOnFinalBoss",
  -- gold & the book
  "antiPrizeOptIn", "buyIn", "bookEnabled", "bookAutoOpenOnReadyCheck",
  "collusionWatch", "bookStakeOU", "bookStakeFB", "bookDraftAnte",
  "bookMaxBetPct", "bookLineWindow",
  -- advanced
  "debugLevel",
}

CFG.SETTINGS_LAYOUT = {
  { id = "tracking", label = "Tracking", groups = { { controls = {
    { kind = "check", key = "syncEnabled",       label = "Sync deaths with other raiders", help = "syncEnabled" },
    { kind = "check", key = "onlyInstances",     label = "Only track deaths in instances (never PvP)", help = "onlyInstances" },
    { kind = "check", key = "raidOnly",          label = "Only track raid instances (ignore 5-man dungeons)", help = "raidOnly" },
    { kind = "check", key = "guildOnly",         label = "Only track deaths of guild members", help = "guildOnly" },
    { kind = "check", key = "combatOnly",        label = "Only track deaths in combat", help = "combatOnly" },
    { kind = "check", key = "forgiveWipeDeaths", label = "Forgive wipe-cascade deaths", help = "forgiveWipeDeaths" },
    { kind = "edit",  key = "wipeThresholdPct",  label = "Wipe-cascade threshold (%)", numeric = true, help = "wipeThresholdPct" },
    { kind = "check", key = "showTitles",        label = "Show earned death titles", help = "showTitles" },
    { kind = "edit",  key = "brandName",         label = "Raid / group name", wide = true, help = "brandName" },
  } } } },

  { id = "chat", label = "Chat", groups = {
    { header = "Reports", controls = {
      { kind = "dropdown", key = "reportChannel", label = "Report channel", options = CFG.CHANNELS, help = "reportChannel" },
      { kind = "dropdown", key = "reportTopN",    label = "Report depth", options = CFG.TOPN, help = "reportTopN" },
      { kind = "check",    key = "reportEmoji",   label = "Decorate reports with a \194\187 accent", help = "reportEmoji" },
    } },
    { header = "Announcements", controls = {
      { kind = "check", key = "soundEnabled",    label = "Play a sound on death", help = "soundEnabled" },
      { kind = "edit",  key = "announceWindow",  label = "Announce window (seconds)", numeric = true, help = "announceWindow" },
      { kind = "edit",  key = "streakThreshold", label = "Streak threshold (pulls)", numeric = true, help = "streakThreshold" },
      { kind = "announceTable" },
    } },
  } },

  { id = "overlays", label = "Overlays", groups = { { controls = {
    { kind = "check",    key = "wipeBannerEnabled", label = "Show the wipe banner", help = "wipeBannerEnabled" },
    { kind = "check",    key = "wipeBannerSound",   label = "Play the wipe-banner sound", help = "wipeBannerSound" },
    { kind = "dropdown", key = "wipeBannerStyle",   label = "Banner style", options = CFG.BANNER_STYLES, help = "wipeBannerStyle" },
    { kind = "edit",     key = "wipeBannerSeconds", label = "Banner duration (seconds)", numeric = true, help = "wipeBannerSeconds" },
    { kind = "edit",     key = "wipeTagline",       label = "Banner tagline", wide = true, help = "wipeTagline" },
    { kind = "check",    key = "autoSummaryOnFinalBoss", label = "Auto-open the summary after a final-boss kill", help = "autoSummaryOnFinalBoss" },
  } } } },

  { id = "gold_book", label = "Gold & The Book", groups = {
    { header = "Gold pot", controls = {
      { kind = "check", key = "antiPrizeOptIn", label = "Join the anti-prize gold pot (opt-in)", help = "antiPrizeOptIn", onChange = "antiPrize" },
      { kind = "edit",  key = "buyIn",          label = "Buy-in per death (gold)", numeric = true, help = "buyIn" },
    } },
    { header = "Wagering", controls = {
      { kind = "check", key = "bookEnabled",             label = "Enable wagering (Over/Under, First Blood, Draft)", help = "bookEnabled" },
      { kind = "check", key = "bookAutoOpenOnReadyCheck", label = "Auto-open a betting round on ready check", help = "bookAutoOpenOnReadyCheck", admin = true },
      { kind = "check", key = "collusionWatch",          label = "Flag suspicious bet-fixing chatter to the admin", help = "collusionWatch", admin = true },
      { kind = "edit",  key = "bookStakeOU",   label = "Over/Under stake (gold)", numeric = true, help = "bookStakeOU", admin = true },
      { kind = "edit",  key = "bookStakeFB",   label = "First Blood stake (gold)", numeric = true, help = "bookStakeFB", admin = true },
      { kind = "edit",  key = "bookDraftAnte", label = "Death Draft ante (gold)", numeric = true, help = "bookDraftAnte", admin = true },
      { kind = "edit",  key = "bookMaxBetPct", label = "My bankroll cap (%)", numeric = true, help = "bookMaxBetPct" },
      { kind = "edit",  key = "bookLineWindow", label = "Auto-line history (pulls)", numeric = true, help = "bookLineWindow", admin = true },
    } },
  } },

  { id = "advanced", label = "Advanced", groups = { { controls = {
    { kind = "dropdown", key = "debugLevel", label = "Debug log level", options = CFG.DEBUG_LEVELS, help = "debugLevel", onChange = "debug" },
  } } } },
}

-- Set of every key the layout covers -> tab id. Expands the announce table to its
-- per-kind toggle+channel pair. Asserts no key is placed in two tabs.
function CFG.CoveredKeys()
  local covered = {}
  local function put(key, tabId)
    if covered[key] then error("setting in two tabs: " .. key) end
    covered[key] = tabId
  end
  for _, tab in ipairs(CFG.SETTINGS_LAYOUT) do
    for _, group in ipairs(tab.groups) do
      for _, c in ipairs(group.controls) do
        if c.kind == "announceTable" then
          for _, k in ipairs(ns.Announce.KINDS) do
            put("announce_" .. k.key, tab.id)
            put("announceChan_" .. k.key, tab.id)
          end
        elseif c.key then
          put(c.key, tab.id)
        end
      end
    end
  end
  return covered
end

-- Reload prompt: most settings apply immediately, but anything that needs a UI
-- reload to fully take effect calls CFG.PromptReload() to offer a one-click reload.
if StaticPopupDialogs then
  StaticPopupDialogs["AGNB_RELOAD"] = {
    text = "All Gas No Brakes: that change needs a UI reload to fully apply.",
    button1 = "Reload now", button2 = "Later",
    OnAccept = function() if ReloadUI then ReloadUI() end end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
end
function CFG.PromptReload()
  if StaticPopup_Show then StaticPopup_Show("AGNB_RELOAD")
  else ns.Print("This change needs a /reload to fully apply.") end
end

-- ----- WoW glue: a scrollable options panel covering every implemented feature -----
local function buildOptions()
  local panel = CreateFrame("Frame")
  panel.name = "All Gas No Brakes"

  local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  header:SetPoint("TOPLEFT", 16, -16); header:SetText("All Gas No Brakes: Death Tracker")
  local subt = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  subt:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
  subt:SetText("Settings apply immediately. Use Reload UI if anything looks stale.")

  local reloadBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  reloadBtn:SetSize(90, 22); reloadBtn:SetPoint("TOPRIGHT", -20, -16); reloadBtn:SetText("Reload UI")
  reloadBtn:SetScript("OnClick", function() if ReloadUI then ReloadUI() end end)

  -- everything lives in a scroll child so the full control set always fits.
  local scroll = CreateFrame("ScrollFrame", "AGNB_OptScroll", panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -52); scroll:SetPoint("BOTTOMRIGHT", -30, 12)
  local child = CreateFrame("Frame", "AGNB_OptChild", scroll)
  child:SetSize(560, 10); scroll:SetScrollChild(child)

  local y = -4
  local idx = 0
  local refreshers = {}   -- re-sync each control from cfg when the panel is shown
  function CFG.RefreshOptions() for _, fn in ipairs(refreshers) do fn() end end
  -- Admin-only settings (book stakes, line window, collusion watch) only take
  -- effect for whoever runs The Book, so non-admins see them greyed and locked.
  local function canAdminNow()
    if ns.Book and ns.Book.CanAdmin then return ns.Book.CanAdmin() end
    return true
  end
  -- Lock/unlock a control on refresh based on admin rank, restoring the label's
  -- original colour when unlocked. `enable`/`disable` toggle the widget itself.
  local function registerAdminGate(label, enable, disable)
    local r, g, b = 1, 0.82, 0.2
    if label then r, g, b = label:GetTextColor() end
    refreshers[#refreshers + 1] = function()
      if canAdminNow() then enable(); if label then label:SetTextColor(r, g, b) end
      else disable(); if label then label:SetTextColor(0.5, 0.5, 0.5) end end
    end
  end
  -- A small "?" to the right of `anchor` that shows tooltip text on hover.
  local function helpMarker(parent, anchor, helpKey)
    if not (helpKey and ns.Help and ns.Help.SETTING and ns.Help.SETTING[helpKey]) then return end
    local q = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    q:SetText("|cff66ccff(?)|r"); q:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetAllPoints(q); btn:EnableMouse(true)
    btn:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(ns.Help.SETTING[helpKey], 1, 1, 1, true)
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  local function section(title, parent)
    parent = parent or child
    y = y - 10
    local s = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    s:SetPoint("TOPLEFT", 10, y); s:SetTextColor(1, 0.82, 0.2); s:SetText(title)
    y = y - 22
  end
  local function checkbox(key, label, onChange, help, parent, adminOnly)
    parent = parent or child
    idx = idx + 1
    local name = "AGNB_Opt" .. idx
    local cb = CreateFrame("CheckButton", name, parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 14, y); y = y - 26
    -- TBC Classic exposes the label as the named "<name>Text" fontstring, not cb.Text.
    local fs = _G[name .. "Text"] or cb.Text
    if fs then fs:SetText(label) end
    local function seed() cb:SetChecked(ns.cfg[key]) end
    seed()
    cb:HookScript("OnShow", seed)
    refreshers[#refreshers + 1] = seed
    cb:SetScript("OnClick", function(self)
      local v = self:GetChecked() and true or false
      ns.cfg[key] = v
      if onChange then onChange(v) end
    end)
    if fs then helpMarker(parent, fs, help) end
    if adminOnly then registerAdminGate(fs, function() cb:Enable() end, function() cb:Disable() end) end
    return cb
  end
  local function dropdown(label, key, options, onChange, help, parent, adminOnly)
    parent = parent or child
    local lbl = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", 16, y); lbl:SetText(label)
    local dd = CreateFrame("Frame", "AGNB_DD_" .. key, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", 232, y + 4)
    UIDropDownMenu_SetWidth(dd, 130)
    local function labelFor(v)
      for _, o in ipairs(options) do if o.value == v then return o.label end end
      return tostring(v)
    end
    UIDropDownMenu_Initialize(dd, function()
      for _, o in ipairs(options) do
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.value = o.label, o.value
        info.checked = (ns.cfg[key] == o.value)
        info.func = function()
          ns.cfg[key] = o.value
          UIDropDownMenu_SetSelectedValue(dd, o.value)
          UIDropDownMenu_SetText(dd, o.label)
          if onChange then onChange(o.value) end
        end
        UIDropDownMenu_AddButton(info)
      end
    end)
    local function seed()
      UIDropDownMenu_SetSelectedValue(dd, ns.cfg[key]); UIDropDownMenu_SetText(dd, labelFor(ns.cfg[key]))
    end
    seed()
    dd:HookScript("OnShow", seed)
    refreshers[#refreshers + 1] = seed
    helpMarker(parent, lbl, help)
    if adminOnly then
      registerAdminGate(lbl, function() UIDropDownMenu_EnableDropDown(dd) end,
        function() UIDropDownMenu_DisableDropDown(dd) end)
    end
    y = y - 32
    return dd
  end
  local function editbox(label, key, numeric, wide, help, parent, adminOnly)
    parent = parent or child
    local lbl = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", 16, y - 4); lbl:SetText(label)
    local eb = CreateFrame("EditBox", "AGNB_EB_" .. key, parent, "InputBoxTemplate")
    eb:SetSize(wide and 200 or 56, 20); eb:SetPoint("TOPLEFT", 248, y - 2); eb:SetAutoFocus(false)
    if numeric then eb:SetNumeric(true) end
    -- Re-seed the box from cfg. An EditBox never paints text that was set while
    -- its frame (or its settings tab / the whole panel) was hidden, and SetText is
    -- a no-op when the new string matches the current one -- so a plain re-SetText
    -- leaves the box blank even though the value is stored. Clearing first forces a
    -- real change, and seeding on every OnShow makes reopening Settings or switching
    -- tabs always repaint the saved value.
    local function seed()
      eb:SetText(""); eb:SetText(tostring(ns.cfg[key] ~= nil and ns.cfg[key] or ""))
      eb:SetCursorPosition(0)
    end
    seed()
    eb:HookScript("OnShow", seed)
    eb:SetScript("OnEnterPressed", function(self)
      local v = self:GetText()
      if numeric then ns.cfg[key] = tonumber(v) or ns.cfg[key]; self:SetText(tostring(ns.cfg[key]))
      else ns.cfg[key] = (v:gsub("^%s*(.-)%s*$", "%1")) end
      self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:SetText(tostring(ns.cfg[key] or "")); self:ClearFocus() end)
    refreshers[#refreshers + 1] = seed
    helpMarker(parent, lbl, help)
    if adminOnly then registerAdminGate(lbl, function() eb:Enable() end, function() eb:Disable() end) end
    y = y - 28
    return eb
  end

  -- map a layout onChange tag to its side-effecting handler
  local function onChangeFor(kind)
    if kind == "antiPrize" then return function(v) if ns.AntiPrize then ns.AntiPrize.SetSelf(v) end end
    elseif kind == "debug" then return function(v) if ns.Debug and ns.Debug.SetLevel then ns.Debug.SetLevel(v) end end end
  end

  -- ----- MRT-style tab row + one content frame per tab -----
  local tabBtns, tabContent = {}, {}
  local function showTab(id)
    for tid, cf in pairs(tabContent) do cf:SetShown(tid == id) end
    for tid, b in pairs(tabBtns) do
      local on = (tid == id)
      b.fs:SetTextColor(on and 1 or 0.7, on and 0.82 or 0.62, on and 0.2 or 0.36)
      b.underline:SetShown(on)
    end
    CFG._activeTab = id
  end

  local tabX = 10
  for _, tab in ipairs(CFG.SETTINGS_LAYOUT) do
    local b = CreateFrame("Button", nil, child)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetText(tab.label); fs:SetPoint("LEFT")
    b.fs = fs; b:SetSize((fs:GetStringWidth() or 60) + 8, 20); b:SetPoint("TOPLEFT", tabX, -2)
    local ul = b:CreateTexture(nil, "ARTWORK"); ul:SetColorTexture(1, 0.82, 0.2)
    ul:SetHeight(2); ul:SetPoint("BOTTOMLEFT"); ul:SetPoint("BOTTOMRIGHT"); ul:Hide()
    b.underline = ul
    b:SetScript("OnClick", function() showTab(tab.id) end)
    tabBtns[tab.id] = b
    tabX = tabX + b:GetWidth() + 14

    local cf = CreateFrame("Frame", nil, child)
    cf:SetPoint("TOPLEFT", 0, -28); cf:SetPoint("TOPRIGHT", 0, -28); cf:SetHeight(10)
    tabContent[tab.id] = cf
  end

  -- render each tab's groups/controls into its content frame
  local maxH = 0
  for _, tab in ipairs(CFG.SETTINGS_LAYOUT) do
    local cf = tabContent[tab.id]
    y = -4
    local function renderControl(c)
      if c.kind == "check" then checkbox(c.key, c.label, c.onChange and onChangeFor(c.onChange), c.help, cf, c.admin)
      elseif c.kind == "dropdown" then dropdown(c.label, c.key, c.options, c.onChange and onChangeFor(c.onChange), c.help, cf, c.admin)
      elseif c.kind == "edit" then editbox(c.label, c.key, c.numeric, c.wide, c.help, cf, c.admin)
      elseif c.kind == "announceTable" then
        for _, k in ipairs(ns.Announce.KINDS) do
          checkbox("announce_" .. k.key, "Announce " .. k.label, nil, "announce_" .. k.key, cf)
          dropdown("   channel", "announceChan_" .. k.key, CFG.CHANNELS, nil, "announceChan_" .. k.key, cf)
        end
      end
    end
    for _, group in ipairs(tab.groups) do
      if group.header then section(group.header, cf) end
      for _, c in ipairs(group.controls) do renderControl(c) end
    end
    -- dev tools sit at the bottom of the Advanced tab
    if tab.id == "advanced" and ns.Demo and ns.Demo.IsDev and ns.Demo.IsDev() then
      section("Dev", cf)
      local mock = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
      mock:SetSize(170, 22); mock:SetText("Load / Clear Mock Data")
      mock:SetPoint("TOPLEFT", 14, y); y = y - 26
      mock:SetScript("OnClick", function() if ns.Demo.active then ns.Demo.Clear() else ns.Demo.Load() end end)
      local dbg = CreateFrame("Button", nil, cf, "UIPanelButtonTemplate")
      dbg:SetSize(170, 22); dbg:SetText("Open Debug Log")
      dbg:SetPoint("TOPLEFT", 14, y); y = y - 26
      dbg:SetScript("OnClick", function() if ns.Debug and ns.Debug.Show then ns.Debug.Show() end end)
    end
    local h = math.abs(y) + 12
    cf:SetHeight(h)
    if h > maxH then maxH = h end
  end

  -- scroll child spans the tallest tab (+ the tab row) so a long tab (Chat) scrolls
  child:SetHeight(maxH + 36)
  showTab(CFG.SETTINGS_LAYOUT[1].id)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(cat)
    ns.optionsCategoryID = cat:GetID()
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
  ns.optionsPanel = panel
end

-- Embed the options panel inside the main window's content host (single-window UI).
function ns.Config.EmbedOptions(host)
  local panel = ns.optionsPanel
  if not (panel and host) then return end
  panel:SetParent(host)
  panel:ClearAllPoints()
  panel:SetAllPoints(host)
  panel:Show()   -- visibility controlled by the view registry (show/hide on view switch)
end

ns.OnInit(function()
  ns.db.config = CFG.ApplyDefaults(ns.db.config)
  ns.cfg = ns.db.config
  SLASH_AGNB1 = "/agnb"; SLASH_AGNB2 = "/deaths"
  SlashCmdList["AGNB"] = handleSlash
  buildOptions()
end)
