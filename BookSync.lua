local _, ns = ...
ns = ns or __AGNB_NS
ns.Book = ns.Book or {}
local B = ns.Book

-- Runtime orchestration for The Book (in-game glue; pure logic lives in Book.lua).
-- One betting "round" per pull covers Over/Under + First Blood together. Outcomes
-- resolve from the synced death log over the pull's TIME WINDOW (pullId isn't a
-- reliable cross-client key), so every client computes the same result.

B.rt = B.rt or { round = nil, draft = nil, history = {} }
local rt = B.rt

local function copyMap(m)
  local o = {}
  if m then for k, v in pairs(m) do o[k] = v end end
  return o
end

local function cfg() return ns.cfg or {} end
local function myName() return ns.MyName or (UnitName and UnitName("player")) or "?" end

local function send(msg)
  local chan = ns.Sync and ns.Sync.Channel and ns.Sync.Channel()
  if chan and C_ChatInfo then C_ChatInfo.SendAddonMessage(ns.Sync.PREFIX, msg, chan) end
end

-- leader / assist / dev may open rounds and set stakes
function B.CanAdmin()
  if ns.Demo and ns.Demo.active then return true end   -- dev aid: mock data grants admin so admin UI is previewable solo
  if ns.db and ns.db.designatedAdmin and ns.db.designatedAdmin == myName() then return true end
  local isL = UnitIsGroupLeader and UnitIsGroupLeader("player") or false
  local isA = UnitIsGroupAssistant and UnitIsGroupAssistant("player") or false
  local tag; if BNGetInfo then local _, bt = BNGetInfo(); tag = bt end
  return ns.Summary and ns.Summary.CanBroadcast(isL, isA, myName(), tag) or false
end

-- Who may appoint/clear a delegate: a LIVE leader/assist or dev only -- never the
-- delegate (prevents a delegate from appointing further admins).
function B.CanAppoint()
  if ns.Demo and ns.Demo.active then return true end
  local isL = UnitIsGroupLeader and UnitIsGroupLeader("player") or false
  local isA = UnitIsGroupAssistant and UnitIsGroupAssistant("player") or false
  local tag; if BNGetInfo then local _, bt = BNGetInfo(); tag = bt end
  return ns.Summary and ns.Summary.CanBroadcast(isL, isA, myName(), tag) or false
end

local function genNonce()
  return ns.Hash.SHA256(tostring((GetTime and GetTime()) or 0) .. ":" .. tostring(math.random())
    .. ":" .. myName()):sub(1, 16)
end

local function activeStore()
  local demo = ns.Demo and ns.Demo.active
  local store = demo and ns.Demo.store or (ns.db and ns.db.store)
  local raidId = demo and ns.Demo.raidId or (ns.Tracking and ns.Tracking.raidId)
  return store, raidId
end

