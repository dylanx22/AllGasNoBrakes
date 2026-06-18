local _, ns = ...
ns = ns or __AGNB_NS
ns.BookUI = ns.BookUI or {}
local BUI = ns.BookUI

local GOLD, TAN, MUTED = { 1, 0.85, 0.4 }, { 0.9, 0.86, 0.72 }, { 0.54, 0.49, 0.39 }

local function B() return ns.Book end
local function rt() return ns.Book and ns.Book.rt end

-- Format a copper amount as gold (+ silver when there's a sub-gold remainder), so
-- settlement lines reconcile exactly instead of truncating fractional-gold transfers
-- (a 7g50s + 2g50s split must read as 10g, not 9g).
local function money(copper)
  copper = math.abs(copper or 0)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  if s > 0 then return ("%dg %ds"):format(g, s) end
  return ("%dg"):format(g)
end
local function moneyDelta(copper)
  return (((copper or 0) < 0) and "-" or "+") .. money(copper)
end

local function btn(parent, label, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 90, 22); b:SetText(label); b:SetScript("OnClick", onClick)
  return b
end

local function build()
  if BUI.frame then return BUI.frame end
  local f = CreateFrame("Frame", "AGNB_Book", UIParent, "BackdropTemplate")
  f:SetSize(380, 360); f:SetPoint("CENTER"); f:SetFrameStrata("HIGH")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.05, 0.04, 0.02, 0.97); f:SetBackdropBorderColor(0.23, 0.18, 0.09, 1)
  end
  f.closeX = CreateFrame("Button", nil, f, "UIPanelCloseButton"); f.closeX:SetPoint("TOPRIGHT", 2, 2)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", 16, -14); f.title:SetText("The Book"); f.title:SetTextColor(unpack(GOLD))
  f.state = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.state:SetPoint("TOPLEFT", 16, -36); f.state:SetWidth(340); f.state:SetJustifyH("LEFT")

  -- admin row
  f.openBtn = btn(f, "Open round", 100, function() B().OpenRound() end)
  f.openBtn:SetPoint("TOPLEFT", 14, -56)
  f.draftBtn = btn(f, "Open draft", 100, function() B().OpenDraft() end)
  f.draftBtn:SetPoint("LEFT", f.openBtn, "RIGHT", 6, 0)
  f.lockDraftBtn = btn(f, "Lock draft", 90, function() B().LockDraft() end)
  f.lockDraftBtn:SetPoint("LEFT", f.draftBtn, "RIGHT", 6, 0)

  -- over/under
  f.ouLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.ouLabel:SetPoint("TOPLEFT", 16, -92); f.ouLabel:SetTextColor(unpack(TAN))
  f.overBtn = btn(f, "Over", 80, function() B().PlaceOU("over") end)
  f.overBtn:SetPoint("TOPLEFT", 16, -112)
  f.underBtn = btn(f, "Under", 80, function() B().PlaceOU("under") end)
  f.underBtn:SetPoint("LEFT", f.overBtn, "RIGHT", 6, 0)

  -- first blood: a dropdown of candidates + "no deaths"
  f.fbLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.fbLabel:SetPoint("TOPLEFT", 16, -146); f.fbLabel:SetText("First Blood:"); f.fbLabel:SetTextColor(unpack(TAN))
  f.fbDD = CreateFrame("Frame", "AGNB_BookFB_DD", f, "UIDropDownMenuTemplate")
  f.fbDD:SetPoint("TOPLEFT", 96, -142); UIDropDownMenu_SetWidth(f.fbDD, 150)

  -- results / standings text
  f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.body:SetPoint("TOPLEFT", 18, -184); f.body:SetWidth(346); f.body:SetJustifyH("LEFT")
  f.body:SetJustifyV("TOP")

  -- admin-only "all wager math" pane: a scrollable whole-raid breakdown that
  -- overlays the body region (the plain body FontString can't scroll, and a full
  -- raid's bet-by-bet math runs well past the panel).
  f.mathPane = CreateFrame("ScrollFrame", "AGNB_BookAllMathScroll", f, "UIPanelScrollFrameTemplate")
  f.mathPane:SetPoint("TOPLEFT", 16, -184); f.mathPane:SetPoint("BOTTOMRIGHT", -30, 44)
  f.mathChild = CreateFrame("Frame", nil, f.mathPane); f.mathChild:SetSize(316, 10)
  f.mathPane:SetScrollChild(f.mathChild)
  f.mathText = f.mathChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.mathText:SetPoint("TOPLEFT"); f.mathText:SetWidth(310)
  f.mathText:SetJustifyH("LEFT"); f.mathText:SetJustifyV("TOP")
  f.mathPane:Hide()

  -- draft join
  f.joinBtn = btn(f, "Join draft", 100, function() B().JoinDraft() end)
  f.joinBtn:SetPoint("BOTTOMLEFT", 16, 14)

  -- settlement / admin row
  f.closeBtn = btn(f, "Close book", 100, function() if ns.Book.CloseBook then ns.Book.CloseBook() end end)
  f.closeBtn:SetPoint("LEFT", f.lockDraftBtn, "RIGHT", 6, 0)

  f.mathBtn = btn(f, "Show math", 90, function() BUI.showMath = not BUI.showMath; BUI.Refresh() end)
  f.mathBtn:SetPoint("BOTTOMLEFT", f.joinBtn, "TOPLEFT", 0, 6)

  -- admin: toggle the whole-raid wager-math pane
  f.allMathBtn = btn(f, "All math", 90, function() BUI.showAllMath = not BUI.showAllMath; BUI.Refresh() end)
  f.allMathBtn:SetPoint("BOTTOMLEFT", f.mathBtn, "TOPLEFT", 0, 6)

  -- ignore-pull picker (admin)
  f.ignoreBtn = btn(f, "Ignore a pull", 110, function() BUI.showIgnore = not BUI.showIgnore; BUI.Refresh() end)
  f.ignoreBtn:SetPoint("LEFT", f.mathBtn, "RIGHT", 6, 0)

  -- invite to pot (admin action, formerly a nav item)
  f.inviteBtn = btn(f, "Invite to pot", 110, function() if ns.AntiPrize then ns.AntiPrize.Invite() end end)
  f.inviteBtn:SetPoint("BOTTOMRIGHT", -14, 14)

  f.settleBtn = btn(f, "Settle by mail", 120, function() BUI.SettleByMail() end)
  f.settleBtn:SetPoint("BOTTOMRIGHT", f.inviteBtn, "TOPRIGHT", 0, 6)

  -- ----- delegated admin: status (everyone) + picker (leaders only) -----
  f.adminStatus = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.adminStatus:SetPoint("BOTTOMLEFT", 16, 98); f.adminStatus:SetJustifyH("LEFT")
  f.adminDD = CreateFrame("Frame", "AGNB_BookAdmin_DD", f, "UIDropDownMenuTemplate")
  f.adminDD:SetPoint("BOTTOMLEFT", 0, 66); UIDropDownMenu_SetWidth(f.adminDD, 120)
  f.setAdminBtn = btn(f, "Set admin", 90, function()
    if f._adminPick then ns.Book.SetAdmin(f._adminPick) end
  end)
  f.setAdminBtn:SetPoint("LEFT", f.adminDD, "RIGHT", 0, 2)
  f.clearAdminBtn = btn(f, "Clear", 60, function() ns.Book.ClearAdmin() end)
  f.clearAdminBtn:SetPoint("LEFT", f.setAdminBtn, "RIGHT", 4, 0)

  -- enable-prompt (shown when wagering is off)
  f.offPrompt = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.offPrompt:SetPoint("TOP", 0, -60); f.offPrompt:SetWidth(320); f.offPrompt:SetJustifyH("CENTER")
  f.offPrompt:SetText("Wagering is off.\nThe Book runs Over/Under, First Blood, and a Death Draft.")
  f.enableBtn = btn(f, "Enable wagering", 140, function()
    if ns.cfg then ns.cfg.bookEnabled = true end
    if ns.Config and ns.Config.PromptReload then ns.Config.PromptReload() end
    BUI.Refresh()
  end)
  f.enableBtn:SetPoint("TOP", f.offPrompt, "BOTTOM", 0, -10)

  BUI.frame = f
  return f
end

-- Embed the betting panel inside the main window's content host (single-window UI).
function BUI.Embed(host)
  local f = build()
  if not host then return f end
  f:SetParent(host)
  f:ClearAllPoints(); f:SetAllPoints(host)
  f:SetMovable(false); f:EnableMouse(false)
  f:SetScript("OnDragStart", nil); f:SetScript("OnDragStop", nil)
  if f.SetBackdrop then f:SetBackdrop(nil) end   -- the host/main window provides the frame
  if f.closeX then f.closeX:Hide() end
  return f
end

local function setShown(widget, shown) if widget then widget:SetShown(shown and true or false) end end

local function fbInitialize(self)
  local r = rt() and rt().round
  if not r then return end
  local me = ns.MyName or (UnitName and UnitName("player")) or "?"
  local cands = ns.Book.FirstBloodCandidates(
    (function() local out = {}; local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
       local pre = (IsInRaid and IsInRaid()) and "raid" or "party"
       for i = 1, n do local nm = UnitName and UnitName(pre .. i); if nm then out[#out+1] = nm end end
       if #out == 0 then out[1] = me end
       return out end)(), me)
  local function add(value, label)
    local info = UIDropDownMenu_CreateInfo()
    info.text, info.value = label or value, value
    info.func = function() ns.Book.PlaceFB(value); UIDropDownMenu_SetText(self, label or value) end
    UIDropDownMenu_AddButton(info)
  end
  add("none", "No deaths")
  for _, p in ipairs(cands) do add(p) end
end

function BUI.Refresh()
  local f = BUI.frame
  if not f or not f:IsShown() then return end

  local off = not (ns.cfg and ns.cfg.bookEnabled)
  f.offPrompt:SetShown(off); f.enableBtn:SetShown(off)
  if off then
    for _, w in ipairs({ f.state, f.openBtn, f.draftBtn, f.lockDraftBtn, f.ouLabel, f.overBtn,
        f.underBtn, f.fbLabel, f.fbDD, f.body, f.joinBtn, f.closeBtn, f.mathBtn, f.allMathBtn,
        f.mathPane, f.ignoreBtn, f.inviteBtn, f.settleBtn, f.title, f.adminStatus, f.adminDD,
        f.setAdminBtn, f.clearAdminBtn }) do
      if w then w:SetShown(false) end
    end
    return
  end

  local r = rt() and rt().round
  local dr = rt() and rt().draft
  local admin = ns.Book.CanAdmin()

  setShown(f.openBtn, admin); setShown(f.draftBtn, admin)
  setShown(f.lockDraftBtn, admin and dr and dr.state == "OPEN")
  setShown(f.closeBtn, admin)
  setShown(f.ignoreBtn, admin)
  setShown(f.mathBtn, true)
  setShown(f.allMathBtn, admin)

  -- delegated-admin status + picker
  local desig = ns.db and ns.db.designatedAdmin
  f.adminStatus:SetText("AGNB admin: " .. (desig or "(leaders only)")); setShown(f.adminStatus, true)
  local canAppoint = ns.Book.CanAppoint and ns.Book.CanAppoint()
  setShown(f.adminDD, canAppoint); setShown(f.setAdminBtn, canAppoint); setShown(f.clearAdminBtn, canAppoint)
  if canAppoint then
    UIDropDownMenu_Initialize(f.adminDD, function()
      local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
      local pre = (IsInRaid and IsInRaid()) and "raid" or "party"
      for i = 1, n do
        local nm = UnitName and UnitName(pre .. i)
        if nm then
          local info = UIDropDownMenu_CreateInfo()
          info.text, info.value = nm, nm
          info.func = function() f._adminPick = nm; UIDropDownMenu_SetText(f.adminDD, nm) end
          UIDropDownMenu_AddButton(info)
        end
      end
    end)
  end

  -- round section
  if r then
    f.state:SetText(("Round: %s  ·  O/U line %.1f  ·  stakes %dg / %dg")
      :format(r.state, r.line, r.stakeOU, r.stakeFB))
    f.ouLabel:SetText(("Over/Under %.1f deaths this pull (%dg):"):format(r.line, r.stakeOU))
    local open = r.state == "OPEN"
    setShown(f.ouLabel, true); setShown(f.overBtn, open); setShown(f.underBtn, open)
    setShown(f.fbLabel, open); setShown(f.fbDD, open)
    if open then UIDropDownMenu_Initialize(f.fbDD, fbInitialize) end
  else
    f.state:SetText("No betting round yet." .. (admin and " (Open one above.)" or " Waiting for the raid leader."))
    f.ouLabel:SetText(""); setShown(f.overBtn, false); setShown(f.underBtn, false)
    setShown(f.fbLabel, false); setShown(f.fbDD, false)
  end

  -- body: results + draft standings
  local lines = {}
  if r and (r.state == "RESOLVED" or r.state == "SETTLED") then
    lines[#lines + 1] = ("Outcome: %s  ·  First blood: %s"):format(r.outcomeOU or "?", r.outcomeFB or "?")
    if r.settleOU then
      lines[#lines + 1] = ("O/U pot %dg - winners: %s"):format(r.settleOU.pot, table.concat(r.settleOU.winners, ", "))
    end
    if r.settleFB then
      lines[#lines + 1] = ("First Blood pot %dg - winners: %s"):format(r.settleFB.pot,
        (#r.settleFB.winners > 0 and table.concat(r.settleFB.winners, ", ") or "nobody (rolls over)"))
    end
  end
  if dr then
    lines[#lines + 1] = " "
    lines[#lines + 1] = ("Death Draft: %s  ·  ante %dg"):format(dr.state, dr.ante or 0)
    if dr.assign then
      local st = B().LiveStandings()
      for i = 1, math.min(8, #st) do
        lines[#lines + 1] = ("  %d. %s - %s (%d)"):format(i, st[i].player, st[i].raider, st[i].deaths)
      end
    elseif dr.commits then
      local n = 0; for _ in pairs(dr.commits) do n = n + 1 end
      lines[#lines + 1] = ("  %d entered"):format(n)
    end
  end
  -- (all-time winners/losers board moved to the Bet Records page)

  -- ----- settlement (after the book is closed) -----
  local ST = ns.Settlement
  if ST and ST.state then
    lines[#lines + 1] = " "
    lines[#lines + 1] = "|cffffd966Settlement|r" .. (ST.desync and "  |cffff5555(numbers out of sync - /reload)|r" or "")
    local me = ns.MyName or (UnitName and UnitName("player")) or "?"
    local mine = ST.MyDebts()
    if #mine == 0 then
      lines[#lines + 1] = "  You owe nothing."
    else
      for _, t in ipairs(mine) do
        lines[#lines + 1] = ("  Pay %s: %s%s"):format(t.to, money(t.amount),
          t.settled and "  |cff66ff66(paid)|r" or "")
      end
    end
    for _, t in ipairs(ST.state.transfers) do
      if t.to == me and not t.settled then
        lines[#lines + 1] = ("  %s owes you %s  (/agnb book paid %s)"):format(t.from, money(t.amount), t.from)
      end
    end
    if BUI.showMath and ST.breakdown and ST.breakdown[me] then
      lines[#lines + 1] = "|cffffd966  Your math:|r"
      for _, ln in ipairs(ST.breakdown[me].lines) do
        lines[#lines + 1] = ("    [%d] %s %s/%s - %s (%s)"):format(ln.seq, ln.bet, ln.pick,
          ln.outcome, ln.result, moneyDelta(ln.delta))
      end
    end
    -- full raid settlement (admin only): every transfer, unsettled highlighted
    if ns.Book.CanAdmin and ns.Book.CanAdmin() then
      local sum = ns.Book.SettleSummary(ST.state)
      lines[#lines + 1] = ("|cffffd966  Full raid settlement:|r  %d of %d settled  \194\183  %s outstanding"):format(
        sum.settled, sum.total, money(sum.outstanding))
      for _, t in ipairs(ST.state.transfers) do
        if t.settled then
          lines[#lines + 1] = ("    |cff66ff66%s -> %s: %s (paid)|r"):format(t.from, t.to, money(t.amount))
        else
          -- show the REMAINING owed so the lines reconcile with the outstanding header
          lines[#lines + 1] = ("    |cffff8844%s -> %s: %s|r"):format(t.from, t.to, money((t.amount or 0) - (t.paid or 0)))
        end
      end
    end
  end

  -- ----- ignore-pull picker (admin) -----
  if BUI.showIgnore and ns.Book.CanAdmin and ns.Book.CanAdmin() and ns.Book.RecentPullList then
    lines[#lines + 1] = " "
    lines[#lines + 1] = "|cffffd966Ignore a pull (voids deaths + bets):|r"
    for _, p in ipairs(ns.Book.RecentPullList()) do
      lines[#lines + 1] = ("  %s - %d deaths   (/agnb book void %d %d)"):format(
        tostring(p.boss or "?"), p.count, p.startTime, p.endTime)
    end
  end

  -- ----- collusion alerts (admin) -----
  if ns.Book.CanAdmin and ns.Book.CanAdmin() and ns.Book.collusionAlerts and #ns.Book.collusionAlerts > 0 then
    lines[#lines + 1] = " "
    lines[#lines + 1] = "|cffff5555Collusion alerts:|r"
    for _, a in ipairs(ns.Book.collusionAlerts) do
      lines[#lines + 1] = ("  [%s] %s: \"%s\""):format(a.kind, tostring(a.suspect), tostring(a.snippet))
    end
  end

  -- the admin "all wager math" pane swaps in over the body when toggled on
  local showPane = BUI.showAllMath and admin and ns.Settlement
  if f.allMathBtn then f.allMathBtn:SetText(showPane and "Hide math" or "All math") end
  if showPane then
    local ml = {}
    if not ns.Settlement.state then
      ml[#ml + 1] = "Close the book to settle, then the whole raid's wager math shows here."
    else
      local all = (ns.Settlement.AllMath and ns.Settlement.AllMath()) or {}
      if #all == 0 then
        ml[#ml + 1] = "No wagers were placed this session."
      else
        for _, e in ipairs(all) do
          ml[#ml + 1] = ("|cffffffff%s|r   net %s"):format(e.player, moneyDelta(e.net))
          if #e.lines == 0 then
            ml[#ml + 1] = "    (no individual bets)"
          else
            for _, ln in ipairs(e.lines) do
              ml[#ml + 1] = ("    [%d] %s %s - %s (%s)"):format(ln.seq or 0, ln.bet or "?",
                tostring(ln.pick), ln.outcome or "", moneyDelta(ln.delta))
            end
          end
        end
      end
    end
    f.mathText:SetText(table.concat(ml, "\n"))
    f.mathChild:SetHeight((f.mathText:GetStringHeight() or 10) + 12)
    f.mathPane:Show(); f.body:Hide()
  else
    f.mathPane:Hide(); f.body:Show()
    f.body:SetText(table.concat(lines, "\n"))
  end
  setShown(f.joinBtn, dr and dr.state == "OPEN")
  if f.inviteBtn then f.inviteBtn:SetShown(ns.AntiPrize and ns.AntiPrize.CanInvite() or false) end
  if f.settleBtn then
    local nxt = ns.Settlement and ns.Settlement.MailNext and ns.Settlement.MailNext()
    f.settleBtn:SetShown(nxt ~= nil)
  end
end

-- Payer-side auto-settle: pre-fill an in-game mail to the first creditor the
-- viewer still owes (mirrors the anti-prize Settle button). Book transfer
-- amounts are copper, so they go straight to MoneyInputFrame_SetCopper.
function BUI.SettleByMail()
  local ST = ns.Settlement
  local nxt = ST and ST.MailNext and ST.MailNext()
  if not nxt then ns.Print("You owe the book nothing. Smug.") return end
  if not (MailFrame and MailFrame:IsShown()) then
    ns.Print(("You owe %s %s. Open a mailbox and click 'Settle by mail' again to pre-fill it."):format(
      nxt.to, money(nxt.amount)))
    return
  end
  if MailFrameTab2 then MailFrameTab2:Click() end
  if SendMailNameEditBox then SendMailNameEditBox:SetText(nxt.to) end
  if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText("Book settlement") end
  if MoneyInputFrame_SetCopper and SendMailMoney then MoneyInputFrame_SetCopper(SendMailMoney, nxt.amount) end
  ns.Print(("Pre-filled mail: %s to %s. Click Send."):format(money(nxt.amount), nxt.to))
end

function BUI.Toggle()
  local f = build()
  if f:IsShown() then f:Hide() else f:Show(); BUI.Refresh() end
end
