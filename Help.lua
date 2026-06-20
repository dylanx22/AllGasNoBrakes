local _, ns = ...
ns = ns or __AGNB_NS
ns.Help = ns.Help or {}
local H = ns.Help

-- One-line tooltips, keyed by setting. Surfaced by the "?" markers in Settings.
H.SETTING = {
  syncEnabled        = "Share and merge deaths with other raiders running the addon. No setup needed.",
  onlyInstances      = "Ignore open-world and PvP deaths; only count dungeon/raid deaths.",
  raidOnly           = "Count raid instances only, skipping 5-man dungeons.",
  guildOnly          = "Only track deaths of players in your guild.",
  combatOnly         = "Only count deaths that happen in combat.",
  forgiveWipeDeaths  = "Once the raid is clearly wiping, later deaths don't count toward shame.",
  wipeThresholdPct   = "How much of the raid must be dead before remaining deaths are forgiven.",
  showTitles         = "Award earned 'death titles' for notable performances.",
  brandName          = "Name shown in the window, reports, and banner. Blank uses your guild name.",
  soundEnabled       = "Play a short sound when someone dies.",
  announceWindow     = "Group deaths within this many seconds into a single announcement.",
  streakThreshold    = "How many pulls in a row a player must die to trigger a streak callout.",
  reportChannel      = "Where posted reports go. 'Just me' prints only to your own chat.",
  reportTopN         = "How many players a posted leaderboard includes.",
  reportEmoji        = "Add a decorative accent to posted report lines.",
  announce_death        = "Post a snarky line when someone dies (e.g. \"X took a dirt nap, courtesy of Fireball\").",
  announceChan_death    = "Where death lines post.",
  announce_combobreaker = "Post a line when someone takes over the most-deaths lead (\"COMBO BREAKER: X seizes the death lead\").",
  announceChan_combobreaker = "Where lead-change lines post.",
  announce_streak       = "Post a line when a player dies several pulls in a row (count set by the streak threshold below).",
  announceChan_streak   = "Where streak lines post.",
  announce_achievement  = "Post a line when a player unlocks a death achievement (e.g. \"Crash Test Dummy\").",
  announceChan_achievement = "Where achievement lines post.",
  announce_milestone    = "Post a line when a player crosses a death count for the night (10, 25, ...).",
  announceChan_milestone = "Where milestone lines post.",
  announce_survival     = "Post a line when a boss is killed with zero deaths (\"Flawless. Nobody hit the floor\").",
  announceChan_survival = "Where flawless-kill lines post.",
  wipeBannerEnabled  = "Flash a full-screen banner on a full wipe.",
  wipeBannerSound    = "Play a sound with the wipe banner.",
  wipeBannerStyle    = "Visual theme for the wipe banner.",
  wipeBannerSeconds  = "How long the wipe banner stays on screen.",
  wipeTagline        = "Text shown on the wipe banner.",
  autoSummaryOnFinalBoss = "Open the End-of-Raid screen automatically after the final boss dies.",
  antiPrizeOptIn     = "Join the gold pot. You only owe the ledger if you opt in. It's a tally only -- addons can't move gold.",
  buyIn              = "Gold owed per counted death (ledger only).",
  bookEnabled        = "Turn on wagering: Over/Under, First Blood, and the Death Draft.",
  bookAutoOpenOnReadyCheck = "Open a betting round automatically when a ready check starts.",
  bookAutoRounds     = "Automatically open a new betting round between pulls (a couple seconds after the last one settles), so betting is ready without anyone clicking.",
  collusionWatch     = "Flag suspicious bet-fixing chatter to the raid leader.",
  bookStakeOU        = "Flat stake for Over/Under bets (set by the raid leader running the book).",
  bookStakeFB        = "Flat stake for First Blood bets (raid-leader set).",
  bookDraftAnte      = "Ante per player for the Death Draft (raid-leader set).",
  bookMaxBetPct      = "Cap your own wagering at this percent of your gold. 0 = no cap.",
  bookLineWindow     = "How many recent pulls feed the automatic Over/Under line.",
  bookStakeHS        = "Underdog base stake for Hot Seat survival bets; the favorite's stake scales up by the odds (raid-leader set).",
  bookStakeRHS       = "Flat stake for the Raid Hot Seat: a whole-raid Over/Under on one nominated raider's total deaths (raid-leader set).",
  debugLevel         = "Verbosity of the debug log. Leave on 'Errors only' unless troubleshooting.",
}

