local _, ns = ...
ns = ns or __AGNB_NS
ns.Tour = ns.Tour or {}
local TR = ns.Tour

-- Interactive onboarding: drive the real main window from view to view, ring the
-- matching navigation element, and float a callout beside it. Sample data is
-- loaded first so the pages aren't empty, and cleared when the tour ends.

local GOLD = { 1, 0.82, 0.2 }

local function uiFrame() return ns.UI and ns.UI.frame end

-- Find a nav widget whose definition matches `pred` (so the spotlight tracks the
-- real button, surviving the relayout that SetView triggers).
local function navWidget(pred)
  local f = uiFrame()
  if not (f and f.nav) then return nil end
  for _, e in ipairs(f.nav) do
    if e.def and pred(e.def) then return e.widget end
  end
  return nil
end
local function byView(v) return function() return navWidget(function(d) return d.view == v end) end end
local function byLabel(l) return function() return navWidget(function(d) return d.label == l end) end end

-- Each step optionally switches the window to `view`, then highlights `target()`.
-- A nil target just centers the callout (no ring).
TR.STEPS = {
  { title = "Welcome to All Gas No Brakes",
    body = "Your raid's deaths, tracked and roasted. Open this window any time with the minimap skull or /agnb. Nothing leaves your screen until you switch it on.",
    target = function() return uiFrame() end },
  { view = "deaths", target = byView("deaths"),
    title = "Leaderboards",
    body = "Tonight and All-Time boards credit whoever landed the killing blow. The toggle up top swaps the range, and clicking a name opens their breakdown." },
  { view = "abilities", target = byView("abilities"),
    title = "Deadliest Abilities",
    body = "Wondering what keeps flattening the raid? This board ranks the spells and hits behind the most deaths, so you know what to dodge next pull." },
  { view = "log", target = byView("log"),
    title = "Death Log and killcams",
    body = "Every death, newest first. Click any row to replay a short killcam of the final few seconds before it happened." },
  { view = "perboss", target = byView("perboss"),
    title = "Insights",
    body = "Per-Boss shows where you die most, and the Pull Timeline charts when deaths land across a fight. Handy for spotting the wipe pattern." },
  { target = byLabel("End of Raid"),
    title = "Overlays",
    body = "A full-screen banner fires on a wipe, and an End-of-Raid podium with a Lowlights Reel pops after the final boss. Style both under Settings, Overlays." },
  { view = "book", target = byView("book"),
    title = "The Book (wagering)",
    body = "Opt-in Over/Under, First Blood, and a Death Draft. Lead or assist the raid and you also get the controls to open rounds, lock bets, and settle up." },
  { view = "betting", target = byView("betting"),
    title = "Bet Records and the gold pot",
    body = "Bet Records keeps the all-time wager standings. The gold anti-prize is opt-in and a tally only, since addons can't actually move gold for you." },
  { view = "history", target = byView("history"),
    title = "Raid History and export",
    body = "Past nights are kept here, bucketed by raid lockout. Drill into any single death's killcam, or export a night as Discord-ready text or a screenshot scorecard." },
  { view = "report", target = byView("report"),
    title = "Post a report",
    body = "Post any board (Tonight, All-Time, Lowlights, or the ledger) to a channel you pick. Per-event announcements live in Settings and all default to just you." },
  { view = "settings", target = byView("settings"),
    title = "Settings",
    body = "Everything lives here: tracking rules, raid-wide sync, a custom raid name, announce channels, the wipe banner, the gold ledger, and wagering. Options only the raid leader uses are greyed out for everyone else." },
  { view = "help", target = byView("help"),
    title = "Help is always here",
    body = "The Help page recaps every feature and its slash command. You can replay this whole tour any time with /agnb tour." },
  { title = "Your minimap button",
    body = "Left-click opens the window, right-click jumps to Settings, and you can drag it anywhere around the minimap. That's the tour. Go wipe gloriously.",
    target = function() return _G.AGNB_MinimapButton end },
}

