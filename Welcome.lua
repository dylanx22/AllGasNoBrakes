local _, ns = ...
ns = ns or __AGNB_NS
ns.Welcome = ns.Welcome or {}
local W = ns.Welcome

function W.ShouldShow(db) return not (db and db.seenWelcome) end

function W.MarkSeen(db) if db then db.seenWelcome = true end end

-- Apply the 3 quick-setup choices straight to cfg. Returns cfg for chaining.
function W.ApplyQuickSetup(cfg, choices)
  cfg = cfg or {}
  choices = choices or {}
  -- announceDeaths: a channel string turns it on; an explicit false turns it
  -- off; nil means "no choice" and leaves the setting alone.
  if choices.announceDeaths == false then
    cfg.announce_death = false
  elseif choices.announceDeaths then
    cfg.announce_death = true
    cfg.announceChan_death = choices.announceDeaths
  end
  cfg.bookEnabled = choices.enableWagering and true or false
  cfg.antiPrizeOptIn = choices.joinPot and true or false
  return cfg
end

-- ----- first-run paged dialog (frame; not unit-tested) -----
local PAGES = {
  { title = "Welcome to All Gas No Brakes",
    body = "Your raid is going to wipe -- this makes it funny. Click the minimap skull (or /agnb) any time to open the window. Everything is private until you switch it on." },
  { title = "Boards, killcams & overlays",
    body = "Tonight / All-Time leaderboards, click-to-killcam, a full-wipe banner, and an End-of-Raid podium. Deaths sync automatically with other raiders running the addon." },
  { title = "The comedy layer",
    body = "Snark, earned titles, streak callouts, and an opt-in gold 'anti-prize' ledger. When you're raid leader or assist, you'll also get the controls to run the gold pot and wagering." },
  { title = "Quick setup",
    body = "Pick a few defaults to start (you can change everything later in Settings):" },
}

function W.Show()
  local d = W.dlg
  if not d then
    d = CreateFrame("Frame", "AGNB_Welcome", UIParent, "BackdropTemplate")
    d:SetSize(420, 320); d:SetPoint("CENTER"); d:SetFrameStrata("DIALOG"); d:SetToplevel(true)
    if d.SetBackdrop then
      d:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
      d:SetBackdropColor(0.05, 0.04, 0.02, 0.98); d:SetBackdropBorderColor(0.23, 0.18, 0.09, 1)
    end
    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.title:SetPoint("TOPLEFT", 16, -16); d.title:SetTextColor(1, 0.82, 0.2)
    d.body = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.body:SetPoint("TOPLEFT", 16, -44); d.body:SetPoint("TOPRIGHT", -16, -44)
    d.body:SetJustifyH("LEFT"); d.body:SetSpacing(3)

    -- quick-setup controls (shown only on the last page)
    d.qs = { choice = { announceDeaths = "SELF", enableWagering = false, joinPot = false } }
    d.qs.channelDD = CreateFrame("Frame", "AGNB_WelcomeChan", d, "UIDropDownMenuTemplate")
    d.qs.channelDD:SetPoint("TOPLEFT", 0, -120); UIDropDownMenu_SetWidth(d.qs.channelDD, 150)
    UIDropDownMenu_Initialize(d.qs.channelDD, function()
      -- "off" is an explicit false so it can turn an already-on setting back off.
      local opts = { { value = false, text = "Don't announce deaths" } }
      for _, o in ipairs(ns.Config.CHANNELS) do
        opts[#opts + 1] = { value = o.value, text = "Announce deaths: " .. o.label }
      end
      for _, o in ipairs(opts) do
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.value = o.text, o.value
        info.func = function() d.qs.choice.announceDeaths = o.value
          UIDropDownMenu_SetText(d.qs.channelDD, o.text) end
        UIDropDownMenu_AddButton(info)
      end
    end)
    UIDropDownMenu_SetText(d.qs.channelDD, "Announce deaths: Just me (self)")
    local function check(label, yy, set)
      local cb = CreateFrame("CheckButton", "AGNB_WelcomeCB" .. yy, d, "InterfaceOptionsCheckButtonTemplate")
      cb:SetPoint("TOPLEFT", 16, yy)
      local fs = _G[cb:GetName() .. "Text"] or cb.Text; if fs then fs:SetText(label) end
      cb:SetScript("OnClick", function(s) set(s:GetChecked() and true or false) end)
      return cb
    end
    d.qs.wager = check("Enable wagering (The Book)", -150, function(v) d.qs.choice.enableWagering = v end)
    d.qs.pot   = check("Join the gold pot", -176, function(v) d.qs.choice.joinPot = v end)

    d.explore = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.explore:SetSize(170, 22); d.explore:SetPoint("BOTTOM", 0, 44); d.explore:SetText("Explore with sample data")
    d.explore:SetScript("OnClick", function()
      if ns.Demo and ns.Demo.LoadPreview then ns.Demo.LoadPreview() end
      if ns.UI then ns.UI.Build(); ns.UI.frame:Show(); ns.UI.Refresh() end
    end)

    d.back = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.back:SetSize(80, 22); d.back:SetPoint("BOTTOMLEFT", 16, 16); d.back:SetText("Back")
    d.next = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.next:SetSize(120, 22); d.next:SetPoint("BOTTOMRIGHT", -16, 16); d.next:SetText("Next")

    d.page = 1
    -- Finishing the guide always saves the quick-setup and opens the Help page.
    -- (These settings apply immediately -- no reload needed.)
    local function finish()
      ns.Welcome.ApplyQuickSetup(ns.cfg, d.qs.choice)
      if ns.AntiPrize and ns.AntiPrize.SetSelf then ns.AntiPrize.SetSelf(d.qs.choice.joinPot) end
      ns.Welcome.MarkSeen(ns.cfg)
      if ns.Demo and ns.Demo.active then ns.Demo.Clear() end
      d:Hide()
      if ns.UI then ns.UI.Build(); ns.UI.frame:Show(); ns.UI.SetView("help") end
    end
    d.render = function()
      local last = (d.page == #PAGES)
      local pg = PAGES[d.page]
      d.title:SetText(pg.title); d.body:SetText(pg.body)
      d.qs.channelDD:SetShown(last); d.qs.wager:SetShown(last); d.qs.pot:SetShown(last)
      d.explore:SetShown(d.page == 2)
      d.back:SetEnabled(d.page > 1)
      d.next:SetText(last and "Got it" or "Next")
    end
    d.back:SetScript("OnClick", function() d.page = math.max(1, d.page - 1); d.render() end)
    d.next:SetScript("OnClick", function()
      if d.page == #PAGES then finish() else d.page = d.page + 1; d.render() end
    end)
    W.dlg = d
  end
  d.page = 1; d.render(); d:Show()
end

W.replay = W.Show

ns.OnInit(function()
  if ns.Welcome.ShouldShow(ns.cfg) then
    if C_Timer and C_Timer.After then C_Timer.After(2, function() ns.Welcome.Show() end)
    else ns.Welcome.Show() end
  end
end)