-- Feature overview, rendered as the Help page. Leader-only powers are called out
-- in-body so leaders discover them without a role-branched tour.
H.GUIDE = {
  { title = "Getting started",
    body = "Click the minimap skull (or type /agnb) to open the window. Everything is private until you switch on an announcement or report channel in Settings. Raid, die, and the boards fill in. Deaths sync automatically with other raiders running the addon.",
    command = "/agnb" },
  { title = "Leaderboards",
    body = "Tonight and All-Time death boards with killing-blow attribution, a Deadliest Abilities board, and a Death Log. Click any Death Log row to pop a killcam of the last few seconds before that death.",
    command = "/deaths" },
  { title = "Overlays",
    body = "A full-wipe banner ('ALL GAS, NO BRAKES') in four styles, and an End-of-Raid podium + Lowlights Reel that auto-opens after the final boss. Configure both under Settings > Overlays.",
    command = "/agnb summary" },
  { title = "The Book (wagering)",
    body = "Opt-in Over/Under on pull deaths, a First Blood pool, and a commit-reveal Death Draft. Enable it in Settings > Gold & The Book. When you're the raid leader or assist, you'll also get controls to open rounds, lock the draft, and run settlement.",
    command = "/agnb book" },
  { title = "Gold / anti-prize",
    body = "An opt-in gold ledger that tallies who owes the pot per death, with a pre-filled settlement mail. It's a tally only -- addons cannot move gold -- and you only owe if you join. Leaders can invite the group to the pot.",
    command = "/agnb invite" },
  { title = "Reports & announcements",
    body = "Post Tonight, All-Time, Lowlights, or the ledger to your chosen channel, and turn on per-event announcements (deaths, streaks, milestones, more). All default to 'Just me' so nothing hits raid chat until you choose.",
    command = "/agnb report tonight" },
  { title = "History & export",
    body = "Browse past raids bucketed by lockout, drill into any night and any single death's killcam, and export a raid as Discord-ready text or a screenshot scorecard.",
    command = "/agnb" },
}

-- ----- Help page (embedded in the main window's content host) -----
local GOLD, TAN = { 1, 0.85, 0.4 }, { 0.9, 0.86, 0.72 }

function H.Embed(host)
  if H.frame then return H.frame end
  local p = CreateFrame("Frame", nil, host)
  p:SetAllPoints(host); p:Hide()
  p:SetClipsChildren(true); p:EnableMouseWheel(true)

  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 4, -2); title:SetText("Help & Guide"); title:SetTextColor(unpack(GOLD))

  local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -24); scroll:SetPoint("BOTTOMRIGHT", -26, 8)
  local body = CreateFrame("Frame", nil, scroll)
  body:SetSize(520, 10); scroll:SetScrollChild(body)
  p.body = body

  H.frame = p
  return p
end

function H.Refresh()
  local p = H.frame; if not p then return end
  p.lines = p.lines or {}
  local y, i = -4, 0
  local function line(font, text, color, indent)
    i = i + 1
    local fs = p.lines[i]
    if not fs then fs = p.body:CreateFontString(nil, "OVERLAY", font); p.lines[i] = fs end
    fs:SetFontObject(font); fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", indent or 6, y); fs:SetPoint("TOPRIGHT", -6, y)
    fs:SetJustifyH("LEFT"); fs:SetSpacing(2)
    fs:SetTextColor(unpack(color)); fs:SetText(text); fs:Show()
    y = y - (fs:GetStringHeight() or 12) - 6
  end
  for _, b in ipairs(H.GUIDE) do
    line("GameFontNormal", b.title, GOLD)
    line("GameFontHighlightSmall", b.body, TAN)
    if b.command then line("GameFontDisableSmall", b.command, { 0.6, 0.8, 1 }) end
    y = y - 6
  end
  -- final pointers: replay the guided tour or the first-run welcome
  line("GameFontNormal", "Take the guided tour", GOLD)
  line("GameFontDisableSmall", "/agnb tour", { 0.6, 0.8, 1 })
  line("GameFontNormal", "Replay the welcome", GOLD)
  line("GameFontDisableSmall", "/agnb welcome", { 0.6, 0.8, 1 })
  for j = i + 1, #p.lines do p.lines[j]:Hide() end
  p.body:SetHeight(math.abs(y) + 12)
end