local function build()
  if TR.frame then return TR.frame end

  local hl = CreateFrame("Frame", "AGNB_TourHighlight", UIParent, "BackdropTemplate")
  hl:SetFrameStrata("FULLSCREEN_DIALOG"); hl:SetFrameLevel(50)
  if hl.SetBackdrop then
    hl:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    hl:SetBackdropBorderColor(1, 0.82, 0.2, 1)
  end
  hl:Hide()
  TR.highlight = hl

  local c = CreateFrame("Frame", "AGNB_Tour", UIParent, "BackdropTemplate")
  c:SetSize(300, 172); c:SetFrameStrata("FULLSCREEN_DIALOG"); c:SetFrameLevel(60); c:SetToplevel(true)
  if c.SetBackdrop then
    c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    c:SetBackdropColor(0.05, 0.04, 0.02, 0.98); c:SetBackdropBorderColor(0.23, 0.18, 0.09, 1)
  end
  c.title = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  c.title:SetPoint("TOPLEFT", 14, -14); c.title:SetWidth(240); c.title:SetJustifyH("LEFT")
  c.title:SetTextColor(unpack(GOLD))
  c.progress = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  c.progress:SetPoint("TOPRIGHT", -14, -16)
  c.body = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  c.body:SetPoint("TOPLEFT", 14, -42); c.body:SetPoint("TOPRIGHT", -14, -42)
  c.body:SetJustifyH("LEFT"); c.body:SetJustifyV("TOP"); c.body:SetSpacing(3)

  local function mkbtn(label, w)
    local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    b:SetSize(w, 22); b:SetText(label); return b
  end
  c.skip = mkbtn("Skip", 54); c.skip:SetPoint("BOTTOMLEFT", 10, 12)
  c.back = mkbtn("Back", 58); c.back:SetPoint("BOTTOMRIGHT", -74, 12)
  c.next = mkbtn("Next", 62); c.next:SetPoint("BOTTOMRIGHT", -10, 12)
  c.skip:SetScript("OnClick", function() TR.Finish() end)
  c.back:SetScript("OnClick", function() TR.Go(TR.i - 1) end)
  c.next:SetScript("OnClick", function()
    if TR.i >= #TR.STEPS then TR.Finish() else TR.Go(TR.i + 1) end
  end)

  TR.frame = c
  return c
end

-- Show step i: switch view, write the callout, and ring the target element.
function TR.Go(i)
  local n = #TR.STEPS
  i = math.max(1, math.min(n, i))
  TR.i = i
  local c = build()
  local step = TR.STEPS[i]

  if step.view and ns.UI and ns.UI.SetView then ns.UI.SetView(step.view) end

  c.title:SetText(step.title)
  c.body:SetText(step.body)
  c.progress:SetText(("%d / %d"):format(i, n))
  c.back:SetEnabled(i > 1)
  c.next:SetText(i >= n and "Done" or "Next")

  local t = step.target and step.target()
  local hl = TR.highlight
  if t and t.GetObjectType then
    hl:ClearAllPoints()
    hl:SetPoint("TOPLEFT", t, "TOPLEFT", -3, 3)
    hl:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 3, -3)
    hl:Show()
  else
    hl:Hide()
  end

  c:ClearAllPoints()
  local f = uiFrame()
  if f and f:IsShown() then c:SetPoint("LEFT", f, "RIGHT", 16, 0) else c:SetPoint("CENTER") end
  c:Show()
end

-- Open the window with sample data, then start at step 1.
function TR.Start()
  if ns.Demo and ns.Demo.LoadPreview and not ns.Demo.active then ns.Demo.LoadPreview() end
  if ns.UI then ns.UI.Build(); if ns.UI.frame then ns.UI.frame:Show() end; if ns.UI.Refresh then ns.UI.Refresh() end end
  build()
  TR.Go(1)
end
TR.replay = TR.Start

-- Tear down, mark onboarding seen, drop the sample data, land on Help.
function TR.Finish()
  if TR.highlight then TR.highlight:Hide() end
  if TR.frame then TR.frame:Hide() end
  if ns.Welcome and ns.Welcome.MarkSeen then ns.Welcome.MarkSeen(ns.cfg) end
  if ns.Demo and ns.Demo.active and ns.Demo.Clear then ns.Demo.Clear() end
  if ns.UI and ns.UI.SetView then ns.UI.SetView("help") end
end