local function windowDeaths(t0, t1)
  local store, raidId = activeStore()
  local raid = store and raidId and store.raids[raidId]
  local out = {}
  if raid then
    for _, d in ipairs(raid.deaths) do
      local t = d.time or 0
      if t >= (t0 or 0) and t <= (t1 or math.huge) then out[#out + 1] = d end
    end
  end
  return out
end

local function roster()
  if ns.Demo and ns.Demo.active and ns.Demo.DemoNames then
    local names = { myName() }
    for _, nm in ipairs(ns.Demo.DemoNames(24)) do names[#names + 1] = nm end
    return names
  end
  local out = {}
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  local inRaid = IsInRaid and IsInRaid()
  local prefix = inRaid and "raid" or "party"
  for i = 1, n do
    local nm = UnitName and UnitName(prefix .. i)
    if nm then out[#out + 1] = nm end
  end
  -- party units (party1..N) exclude the player, so add self; raid units (raidN) already
  -- include the player. Without this, a 5-man dropped the local player from the roster.
  if not inRaid then out[#out + 1] = myName() end
  if #out == 0 then out[#out + 1] = myName() end
  return out
end

local function refreshUI() if ns.BookUI and ns.BookUI.Refresh then ns.BookUI.Refresh() end end

-- Resolve whether a raid member by name currently holds leader/assist (or is a
-- dev). Used to validate admin-authoritative messages on receipt so they can't be
-- spoofed by a non-admin client.
-- Appointment-authority: the sender currently holds live leader/assist (or is a
-- dev). Used to validate admin APPOINTMENT messages -- deliberately does NOT
-- consult the delegation, so a delegate can't appoint further admins.
local function senderIsAppointer(who)
  if not who then return false end
  if ns.Summary and ns.Summary.DEV_BROADCASTERS and ns.Summary.DEV_BROADCASTERS[who] then return true end
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
  for i = 1, n do
    local unit = prefix .. i
    if UnitName and UnitName(unit) == who then
      return (UnitIsGroupLeader and UnitIsGroupLeader(unit))
          or (UnitIsGroupAssistant and UnitIsGroupAssistant(unit)) or false
    end
  end
  return false
end
B.senderIsAppointer = senderIsAppointer

-- Action-authority: a live appointer OR the standing delegate. Used to validate
-- Book action messages (open/close/void/draft) so the delegate's actions apply.
local function senderIsAdmin(who)
  if ns.db and ns.db.designatedAdmin and ns.db.designatedAdmin == who then return true end
  return senderIsAppointer(who)
end
B.senderIsAdmin = senderIsAdmin

-- ----- delegated admin: a leader/assist appoints a non-leader to run the book -----
-- Pure: resolve an admin change given the sender's already-validated authority.
function B.ResolveAdminMsg(current, rest, isAppointer)
  if not isAppointer then return current end
  local op, name = rest:match("^([^|]*)|?(.*)$")
  if op == "set" and name ~= "" then return name
  elseif op == "clear" then return nil end
  return current
end

function B.SetAdmin(name)
  if not B.CanAppoint() then ns.Print("Only the raid leader/assist can set the AGNB admin.") return end
  if not name or name == "" then return end
  if ns.db then ns.db.designatedAdmin = name end
  send("BADM|set|" .. name)
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  refreshUI()
  ns.Print(("AGNB admin set to %s."):format(name))
end

function B.ClearAdmin()
  if not B.CanAppoint() then ns.Print("Only the raid leader/assist can clear the AGNB admin.") return end
  if ns.db then ns.db.designatedAdmin = nil end
  send("BADM|clear")
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  refreshUI()
  ns.Print("AGNB admin cleared.")
end

function B.OnAdminMsg(rest, who)
  if ns.db then
    ns.db.designatedAdmin = B.ResolveAdminMsg(ns.db.designatedAdmin, rest, senderIsAppointer(who))
  end
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  refreshUI()
end

-- Current raid leader + assistants (for privately whispering collusion alerts).
local function adminNames()
  local out = {}
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
  for i = 1, n do
    local unit = prefix .. i
    if (UnitIsGroupLeader and UnitIsGroupLeader(unit)) or (UnitIsGroupAssistant and UnitIsGroupAssistant(unit)) then
      local nm = UnitName and UnitName(unit); if nm then out[#out + 1] = nm end
    end
  end
  return out
end

local function whisperAdmins(msg)
  for _, a in ipairs(adminNames()) do
    if a ~= myName() and C_ChatInfo then
      C_ChatInfo.SendAddonMessage(ns.Sync.PREFIX, msg, "WHISPER", a)
    end
  end
end

B.collusionAlerts = B.collusionAlerts or {}

-- Scan MY incoming whisper; on a hit, warn me and privately alert all admins.
function B.OnWhisper(text, sender)
  if not cfg().collusionWatch then return end
  local score = ns.Book.ScoreWhisper(text)
  if score < 2 then return end
  -- strip the pipe delimiter from the forwarded snippet so it can't truncate/garble the
  -- "BCOL|sender|snippet" addon message on the admin's side (Book messages aren't escaped).
  local snippet = ((text or ""):sub(1, 120)):gsub("|", "/")
  B.lastFlag = { sender = sender, snippet = snippet }
  ns.Print("|cffff5555Possible bet-rigging whisper from " .. tostring(sender)
    .. ".|r Type /agnb book report to forward it to officers.")
  whisperAdmins(("BCOL|%s|%s"):format(tostring(sender), snippet))
  refreshUI()
end

-- I choose to forward fuller context to officers.
function B.ReportLastFlag()
  if not B.lastFlag then ns.Print("Nothing flagged to report.") return end
  whisperAdmins(("BCOLR|%s|%s"):format(tostring(B.lastFlag.sender), B.lastFlag.snippet))
  ns.Print("Reported to officers.")
end

-- Admin receives an auto alert / a manual report.
function B.OnCollusionAlert(who, rest)
  if not B.CanAdmin() then return end
  local suspect, snip = rest:match("^([^|]*)|(.*)$")
  B.collusionAlerts[#B.collusionAlerts + 1] = { reporter = who, suspect = suspect, snippet = snip, kind = "auto" }
  refreshUI()
end

function B.OnCollusionReport(who, rest)
  if not B.CanAdmin() then return end
  local suspect, snip = rest:match("^([^|]*)|(.*)$")
  B.collusionAlerts[#B.collusionAlerts + 1] = { reporter = who, suspect = suspect, snippet = snip, kind = "report" }
  refreshUI()
end

-- Admin: close the book at raid end -> everyone computes settlement + checksum.
-- The runner resolves the Raid Hot Seat locally first and ships its authoritative
-- outcome + count in the close message so clients adopt one canonical result.
function B.CloseBook()
  if not B.CanAdmin() then ns.Print("Only the raid leader/assist can close the book.") return end
  B.ResolveAndSettleRaidHS((time and time()) or 0)
  local rh = rt.raidHS
  local payload = (rh and ("%s|%s|%d"):format(rh.id, tostring(rh.outcome), rh.count or 0)) or "||"
  send("BSET|1|" .. payload)
  B.OnCloseBook()
end

-- rhsOutcome/rhsCount: the runner's authoritative Raid Hot Seat result (from the close
-- message), adopted instead of a local recompute. nil on the runner's own call (already
-- settled above) and for any client that didn't get them (falls back to local count).
function B.OnCloseBook(rhsOutcome, rhsCount)
  rt.closed = true
  B.ResolveAndSettleRaidHS((time and time()) or 0, rhsOutcome, rhsCount)
  if ns.Settlement and ns.Settlement.Compute then
    ns.Settlement.Compute()
    local chk = ns.Settlement.checksum
    if chk then
      send(("BNCHK|%s"):format(chk))
      if ns.Settlement.OnChecksum then ns.Settlement.OnChecksum(myName(), chk) end
    end
  end
  refreshUI()
end

-- Admin: void a pull window from both the shame counts and the bet ledger.
function B.IgnorePull(t0, t1)
  if not B.CanAdmin() then ns.Print("Only an admin can void a pull.") return end
  if rt.closed then ns.Print("The book is closed -- void pulls before settling.") return end
  send(("BIGN|%d|%d"):format(t0, t1))
  B.OnIgnorePull(t0, t1)
end

function B.OnIgnorePull(t0, t1)
  local store, raidId = activeStore()
  if store and raidId then ns.DB.VoidWindow(store, raidId, t0, t1) end
  if rt.ledger then
    local kept = {}
    for _, r in ipairs(rt.ledger) do
      local overlap = (r.lockTime or 0) <= t1 and (r.endTime or math.huge) >= t0
      if not overlap then kept[#kept + 1] = r end
    end
    rt.ledger = kept
  end
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  refreshUI()
end

-- The recent-pulls list for the admin ignore-pull picker.
function B.RecentPullList()
  local store, raidId = activeStore()
  local raid = store and raidId and store.raids[raidId]
  return ns.Book.RecentPulls(raid and raid.deaths or {})
end

-- ----- Over/Under + First Blood round -----
function B.OpenRound()
  if not cfg().bookEnabled then ns.Print("Wagering is off (enable it in Settings).") return end
  if not B.CanAdmin() then ns.Print("Only the raid leader/assist can open a betting round.") return end
  local line = ns.Book.AutoLine(rt.history, cfg().bookLineFallback or 0.5)
  local id = tostring((GetTime and math.floor(GetTime() * 1000)) or math.random(1, 1e9))
  send(("BO|%s|%s|%s|%s"):format(id, tostring(line), tostring(cfg().bookStakeOU or 0), tostring(cfg().bookStakeFB or 0)))
  B.OnOpen(id, line, cfg().bookStakeOU or 0, cfg().bookStakeFB or 0)
  ns.Print(("Betting open: Over/Under %.1f deaths this pull."):format(line))
  -- Hot Seat sub-market: skip if fewer than 4 raiders (not enough to be meaningful)
  local currentRoster = roster()
  if #currentRoster >= 4 then
    local seed = id
    local n = ns.Book.TargetCount(#currentRoster)
    local targets = ns.Book.RollTargets(seed, currentRoster, n)
    -- build per-player death counts from all-time history (synced, so the line
    -- is identical on every client and meaningful from the first pull)
    local store = activeStore()
    local deathCounts = {}
    if store and store.allTime then
      for name, p in pairs(store.allTime) do deathCounts[name] = p.deaths or 0 end
    end
    -- build payload: "name=line,name=line,..."
    local parts = {}
    local lines = {}
    for _, name in ipairs(targets) do
      local p = ns.Book.SurvivalLine(deathCounts, currentRoster, name)
      lines[name] = p
      parts[#parts + 1] = name .. "=" .. string.format("%.2f", p)
    end
    local payload = table.concat(parts, ",")
    -- Hot Seat base stake: default to 5g if unset/blank, and hold it to 1..10g so
    -- the betting window always shows a real wager (never 0g) and stays capped.
    local hsStake = tonumber(cfg().bookStakeHS) or 5
    if hsStake < 1 then hsStake = 5 elseif hsStake > 10 then hsStake = 10 end
    local sHS = tostring(hsStake)
    send(("BOH|%s|%s|%s|%s"):format(id, seed, sHS, payload))
    B.OnOpenHotSeat(id, seed, sHS, payload)
  end
end

function B.OnOpen(id, line, stakeOU, stakeFB)
  -- Don't clobber a live round: re-applying the SAME id is an idempotent no-op (keeps
  -- commits already received), and a DIFFERENT id while a round is still in progress is
  -- rejected so a second admin re-opening can't wipe everyone's pending bets.
  if rt.round then
    if rt.round.id == id then return end
    if rt.round.state ~= "SETTLED" then return end
  end
  rt.round = {
    id = id, line = tonumber(line) or 0.5,
    stakeOU = tonumber(stakeOU) or 0, stakeFB = tonumber(stakeFB) or 0,
    ou = ns.Book.NewRound(nil, nil, "OU", tonumber(line) or 0.5),
    fb = ns.Book.NewRound(nil, nil, "FB"),
    state = "OPEN",
  }
  -- Apply a Hot Seat open (BOH) that arrived BEFORE this round open (BO) -- addon
  -- messages can reorder under throttle, and without this the Hot Seat would be dropped.
  if rt._pendingHS and rt._pendingHS.id == id then
    local p = rt._pendingHS; rt._pendingHS = nil
    B.OnOpenHotSeat(p.id, p.seed, p.sHS, p.payload)
  end
  refreshUI()
end

-- Parse the Hot Seat broadcast and attach rd.hs to the current round.
-- payload: "name=line,name=line,..." (names never contain = or ,).
function B.OnOpenHotSeat(id, seed, sHS, payload)
  local rd = rt.round
  if not rd or rd.id ~= id then
    -- the round open hasn't arrived yet: buffer this so B.OnOpen can apply it on arrival.
    rt._pendingHS = { id = id, seed = seed, sHS = sHS, payload = payload }
    return
  end
  local targets, lines = {}, {}
  for entry in (payload or ""):gmatch("[^,]+") do
    local name, val = entry:match("^([^=]+)=(.+)$")
    if name and val then
      targets[#targets + 1] = name
      lines[name] = tonumber(val) or 0.5
    end
  end
  rd.hs = {
    seed = seed, targets = targets, lines = lines,
    stakeBase = tonumber(sHS) or 0,
    round = ns.Book.NewRound(nil, nil, "HS"),
    outcomes = {},
  }
  -- Pop the bet prompt from the open event (not just from a panel Refresh), so a player
  -- who keeps the Book window closed still gets the between-pulls Hot Seat popup. Set the
  -- Refresh guard so it doesn't double-pop. (self-target is handled inside the popup.)
  if ns.BookUI then
    ns.BookUI._popupShownFor = id
    if ns.BookUI.ShowHotSeatPopup then ns.BookUI.ShowHotSeatPopup() end
  end
  refreshUI()
end

-- ===== Raid Hot Seat (whole-raid Over/Under on one nominated raider) =====

-- Admin: open the raid-level market. Deals the subject (random, deterministic from a
-- broadcast seed) unless overridden, sets the line (auto from the subject's recent raid
-- counts, or overridden), and broadcasts it so every client agrees. Opens before the
-- first pull.
function B.OpenRaidHotSeat(subjectOverride, lineOverride)
  if not cfg().bookEnabled then ns.Print("Wagering is off (enable it in Settings).") return end
  if not B.CanAdmin() then ns.Print("Only the raid leader/assist can open the Raid Hot Seat.") return end
  if rt.raidHS and rt.raidHS.state ~= "SETTLED" then ns.Print("A Raid Hot Seat is already running.") return end
  local currentRoster = roster()
  if #currentRoster < 4 then ns.Print("Need at least 4 raiders for a Raid Hot Seat.") return end
  local id = tostring((GetTime and math.floor(GetTime() * 1000)) or math.random(1, 1e9))
  local seed = id
  local subject = subjectOverride
  if not subject or subject == "" then
    subject = ns.Book.RollTargets(seed, currentRoster, 1)[1]
  end
  if not subject then ns.Print("Could not pick a Raid Hot Seat subject.") return end
  local line = tonumber(lineOverride)
  if not line then
    local store = activeStore()
    line = ns.Book.AutoLine(ns.Book.SubjectRaidCounts(store or { raids = {} }, subject),
                            cfg().bookRaidLineFallback or 3.5)
  end
  local stake = tonumber(cfg().bookStakeRHS) or 5
  local openTime = (time and time()) or 0
  send(("BRHO|%s|%s|%s|%s|%s|%d"):format(id, seed, subject, tostring(line), tostring(stake), openTime))
  B.OnOpenRaidHS(id, seed, subject, line, stake, openTime)
  ns.Print(("Raid Hot Seat open: Over/Under %.1f deaths on %s (whole raid)."):format(line, subject))
end

-- Build rt.raidHS from an open broadcast. Idempotent on the same id; never clobbers a
-- raid HS that has already LOCKED (same guard spirit as B.OnOpen).
function B.OnOpenRaidHS(id, seed, subject, line, stake, openTime)
  if rt.raidHS then
    if rt.raidHS.id == id then return end
    if rt.raidHS.state ~= "SETTLED" then return end
  end
  rt.raidHS = {
    id = id, seed = seed, subject = subject,
    line = tonumber(line) or 0.5, stake = tonumber(stake) or 0,
    state = "OPEN", openTime = tonumber(openTime) or 0,
    round = ns.Book.NewRound(nil, nil, "RHS"),
  }
  -- Pop the bet prompt from the open event so it shows even with the Book window closed
  -- (the popup itself no-ops for the subject). Set the Refresh guard to avoid a re-pop.
  if ns.BookUI then
    ns.BookUI._rhsPopupShownFor = id
    if ns.BookUI.ShowRaidHotSeatPopup then ns.BookUI.ShowRaidHotSeatPopup() end
  end
  refreshUI()
end

-- Place a Raid Hot Seat bet ("over"/"under"). The subject can't bet on their own count.
function B.PlaceRaidHS(pick)
  local rh = rt.raidHS
  if not (rh and rh.state == "OPEN") then ns.Print("No open Raid Hot Seat.") return end
  if rh.subject == myName() then ns.Print("You're tonight's Hot Seat -- you can't bet on yourself.") return end
  if rh.myPick then ns.Print("Your Raid Hot Seat bet is already locked.") return end
  if not affordable(rh.stake) then return end
  local nonce = genNonce()
  local hash = ns.Hash.Commit(pick, nonce, myName())
  rh.myPick = { pick = pick, nonce = nonce }
  rh.round.commits[myName()] = hash  -- record our own commit so our reveal verifies locally
  send(("BRHC|%s|%s"):format(rh.id, hash))
  ns.Print(("Raid Hot Seat bet locked: %s %.1f on %s (%dg)."):format(pick, rh.line, rh.subject, rh.stake))
  refreshUI()
end

function B.OnCommitRaidHS(id, sender, hash)
  local rh = rt.raidHS
  if not (rh and rh.id == id) then return end
  ns.Book.AddCommit(rh.round, sender, hash)
  refreshUI()
end

function B.OnRevealRaidHS(id, sender, pick, nonce)
  local rh = rt.raidHS
  if not (rh and rh.id == id) then return end
  ns.Book.AddReveal(rh.round, sender, pick, nonce)
  refreshUI()
end

-- Lock the raid HS at the first pull of the night: stop betting and reveal my side so
-- the field is verifiable for the rest of the raid. Independent of the per-pull round.
local function lockRaidHS()
  local rh = rt.raidHS
  if not (rh and rh.state == "OPEN") then return end
  rh.state = "LOCKED"; rh.lockTime = (time and time()) or 0
  ns.Book.Lock(rh.round)
  if rh.myPick then
    send(("BRHR|%s|%s|%s"):format(rh.id, rh.myPick.pick, rh.myPick.nonce))
    ns.Book.AddReveal(rh.round, myName(), rh.myPick.pick, rh.myPick.nonce)
  end
  refreshUI()
end

-- Refresh the live subject count for the locked Raid Hot Seat tracker (panel display).
function B.RefreshRaidHSCount()
  local rh = rt.raidHS
  if not (rh and rh.state == "LOCKED") then return end
  local window = windowDeaths(rh.openTime, (time and time()) or 0)
  local n = 0
  for _, d in ipairs(window) do
    if d.player == rh.subject and d.classification ~= "wipeCascade" then n = n + 1 end
  end
  rh.count = n
end

-- Resolve the raid HS at Close book: count the subject's counted deaths in the
-- [openTime, closeTime] window, resolve O/U against the line, append a pari-mutuel
-- ledger entry (reusing the OU fields so SettlementBreakdown/RoundDeltas settle it),
-- and record bet results. All gold math is RoundDeltas/ResolveOU.
-- outcomeOverride/countOverride (admin-authoritative): when the admin's close carries a
-- resolved outcome, adopt it instead of recomputing locally, so every client agrees even
-- if their death window differed. Additive -- a missing/garbage override falls back to the
-- local count (current behavior), so it can only reduce divergence.
function B.ResolveAndSettleRaidHS(closeTime, outcomeOverride, countOverride)
  local rh = rt.raidHS
  if not rh or rh.state == "SETTLED" then return end
  rh.closeTime = closeTime or (time and time()) or 0
  local counted
  if outcomeOverride == "over" or outcomeOverride == "under" then
    rh.outcome = outcomeOverride
    counted = tonumber(countOverride) or 0
  else
    local window = windowDeaths(rh.openTime, rh.closeTime)
    local subjectDeaths = {}
    for _, d in ipairs(window) do
      if d.player == rh.subject then subjectDeaths[#subjectDeaths + 1] = d end
    end
    -- ResolveOU counts non-cascade deaths in the list and compares to the line.
    rh.outcome = ns.Book.ResolveOU(rh.line, subjectDeaths, nil)
    counted = 0
    for _, d in ipairs(subjectDeaths) do if d.classification ~= "wipeCascade" then counted = counted + 1 end end
  end
  rh.count = counted
  rh.state = "SETTLED"

  local stakeC = (rh.stake or 0) * 10000
  rt.ledger = rt.ledger or {}
  rt.seq = (rt.seq or 0) + 1
  rt.ledger[#rt.ledger + 1] = {
    seq = rt.seq, roundId = rh.id, raidHS = true, subject = rh.subject, line = rh.line,
    ouReveals = copyMap(rh.round.reveals), ouOutcome = rh.outcome, ouStake = stakeC, ouCount = counted,
  }
  -- live Bet Records (gold, like recordResults for OU/FB)
  local store = activeStore()
  if store then
    local deltas = ns.Book.RoundDeltas(rh.round.reveals, rh.outcome, stakeC)
    for player, pick in pairs(rh.round.reveals) do
      local c = deltas[player] or 0
      local gold = (c >= 0) and math.floor(c / 10000 + 0.5) or -math.floor(-c / 10000 + 0.5)
      ns.DB.RecordBetResult(store, player, pick == rh.outcome, gold)
    end
  end
  refreshUI()
end

-- check the player can afford a stake before locking it in
local function affordable(stake)
  local gold = (GetMoney and math.floor(GetMoney() / 10000)) or 0
  local ok, reason = ns.Book.ValidateStake(stake, gold, cfg().bookMaxBetPct or 0)
  if not ok then ns.Print(reason) end
  return ok
end

-- place / change a hidden Over-Under bet ("over"/"under") while OPEN
function B.PlaceOU(pick)
  local rd = rt.round
  if not (rd and rd.state == "OPEN") then ns.Print("No open betting round.") return end
  if rd.myOU then ns.Print("Your Over/Under bet is already locked for this round.") return end
  if not affordable(rd.stakeOU) then return end
  local nonce = genNonce()
  local hash = ns.Hash.Commit(pick, nonce, myName())
  rd.myOU = { pick = pick, nonce = nonce }
  rd.ou.commits[myName()] = hash  -- record our own commit so our reveal verifies locally
  send(("BCO|%s|%s"):format(rd.id, hash))
  ns.Print("Over/Under bet locked in (hidden until the pull ends).")
  refreshUI()
end

-- place a First Blood bet (a raider name, or "none" for "no deaths")
function B.PlaceFB(pick)
  local rd = rt.round
  if not (rd and rd.state == "OPEN") then ns.Print("No open betting round.") return end
  if rd.myFB then ns.Print("Your First Blood bet is already locked for this round.") return end
  if pick == myName() then ns.Print("You can't bet on your own death.") return end
  if not affordable(rd.stakeFB) then return end
  local nonce = genNonce()
  local hash = ns.Hash.Commit(pick, nonce, myName())
  rd.myFB = { pick = pick, nonce = nonce }
  rd.fb.commits[myName()] = hash  -- record our own commit so our reveal verifies locally
  send(("BCF|%s|%s"):format(rd.id, hash))
  ns.Print("First Blood bet locked in.")
  refreshUI()
end

-- place a Hot Seat bet on your dealt target ("survives"/"dies"; self -> survives only)
function B.PlaceHS(side)
  local rd = rt.round
  if not (rd and rd.hs and rd.state == "OPEN") then ns.Print("No open betting round.") return end
  if rd.myHS then ns.Print("Your Hot Seat bet is already locked for this round.") return end
  local target = ns.Book.DealTarget(rd.hs.seed, rd.hs.targets, myName())
  if not target then return end
  if target == myName() and side ~= "survives" then
    ns.Print("You can only bet on yourself to SURVIVE."); return
  end
  local stk = ns.Book.HotSeatStakes(rd.hs.lines[target] or 0.5, rd.hs.stakeBase)
  local myStake = (stk.favSide == side) and stk.favStake or stk.dogStake
  if not affordable(myStake) then return end
  local nonce = genNonce()
  local hash = ns.Hash.Commit(side, nonce, myName())
  rd.myHS = { pick = side, nonce = nonce }
  rd.hs.round.commits[myName()] = hash  -- record our own commit so our reveal verifies locally
  send(("BCH|%s|%s"):format(rd.id, hash))
  ns.Print(("Hot Seat bet on %s locked in (%s, risk %dg)."):format(target, side, myStake))
  refreshUI()
end

function B.OnCommit(kind, id, sender, hash)
  local rd = rt.round
  if not (rd and rd.id == id) then return end
  local round = (kind == "OU") and rd.ou or rd.fb
  ns.Book.AddCommit(round, sender, hash)
  refreshUI()
end

function B.OnCommitHS(id, sender, hash)
  local rd = rt.round
  if not (rd and rd.id == id and rd.hs) then return end
  ns.Book.AddCommit(rd.hs.round, sender, hash)
  refreshUI()
end

function B.OnRevealHS(id, sender, pick, nonce)
  local rd = rt.round
  if not (rd and rd.id == id and rd.hs) then return end
  ns.Book.AddReveal(rd.hs.round, sender, pick, nonce)
  refreshUI()
end

local function lockRound()
  local rd = rt.round
  if not (rd and rd.state == "OPEN") then return end
  -- Window bounds MUST be epoch time() to match death.time (the combat-log
  -- timestamp windowDeaths filters on). GetTime() is uptime seconds -- a totally
  -- different magnitude -- so it would exclude every death and resolve O/U to 0.
  rd.state = "LOCKED"; rd.lockTime = (time and time()) or 0
  ns.Book.Lock(rd.ou); ns.Book.Lock(rd.fb)
  if rd.hs then ns.Book.Lock(rd.hs.round) end
  refreshUI()
end

local function resolveRound()
  local rd = rt.round
  if not (rd and rd.state == "LOCKED") then return end
  rd.endTime = (time and time()) or 0   -- epoch, to match death.time (see lockRound)
  local window = windowDeaths(rd.lockTime, rd.endTime)
  local counted = 0
  for _, d in ipairs(window) do if d.classification ~= "wipeCascade" then counted = counted + 1 end end
  rd.counted = counted
  rt.history[#rt.history + 1] = counted
  while #rt.history > (cfg().bookLineWindow or 5) do table.remove(rt.history, 1) end

  rd.outcomeOU = ns.Book.ResolveOU(rd.line, window, nil)
  rd.outcomeFB = ns.Book.ResolveFirstBlood(window, nil) or "none"
  ns.Book.Resolve(rd.ou, rd.outcomeOU); ns.Book.Resolve(rd.fb, rd.outcomeFB)
  rd.state = "RESOLVED"

  -- auto-reveal our own bets so others can verify + settle
  if rd.myOU then send(("BRO|%s|%s|%s"):format(rd.id, rd.myOU.pick, rd.myOU.nonce))
    ns.Book.AddReveal(rd.ou, myName(), rd.myOU.pick, rd.myOU.nonce) end
  if rd.myFB then send(("BRF|%s|%s|%s"):format(rd.id, rd.myFB.pick, rd.myFB.nonce))
    ns.Book.AddReveal(rd.fb, myName(), rd.myFB.pick, rd.myFB.nonce) end
  if rd.hs then
    for _, t in ipairs(rd.hs.targets) do
      rd.hs.outcomes[t] = ns.Book.ResolveHotSeat(t, window)
    end
    ns.Book.Resolve(rd.hs.round, "done")
    if rd.myHS then
      send(("BRH|%s|%s|%s"):format(rd.id, rd.myHS.pick, rd.myHS.nonce))
      ns.Book.AddReveal(rd.hs.round, myName(), rd.myHS.pick, rd.myHS.nonce)
    end
  end
  local hsNote = ""
  if rd.hs then
    local n = 0
    for _ in pairs(rd.hs.outcomes) do n = n + 1 end
    if n > 0 then hsNote = (" Hot Seat: %d resolved."):format(n) end
  end
  ns.Print(("Pull over: %d deaths -> %s. First blood: %s.%s"):format(counted, rd.outcomeOU, rd.outcomeFB, hsNote))
  -- Admin-authoritative outcome: the runner broadcasts the resolved outcome so clients
  -- whose local death window diverged (esp. trash pulls) adopt one canonical result.
  -- Additive -- clients still resolve locally; this only overrides before settle.
  if B.CanAdmin() then
    local hsParts = {}
    if rd.hs then
      for _, t in ipairs(rd.hs.targets) do hsParts[#hsParts + 1] = t .. "=" .. tostring(rd.hs.outcomes[t]) end
    end
    send(("BRES|%s|%s|%d|%s|%s"):format(rd.id, tostring(rd.outcomeOU), counted,
      tostring(rd.outcomeFB), table.concat(hsParts, ",")))
  end
  if C_Timer and C_Timer.After then C_Timer.After(6, B.Settle) else B.Settle() end
  refreshUI()
end

-- Adopt an admin-broadcast outcome (override the local resolution) before settlement.
-- Only while RESOLVED-not-yet-SETTLED, so it can't double-append the ledger; if it
-- arrives too late, the local result stands (current behavior). Verified admin only.
function B.OnResolveBroadcast(id, ouOutcome, ouCount, fbOutcome, hsPayload)
  local rd = rt.round
  if not (rd and rd.id == id and rd.state == "RESOLVED") then return end
  rd.outcomeOU = ouOutcome
  rd.counted = tonumber(ouCount) or rd.counted
  rd.outcomeFB = fbOutcome
  if rd.hs and hsPayload and hsPayload ~= "" then
    for entry in hsPayload:gmatch("[^,]+") do
      local t, o = entry:match("^([^=]+)=(.+)$")
      if t and o then rd.hs.outcomes[t] = o end
    end
  end
  refreshUI()
end

function B.OnReveal(kind, id, sender, pick, nonce)
  local rd = rt.round
  if not (rd and rd.id == id) then return end
  local round = (kind == "OU") and rd.ou or rd.fb
  ns.Book.AddReveal(round, sender, pick, nonce)
  refreshUI()
end

-- Record each revealed bettor's win/loss + net into the persistent all-time store.
-- Net is stored in gold (rounded) for the bragging-rights leaderboard; the exact
-- copper deltas live in the session ledger used for settlement. Every client
-- computes the same RoundDeltas, so all stores converge.
local function recordResults(store, reveals, outcome, stakeCopper)
  local deltas = ns.Book.RoundDeltas(reveals, outcome, stakeCopper)
  for player, pick in pairs(reveals) do
    local d = deltas[player] or 0
    local gold = (d >= 0) and math.floor(d / 10000 + 0.5) or -math.floor(-d / 10000 + 0.5)
    ns.DB.RecordBetResult(store, player, pick == outcome, gold)
  end
end

-- compute who-owes-whom from the verified reveals, record all-time results, and
-- append this round to the session ledger that end-of-raid settlement reads.
function B.Settle()
  local rd = rt.round
  if not (rd and rd.state == "RESOLVED") then return end
  rd.settleOU = ns.Book.SettleRound(rd.ou.reveals, rd.outcomeOU, rd.stakeOU)  -- live winners/pot display
  rd.settleFB = ns.Book.SettleRound(rd.fb.reveals, rd.outcomeFB, rd.stakeFB)

  local ouStakeC = (rd.stakeOU or 0) * 10000
  local fbStakeC = (rd.stakeFB or 0) * 10000
  rt.ledger = rt.ledger or {}
  rt.seq = (rt.seq or 0) + 1
  rt.ledger[#rt.ledger + 1] = {
    seq = rt.seq, roundId = rd.id, boss = ns.Tracking and ns.Tracking.currentBoss or nil,
    line = rd.line, lockTime = rd.lockTime, endTime = rd.endTime,
    ouReveals = copyMap(rd.ou.reveals), ouOutcome = rd.outcomeOU, ouStake = ouStakeC, ouCount = rd.counted or 0,
    fbReveals = copyMap(rd.fb.reveals), fbOutcome = rd.outcomeFB, fbStake = fbStakeC,
  }

  local store = activeStore()   -- active (demo-aware) store so the Bet Records board
                                -- shows results in the dev simulator too; identical
                                -- to ns.db.store in real play
  if store then
    recordResults(store, rd.ou.reveals, rd.outcomeOU, ouStakeC)
    recordResults(store, rd.fb.reveals, rd.outcomeFB, fbStakeC)
  end
  if rd.hs then
    local hsOrders = {}
    for player, side in pairs(rd.hs.round.reveals) do
      hsOrders[player] = { target = ns.Book.DealTarget(rd.hs.seed, rd.hs.targets, player), side = side }
    end
    local hsStakeC = (rd.hs.stakeBase or 0) * 10000              -- COPPER base
    rd.hs.result = ns.Book.MatchHotSeat(hsOrders, rd.hs.outcomes, rd.hs.lines, hsStakeC)
    -- live Bet Records: only matched players (unmatched were refunded, no W/L)
    local matched = {}
    for _, pr in ipairs(rd.hs.result.pairs) do matched[pr.winner] = true; matched[pr.loser] = true end
    if store then
      for player in pairs(matched) do
        local c = rd.hs.result.deltas[player] or 0
        local gold = (c >= 0) and math.floor(c / 10000 + 0.5) or -math.floor(-c / 10000 + 0.5)
        ns.DB.RecordBetResult(store, player, c >= 0, gold)
      end
    end
    -- settlement ledger: store the MatchHotSeat INPUTS (copper base) so
    -- SettlementBreakdown recomputes deltas the same way it does for OU/FB
    rt.seq = (rt.seq or 0) + 1
    rt.ledger[#rt.ledger + 1] = {
      seq = rt.seq, roundId = rd.id, boss = ns.Tracking and ns.Tracking.currentBoss or nil,
      hsOrders = hsOrders, hsOutcomes = rd.hs.outcomes, hsLines = rd.hs.lines, hsStakeBase = hsStakeC,
    }
  end
  rd.state = "SETTLED"
  refreshUI()
end

-- Restore the wagering toggle to whatever it was before the first DevSimOpen flipped it
-- on (called from Demo.Clear). No-op if a sim never touched it.
function B.RestoreSimConfig()
  if B._simPrevBookEnabled ~= nil and ns.cfg then
    ns.cfg.bookEnabled = B._simPrevBookEnabled
    B._simPrevBookEnabled = nil
  end
end

-- ===== Dev: solo round simulator (mock data; no group / sync / combat needed) =====

-- Open a full round (OU/FB/HS) with the 25-man mock roster and inject random
-- bets from the 24 NPCs, then pop the Hot Seat window so the dev can bet.
function B.DevSimOpen()
  if not (ns.Demo and ns.Demo.active) then
    if ns.Demo and ns.Demo.Load then ns.Demo.Load() end
  end
  -- the sim needs wagering on; remember the real setting so Demo.Clear can restore it
  -- instead of leaving the dev's wagering toggle flipped on after a sim.
  if ns.cfg then
    if B._simPrevBookEnabled == nil then B._simPrevBookEnabled = ns.cfg.bookEnabled end
    ns.cfg.bookEnabled = true
  end
  B.OpenRound()                      -- builds OU/FB/HS locally; send() is a no-op solo
  local rd = rt.round
  if not rd then ns.Print("Sim: could not open a round.") return end
  -- inject random NPC bets so the dev's bet has opponents to match
  for _, name in ipairs(roster()) do
    if name ~= myName() then
      rd.ou.reveals[name] = (math.random() < 0.5) and "over" or "under"
      if rd.hs then rd.hs.round.reveals[name] = (math.random() < 0.5) and "dies" or "survives" end
    end
  end
  if ns.BookUI and ns.BookUI.ShowHotSeatPopup then ns.BookUI.ShowHotSeatPopup() end
  refreshUI()
  ns.Print("Sim: round open. Place your Hot Seat bet, then click 'Sim: resolve pull'.")
end

-- Lock + simulate a pull (random deaths for ~half the targets) + resolve + settle.
function B.DevSimResolve()
  if not (ns.Demo and ns.Demo.active) then ns.Print("Sim: load mock data first.") return end
  local rd = rt.round
  if not rd then ns.Print("Sim: open a round first.") return end
  lockRound()                        -- LOCKED, lockTime = now (epoch)
  local store, raidId = activeStore()
  local raid = store and raidId and store.raids and store.raids[raidId]
  if raid and rd.hs then
    local t = rd.lockTime
    for _, tgt in ipairs(rd.hs.targets) do
      if math.random() < 0.5 then
        raid.deaths[#raid.deaths + 1] = {
          player = tgt, time = t, classification = "counted",
          ability = "Cleave", sourceName = "Simulator", boss = "Sim", pullId = 99999,
        }
      end
    end
  end
  resolveRound()                     -- endTime = now; resolves from the window; schedules Settle
  refreshUI()
  ns.Print("Sim: pull resolved. Results + Bet Records update shortly.")
end

-- ----- Death Draft -----
function B.OpenDraft()
  if not cfg().bookEnabled then ns.Print("Wagering is off (enable it in Settings).") return end
  if not B.CanAdmin() then ns.Print("Only the raid leader/assist can open the draft.") return end
  local id = tostring((GetTime and math.floor(GetTime() * 1000)) or math.random(1, 1e9))
  send(("BDO|%s|%s"):format(id, tostring(cfg().bookDraftAnte or 0)))
  B.OnDraftOpen(id, cfg().bookDraftAnte or 0)
  ns.Print("Death Draft open -- type /agnb book join to enter.")
end

function B.OnDraftOpen(id, ante)
  rt.draft = { id = id, ante = tonumber(ante) or 0, state = "OPEN",
               commits = {}, secrets = {}, roster = roster() }
  refreshUI()
end

function B.JoinDraft()
  local dr = rt.draft
  if not (dr and dr.state == "OPEN") then ns.Print("No open draft.") return end
  if not affordable(dr.ante) then return end
  dr.mySecret = genNonce()
  dr.commits[myName()] = ns.Hash.SHA256(dr.mySecret)
  send(("BDC|%s|%s"):format(dr.id, ns.Hash.SHA256(dr.mySecret)))
  ns.Print("Entered the Death Draft.")
  refreshUI()
end

function B.OnDraftCommit(id, sender, hash)
  local dr = rt.draft
  if dr and dr.id == id and dr.state == "OPEN" then dr.commits[sender] = hash; refreshUI() end
end

-- admin closes entries; everyone reveals their secret
function B.LockDraft()
  local dr = rt.draft
  if not (dr and dr.state == "OPEN") then return end
  if not B.CanAdmin() then ns.Print("Only the admin can lock the draft.") return end
  dr.state = "REVEAL"
  if dr.mySecret then send(("BDR|%s|%s"):format(dr.id, dr.mySecret)); dr.secrets[myName()] = dr.mySecret end
  ns.Print("Draft entries locked -- revealing and assigning...")
  if C_Timer and C_Timer.After then C_Timer.After(6, B.AssignDraft) end
  refreshUI()
end

function B.OnDraftReveal(id, sender, secret)
  local dr = rt.draft
  if not (dr and dr.id == id) then return end
  -- verify the secret matches the earlier commitment
  if dr.commits[sender] and ns.Hash.SHA256(secret) == dr.commits[sender] then
    dr.secrets[sender] = secret; refreshUI()
  end
end

function B.AssignDraft()
  local dr = rt.draft
  if not dr or dr.state == "DONE" then return end
  dr.assign = ns.Book.DraftAssign(dr.secrets, dr.roster)
  dr.startTime = (time and time()) or 0   -- epoch, to match death.time in windowDeaths
  dr.state = "DRAFTED"
  refreshUI()
end

-- live standings for the current draft (distinct from the pure DraftStandings)
function B.LiveStandings()
  local dr = rt.draft
  if not (dr and dr.assign) then return {} end
  return ns.Book.DraftStandings(dr.assign, windowDeaths(dr.startTime, nil))
end

-- ----- wire receive -----
local function onAddon(_, _, prefix, msg, _, sender)
  if prefix ~= ns.Sync.PREFIX then return end
  local who = sender and sender:match("^[^-]+")
  if who == myName() then return end   -- skip our own echo (we apply locally on send)
  local tag, rest = msg:match("^(%u+)|(.*)$")
  if not tag then return end
  if tag == "BO" then
    local id, line, sOU, sFB = rest:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
    if senderIsAdmin(who) then B.OnOpen(id, line, sOU, sFB) end
  elseif tag == "BOH" then
    local id, seed, sHS, payload = rest:match("^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if senderIsAdmin(who) then B.OnOpenHotSeat(id, seed, sHS, payload) end
  elseif tag == "BRHO" then
    local id, seed, subject, line, stake, openTime = rest:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if senderIsAdmin(who) then B.OnOpenRaidHS(id, seed, subject, tonumber(line), tonumber(stake), tonumber(openTime)) end
  elseif tag == "BRHC" then local id, h = rest:match("^([^|]*)|(.*)$"); B.OnCommitRaidHS(id, who, h)
  elseif tag == "BRHR" then local id, p, n = rest:match("^([^|]*)|([^|]*)|(.*)$"); B.OnRevealRaidHS(id, who, p, n)
  elseif tag == "BRES" then
    local id, ouO, ouC, fbO, hs = rest:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if senderIsAdmin(who) then B.OnResolveBroadcast(id, ouO, ouC, fbO, hs) end
  elseif tag == "BCO" then local id, h = rest:match("^([^|]*)|(.*)$"); B.OnCommit("OU", id, who, h)
  elseif tag == "BCF" then local id, h = rest:match("^([^|]*)|(.*)$"); B.OnCommit("FB", id, who, h)
  elseif tag == "BRO" then local id, p, n = rest:match("^([^|]*)|([^|]*)|(.*)$"); B.OnReveal("OU", id, who, p, n)
  elseif tag == "BRF" then local id, p, n = rest:match("^([^|]*)|([^|]*)|(.*)$"); B.OnReveal("FB", id, who, p, n)
  elseif tag == "BCH" then local id, h = rest:match("^([^|]*)|(.*)$"); B.OnCommitHS(id, who, h)
  elseif tag == "BRH" then local id, p, n = rest:match("^([^|]*)|([^|]*)|(.*)$"); B.OnRevealHS(id, who, p, n)
  elseif tag == "BDO" then local id, a = rest:match("^([^|]*)|(.*)$"); if senderIsAdmin(who) then B.OnDraftOpen(id, a) end
  elseif tag == "BDC" then local id, h = rest:match("^([^|]*)|(.*)$"); B.OnDraftCommit(id, who, h)
  elseif tag == "BDR" then local id, s = rest:match("^([^|]*)|(.*)$"); B.OnDraftReveal(id, who, s)
  elseif tag == "BSET" then
    -- rest = "1|<rhsId>|<rhsOutcome>|<rhsCount>" (the trailing fields may be absent from
    -- an older client; ResolveAndSettleRaidHS ignores a non-over/under outcome).
    local _, _, rhsOut, rhsCnt = rest:match("^([^|]*)|?([^|]*)|?([^|]*)|?([^|]*)$")
    if senderIsAdmin(who) then B.OnCloseBook(rhsOut, rhsCnt) end
  elseif tag == "BIGN" then
    local a, b = rest:match("^([^|]*)|(.*)$")
    if senderIsAdmin(who) then B.OnIgnorePull(tonumber(a) or 0, tonumber(b) or 0) end
  elseif tag == "BPAID" then
    local fr, to, amt = rest:match("^([^|]*)|([^|]*)|(.*)$")
    if ns.Settlement and ns.Settlement.OnPaid then ns.Settlement.OnPaid(fr, to, tonumber(amt) or 0, who) end
  elseif tag == "BNCHK" then
    if ns.Settlement and ns.Settlement.OnChecksum then ns.Settlement.OnChecksum(who, rest) end
  elseif tag == "BADM" then B.OnAdminMsg(rest, who)
  elseif tag == "BCOL" then
    if B.OnCollusionAlert then B.OnCollusionAlert(who, rest) end
  elseif tag == "BCOLR" then
    if B.OnCollusionReport then B.OnCollusionReport(who, rest) end
  end
end

ns.OnInit(function()
  local f = CreateFrame("Frame")
  f:RegisterEvent("CHAT_MSG_ADDON")
  f:RegisterEvent("CHAT_MSG_WHISPER")
  f:RegisterEvent("READY_CHECK")
  f:RegisterEvent("ENCOUNTER_START")
  f:RegisterEvent("ENCOUNTER_END")
  f:RegisterEvent("PLAYER_REGEN_DISABLED")
  f:RegisterEvent("PLAYER_REGEN_ENABLED")
  f:SetScript("OnEvent", ns.Debug.Guard("Book.OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then onAddon(_, event, ...)
    elseif event == "CHAT_MSG_WHISPER" then
      local text, playerName = ...
      B.OnWhisper(text, playerName and playerName:match("^[^-]+") or playerName)
    elseif event == "READY_CHECK" then
      if cfg().bookEnabled and cfg().bookAutoOpenOnReadyCheck and B.CanAdmin() and not rt.round then
        B.OpenRound()
      end
    elseif event == "ENCOUNTER_START" or event == "PLAYER_REGEN_DISABLED" then
      lockRound()
      lockRaidHS()
    elseif event == "ENCOUNTER_END" or event == "PLAYER_REGEN_ENABLED" then
      resolveRound()
    end
  end))
end)
