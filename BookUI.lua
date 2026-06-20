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

-- Size a button to its label (+ chrome padding) so a button row stays compact and
-- fits narrow windows, instead of fixed widths sized for the longest possible label.
local function fitBtn(b, pad)
  local fs = b:GetFontString()
  b:SetWidth((fs and fs:GetStringWidth() or 60) + (pad or 26))
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

  -- admin row -- buttons auto-size to their labels so the row fits narrow windows
  f.openBtn = fitBtn(btn(f, "Open round", 100, function() B().OpenRound() end))
  f.openBtn:SetPoint("TOPLEFT", 14, -56)
  f.draftBtn = fitBtn(btn(f, "Open draft", 100, function() B().OpenDraft() end))
  f.draftBtn:SetPoint("LEFT", f.openBtn, "RIGHT", 6, 0)
  f.lockDraftBtn = fitBtn(btn(f, "Lock draft", 90, function() B().LockDraft() end))
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

  -- hot seat: dealt-target row (label + Survives / Dies buttons)
  f.hsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.hsLabel:SetPoint("TOPLEFT", 16, -174); f.hsLabel:SetTextColor(unpack(TAN))
  f.hsSurvBtn = btn(f, "Survives", 80, function() ns.Book.PlaceHS("survives") end)
  f.hsSurvBtn:SetPoint("TOPLEFT", 16, -194)
  f.hsDiesBtn = btn(f, "Dies", 80, function() ns.Book.PlaceHS("dies") end)
  f.hsDiesBtn:SetPoint("LEFT", f.hsSurvBtn, "RIGHT", 6, 0)

  -- results / standings text
  f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.body:SetPoint("TOPLEFT", 18, -220); f.body:SetWidth(346); f.body:SetJustifyH("LEFT")
  f.body:SetJustifyV("TOP")

  -- admin-only "all wager math" pane: a scrollable whole-raid breakdown that
  -- overlays the body region (the plain body FontString can't scroll, and a full
  -- raid's bet-by-bet math runs well past the panel).
  f.mathPane = CreateFrame("ScrollFrame", "AGNB_BookAllMathScroll", f, "UIPanelScrollFrameTemplate")
  f.mathPane:SetPoint("TOPLEFT", 16, -220); f.mathPane:SetPoint("BOTTOMRIGHT", -30, 44)
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
  -- Close book follows Lock draft, but Lock is usually hidden -- Refresh re-anchors
  -- it to whichever admin button is actually showing so there's no dead gap.
  f.closeBtn = fitBtn(btn(f, "Close book", 100, function() if ns.Book.CloseBook then ns.Book.CloseBook() end end))
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
  -- Sits as its own row ABOVE the left button stack (Join/Show math/All math).
  -- The picker dropdown previously overlapped the "All math" button, which was
  -- added to that stack later -- keep this block clear of the top button (y92).
  f.adminStatus = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.adminStatus:SetPoint("BOTTOMLEFT", 16, 134); f.adminStatus:SetJustifyH("LEFT")
  f.adminDD = CreateFrame("Frame", "AGNB_BookAdmin_DD", f, "UIDropDownMenuTemplate")
  f.adminDD:SetPoint("BOTTOMLEFT", 0, 102); UIDropDownMenu_SetWidth(f.adminDD, 120)
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

-- Build the "Book Admin" settlement report: a master "who pays whom / what's
-- paid" list (the thing an admin watches to confirm everyone settled up), then
-- compact per-player nets + bet-by-bet detail for disputes. Re-rendered on every
-- Refresh, so it updates live as payments confirm (trade/mail auto-detect, or a
-- recipient's "/agnb book paid"). Transfers are whole gold; the bet detail keeps
-- the exact deltas, so a player's audited net can differ by the rounding drift.
function BUI.AdminReport()
  local ST = ns.Settlement
  if not (ST and ST.state) then
    return "Close the book to settle, then the whole raid's settlement shows here."
  end
  local me = ns.MyName or (UnitName and UnitName("player")) or "?"
  local sum = ns.Book.SettleSummary(ST.state)
  local out = {}
  out[#out + 1] = ("|cffffd966Settlement|r   %d of %d transfers settled  \194\183  |cffff8844%s outstanding|r")
    :format(sum.settled, sum.total, money(sum.outstanding))
  if sum.total == 0 then
    out[#out + 1] = " "; out[#out + 1] = "  Nobody owes anyone \226\128\148 all square."
  end
  -- outstanding first (what still needs paying), then the settled receipts
  local owed, paid = {}, {}
  for _, t in ipairs(ST.state.transfers) do
    if t.settled then
      paid[#paid + 1] = ("  |cff66ff66%s \226\134\146 %s   %s  (paid)|r"):format(t.from, t.to, money(t.amount))
    else
      local remaining = (t.amount or 0) - (t.paid or 0)
      local hint = (t.to == me) and ("   |cff888888/agnb book paid %s|r"):format(t.from) or ""
      owed[#owed + 1] = ("  |cffffffff%s \226\134\146 %s|r   |cffff8844%s|r%s"):format(t.from, t.to, money(remaining), hint)
    end
  end
  if #owed > 0 then
    out[#out + 1] = " "; out[#out + 1] = "|cffffd966Outstanding \226\128\148 who still owes:|r"
    for _, l in ipairs(owed) do out[#out + 1] = l end
  end
  if #paid > 0 then
    out[#out + 1] = " "; out[#out + 1] = "|cffffd966Settled:|r"
    for _, l in ipairs(paid) do out[#out + 1] = l end
  end
  -- per-player detail for disputes: net + each bet (compact line so it rarely wraps)
  local all = (ST.AllMath and ST.AllMath()) or {}
  if #all > 0 then
    out[#out + 1] = " "; out[#out + 1] = "|cffffd966Player math (audit):|r"
    for _, e in ipairs(all) do
      out[#out + 1] = ("|cffffffff%s|r  net %s"):format(e.player, moneyDelta(e.net))
      for _, ln in ipairs(e.lines or {}) do
        out[#out + 1] = ("    [%d] %s \194\183 %s \226\134\146 %s  %s"):format(
          ln.seq or 0, ln.bet or "?", tostring(ln.pick), ln.result or "", moneyDelta(ln.delta))
      end
    end
    out[#out + 1] = " "
    out[#out + 1] = "  |cff888888Transfers are rounded to whole gold; this audit shows exact stakes, "
      .. "so a player's net can differ by <1g. It all nets to zero.|r"
  end
  return table.concat(out, "\n")
end

function BUI.Refresh()
  local f = BUI.frame
  if not f or not f:IsShown() then return end

  local off = not (ns.cfg and ns.cfg.bookEnabled)
  f.offPrompt:SetShown(off); f.enableBtn:SetShown(off)
  if off then
    for _, w in ipairs({ f.state, f.openBtn, f.draftBtn, f.lockDraftBtn, f.ouLabel, f.overBtn,
        f.underBtn, f.fbLabel, f.fbDD, f.hsLabel, f.hsSurvBtn, f.hsDiesBtn, f.body, f.joinBtn,
        f.closeBtn, f.mathBtn, f.allMathBtn, f.mathPane, f.ignoreBtn, f.inviteBtn, f.settleBtn,
        f.title, f.adminStatus, f.adminDD, f.setAdminBtn, f.clearAdminBtn }) do
      if w then w:SetShown(false) end
    end
    return
  end

  local r = rt() and rt().round
  local dr = rt() and rt().draft
  local admin = ns.Book.CanAdmin()

  setShown(f.openBtn, admin); setShown(f.draftBtn, admin)
  local lockOpen = admin and dr and dr.state == "OPEN"
  setShown(f.lockDraftBtn, lockOpen)
  setShown(f.closeBtn, admin)
  -- close up the row when Lock draft is hidden (no empty slot for it)
  f.closeBtn:ClearAllPoints()
  f.closeBtn:SetPoint("LEFT", lockOpen and f.lockDraftBtn or f.draftBtn, "RIGHT", 6, 0)
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
    local open = r.state == "OPEN"
    -- one bet per round: once placed, hide the buttons and show the locked pick.
    local ouBet = r.myOU and r.myOU.pick
    if ouBet then
      f.ouLabel:SetText(("Over/Under %.1f (%dg)  ·  |cff66ff66your bet: %s|r"):format(r.line, r.stakeOU, ouBet))
    else
      f.ouLabel:SetText(("Over/Under %.1f deaths this pull (%dg):"):format(r.line, r.stakeOU))
    end
    -- auto-show the Hot Seat popup once per round open (guard avoids re-popping on refresh)
    if open and BUI._popupShownFor ~= r.id then
      BUI._popupShownFor = r.id
      BUI.ShowHotSeatPopup()
    end
    setShown(f.ouLabel, true)
    setShown(f.overBtn, open and not ouBet); setShown(f.underBtn, open and not ouBet)
    setShown(f.fbLabel, open); setShown(f.fbDD, open and not r.myFB)
    if open and not r.myFB then UIDropDownMenu_Initialize(f.fbDD, fbInitialize) end
    if r.myFB then f.fbLabel:SetText(("First Blood: |cff66ff66your bet: %s|r"):format(r.myFB.pick)) end
    -- hot seat row
    local rd = r
    if rd.hs then
      local me = ns.MyName or (UnitName and UnitName("player"))
      local tgt = ns.Book.DealTarget(rd.hs.seed, rd.hs.targets, me)
      local pDie = rd.hs.lines[tgt] or 0.5
      local hsBet = rd.myHS and rd.myHS.pick
      if hsBet then
        f.hsLabel:SetText(("Hot Seat: %s  ·  |cff66ff66your bet: %s|r"):format(tgt, hsBet))
      else
        f.hsLabel:SetText(("Hot Seat: %s  ·  Survives %s / Dies %s"):format(
          tgt, ns.Book.OddsFromProb(1 - pDie), ns.Book.OddsFromProb(pDie)))
      end
      local selfTarget = (tgt == me)
      setShown(f.hsSurvBtn, open and not hsBet); setShown(f.hsDiesBtn, open and not selfTarget and not hsBet)
      setShown(f.hsLabel, open)
    else
      setShown(f.hsLabel, false); setShown(f.hsSurvBtn, false); setShown(f.hsDiesBtn, false)
    end
  else
    f.state:SetText("No betting round yet." .. (admin and " (Open one above.)" or " Waiting for the raid leader."))
    f.ouLabel:SetText(""); setShown(f.overBtn, false); setShown(f.underBtn, false)
    setShown(f.fbLabel, false); setShown(f.fbDD, false)
    setShown(f.hsLabel, false); setShown(f.hsSurvBtn, false); setShown(f.hsDiesBtn, false)
  end

  -- ----- Raid Hot Seat status (whole-raid market, independent of the per-pull round) -----
  local rh = rt() and rt().raidHS
  if ns.Book.RefreshRaidHSCount then ns.Book.RefreshRaidHSCount() end
  if rh and rh.state == "OPEN" and BUI._rhsPopupShownFor ~= rh.id then
    BUI._rhsPopupShownFor = rh.id
    BUI.ShowRaidHotSeatPopup()
  end

  -- body: results + draft standings
  local lines = {}
  if rh and rh.state ~= "SETTLED" then
    local meName = ns.MyName or (UnitName and UnitName("player"))
    if rh.state == "OPEN" then
      if rh.subject == meName then
        lines[#lines + 1] = ("|cffffd966Raid Hot Seat:|r you're tonight's Hot Seat (O/U %.1f) -- no bet."):format(rh.line)
      else
        lines[#lines + 1] = ("|cffffd966Raid Hot Seat:|r %s -- Over/Under %.1f deaths (%dg). Bet in the popup."):format(
          rh.subject, rh.line, rh.stake)
      end
    else
      lines[#lines + 1] = ("|cffffd966Raid Hot Seat:|r %s -- %d deaths so far (line %.1f)."):format(
        rh.subject, rh.count or 0, rh.line)
    end
    lines[#lines + 1] = " "
  end
  if r and (r.state == "RESOLVED" or r.state == "SETTLED") then
    lines[#lines + 1] = ("Outcome: %s  ·  First blood: %s"):format(r.outcomeOU or "?", r.outcomeFB or "?")
    if r.settleOU then
      lines[#lines + 1] = ("O/U pot %dg - winners: %s"):format(r.settleOU.pot, table.concat(r.settleOU.winners, ", "))
    end
    if r.settleFB then
      lines[#lines + 1] = ("First Blood pot %dg - winners: %s"):format(r.settleFB.pot,
        (#r.settleFB.winners > 0 and table.concat(r.settleFB.winners, ", ") or "nobody (rolls over)"))
    end
    -- Hot Seat: per-target outcome + this player's own win/loss (was previously only
    -- in chat / Bet Records -- surface it in the betting window like O/U and FB).
    if r.hs and r.hs.outcomes and next(r.hs.outcomes) then
      local parts = {}
      for _, t in ipairs(r.hs.targets or {}) do
        local o = r.hs.outcomes[t]
        if o then parts[#parts + 1] = ("%s %s"):format(t, o) end
      end
      if #parts > 0 then lines[#lines + 1] = "Hot Seat: " .. table.concat(parts, ", ") end
      local me = ns.MyName or (UnitName and UnitName("player"))
      if r.hs.result and me then
        local matched = false
        for _, pr in ipairs(r.hs.result.pairs or {}) do
          if pr.winner == me or pr.loser == me then matched = true; break end
        end
        local d = r.hs.result.deltas and r.hs.result.deltas[me]
        local tgt = ns.Book.DealTarget(r.hs.seed, r.hs.targets, me)
        if matched and d then
          if d >= 0 then
            lines[#lines + 1] = ("  Your Hot Seat (%s): won +%dg"):format(tostring(tgt), math.floor(d / 10000 + 0.5))
          else
            lines[#lines + 1] = ("  Your Hot Seat (%s): lost %dg"):format(tostring(tgt), math.floor(-d / 10000 + 0.5))
          end
        elseif r.myHS then
          lines[#lines + 1] = "  Your Hot Seat bet was unmatched (refunded)."
        end
      end
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

  -- ----- "Book Admin" view: a clean, full-window, auto-updating settlement report.
  -- It REPLACES the betting controls (rather than overlaying them, which collided)
  -- so the admin sees only the who-pays-whom / what's-paid report while it's open.
  local adminView = BUI.showAllMath and admin and ns.Settlement
  if f.allMathBtn then f.allMathBtn:SetText(adminView and "Back to betting" or "Book Admin") end
  -- betting-view widgets, hidden while the admin report is up so nothing overlaps it
  local bettingWidgets = { f.state, f.openBtn, f.draftBtn, f.lockDraftBtn, f.closeBtn,
    f.ouLabel, f.overBtn, f.underBtn, f.fbLabel, f.fbDD, f.hsLabel, f.hsSurvBtn, f.hsDiesBtn,
    f.body, f.mathBtn, f.ignoreBtn, f.inviteBtn, f.adminStatus, f.adminDD, f.setAdminBtn,
    f.clearAdminBtn }
  if adminView then
    for _, w in ipairs(bettingWidgets) do setShown(w, false) end
    setShown(f.joinBtn, false)
    -- the toggle becomes a bottom-left "back" button, clear of the report pane
    f.allMathBtn:ClearAllPoints(); f.allMathBtn:SetPoint("BOTTOMLEFT", 16, 14)
    f.mathPane:ClearAllPoints()
    f.mathPane:SetPoint("TOPLEFT", 16, -44); f.mathPane:SetPoint("BOTTOMRIGHT", -30, 44)
    f.mathText:SetText(BUI.AdminReport())
    f.mathChild:SetHeight((f.mathText:GetStringHeight() or 10) + 12)
    f.mathPane:Show(); f.body:Hide()
  else
    -- restore the toggle to the left button stack above "Show math"
    f.allMathBtn:ClearAllPoints(); f.allMathBtn:SetPoint("BOTTOMLEFT", f.mathBtn, "TOPLEFT", 0, 6)
    f.mathPane:Hide(); f.body:Show()
    f.body:SetText(table.concat(lines, "\n"))
    setShown(f.joinBtn, dr and dr.state == "OPEN")
    if f.inviteBtn then f.inviteBtn:SetShown(ns.AntiPrize and ns.AntiPrize.CanInvite() or false) end
  end
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

-- Between-pulls Hot Seat popup: lazily created, parented to UIParent so it
-- floats independently of the main book panel.
function BUI.ShowHotSeatPopup()
  -- guard: wagering must be on and the round must have a hot-seat config
  if not (ns.cfg and ns.cfg.bookEnabled) then return end
  local rd = rt() and rt().round
  if not rd then return end
  if not rd.hs then return end

  -- deal this player's target
  local me = ns.MyName or (UnitName and UnitName("player"))
  local target = ns.Book.DealTarget(rd.hs.seed, rd.hs.targets, me)
  if not target then return end

  -- odds + stakes
  local pDie = rd.hs.lines[target] or 0.5
  local stk   = ns.Book.HotSeatStakes(pDie, rd.hs.stakeBase)

  -- survives side: risk is favStake when favSide=="survives", else dogStake
  local survRisk = (stk.favSide == "survives") and stk.favStake or stk.dogStake
  local survWin  = (stk.favSide == "survives") and stk.dogStake  or stk.favStake
  local diesRisk = (stk.favSide == "dies")     and stk.favStake  or stk.dogStake
  local diesWin  = (stk.favSide == "dies")     and stk.dogStake  or stk.favStake

  -- lazily build the popup frame
  local p = BUI.popup
  if not p then
    p = CreateFrame("Frame", "AGNB_HotSeatPopup", UIParent, "BackdropTemplate")
    p:SetSize(340, 180); p:SetPoint("CENTER", 0, 80)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetMovable(true); p:EnableMouse(true); p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving); p:SetScript("OnDragStop", p.StopMovingOrSizing)
    if p.SetBackdrop then
      p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                      edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
      p:SetBackdropColor(0.05, 0.04, 0.02, 0.97)
      p:SetBackdropBorderColor(0.6, 0.5, 0.1, 1)
    end
    local cx = CreateFrame("Button", nil, p, "UIPanelCloseButton"); cx:SetPoint("TOPRIGHT", 2, 2)
    cx:SetScript("OnClick", function() p:Hide() end)

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT", 14, -14); p.title:SetTextColor(unpack(GOLD))

    p.stats = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.stats:SetPoint("TOPLEFT", 14, -40); p.stats:SetWidth(300); p.stats:SetJustifyH("LEFT")

    p.survBtn = btn(p, "Survives", 90, function()
      ns.Book.PlaceHS("survives"); p:Hide()
    end)
    p.survBtn:SetPoint("BOTTOMLEFT", 14, 14)

    p.diesBtn = btn(p, "Dies", 80, function()
      ns.Book.PlaceHS("dies"); p:Hide()
    end)
    p.diesBtn:SetPoint("LEFT", p.survBtn, "RIGHT", 6, 0)

    p.skipBtn = btn(p, "Skip", 70, function() p:Hide() end)
    p.skipBtn:SetPoint("LEFT", p.diesBtn, "RIGHT", 6, 0)

    BUI.popup = p
  end

  -- populate title: target name + odds for each side
  local survOdds = ns.Book.OddsFromProb(1 - pDie)
  local diesOdds = ns.Book.OddsFromProb(pDie)
  p.title:SetText(("Hot Seat: %s"):format(target))

  -- populate stats: odds line + risk/win amounts + all-time deaths
  local store = (ns.Demo and ns.Demo.store) or (ns.db and ns.db.store)
  local rec   = store and store.allTime and store.allTime[target]
  -- risk/win come straight from HotSeatStakes(pDie, stakeBase) where stakeBase is in
  -- GOLD, so they are gold integers -- format with %dg, not money() (which expects copper).
  local statsLines = {
    ("Survives %s  (risk %dg, win %dg)"):format(survOdds, survRisk, survWin),
    ("Dies     %s  (risk %dg, win %dg)"):format(diesOdds, diesRisk, diesWin),
  }
  if rec then
    local nemLine = ""
    if rec.byCause then
      local topK, topV = nil, 0
      for k, v in pairs(rec.byCause) do
        if v > topV then topK, topV = k, v end
      end
      if topK then
        -- byCause keys are "ability\31source"; show just ability for readability
        local ability = topK:match("^([^\31]+)")
        nemLine = ("  ·  nemesis: %s"):format(ability or topK)
      end
    end
    statsLines[#statsLines + 1] = ("All-time deaths: %d%s"):format(rec.deaths or 0, nemLine)
  end
  p.stats:SetText(table.concat(statsLines, "\n"))

  -- hide Dies button when the player is their own target
  local selfTarget = (target == me)
  p.diesBtn:SetShown(not selfTarget)
  -- re-anchor Skip so it hugs the visible buttons
  p.skipBtn:ClearAllPoints()
  if selfTarget then
    p.skipBtn:SetPoint("LEFT", p.survBtn, "RIGHT", 6, 0)
  else
    p.skipBtn:SetPoint("LEFT", p.diesBtn, "RIGHT", 6, 0)
  end

  p:Show()
end

-- Raid Hot Seat popup: a floating Over/Under bet on the night's nominated raider.
-- Floats over UIParent so it never collides with the book panel layout. Pops once at
-- open for everyone except the subject (who can't bet on their own count).
function BUI.ShowRaidHotSeatPopup()
  if not (ns.cfg and ns.cfg.bookEnabled) then return end
  local rh = rt() and rt().raidHS
  if not (rh and rh.state == "OPEN") then return end
  local me = ns.MyName or (UnitName and UnitName("player"))
  if rh.subject == me then return end   -- the subject can't bet on themselves

  local p = BUI.rhsPopup
  if not p then
    p = CreateFrame("Frame", "AGNB_RaidHotSeatPopup", UIParent, "BackdropTemplate")
    p:SetSize(340, 150); p:SetPoint("CENTER", 0, 120)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetMovable(true); p:EnableMouse(true); p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving); p:SetScript("OnDragStop", p.StopMovingOrSizing)
    if p.SetBackdrop then
      p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                      edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
      p:SetBackdropColor(0.05, 0.04, 0.02, 0.97)
      p:SetBackdropBorderColor(0.6, 0.5, 0.1, 1)
    end
    local cx = CreateFrame("Button", nil, p, "UIPanelCloseButton"); cx:SetPoint("TOPRIGHT", 2, 2)
    cx:SetScript("OnClick", function() p:Hide() end)
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT", 14, -14); p.title:SetTextColor(unpack(GOLD))
    p.stats = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.stats:SetPoint("TOPLEFT", 14, -42); p.stats:SetWidth(300); p.stats:SetJustifyH("LEFT")
    p.overBtn = btn(p, "Over", 90, function() ns.Book.PlaceRaidHS("over"); p:Hide() end)
    p.overBtn:SetPoint("BOTTOMLEFT", 14, 14)
    p.underBtn = btn(p, "Under", 90, function() ns.Book.PlaceRaidHS("under"); p:Hide() end)
    p.underBtn:SetPoint("LEFT", p.overBtn, "RIGHT", 6, 0)
    p.skipBtn = btn(p, "Skip", 70, function() p:Hide() end)
    p.skipBtn:SetPoint("LEFT", p.underBtn, "RIGHT", 6, 0)
    BUI.rhsPopup = p
  end
  p.title:SetText(("Raid Hot Seat: %s"):format(rh.subject))
  p.stats:SetText(("Over/Under %.1f deaths this whole raid.\nFlat stake: risk %dg to win the pool."):format(
    rh.line, rh.stake))
  p:Show()
end

function BUI.Toggle()
  local f = build()
  if f:IsShown() then f:Hide() else f:Show(); BUI.Refresh() end
end
