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
  local out = {}
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
  for i = 1, n do
    local nm = UnitName and UnitName(prefix .. i)
    if nm then out[#out + 1] = nm end
  end
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
  local snippet = (text or ""):sub(1, 120)
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
function B.CloseBook()
  if not B.CanAdmin() then ns.Print("Only the raid leader/assist can close the book.") return end
  send("BSET|1")
  B.OnCloseBook()
end

function B.OnCloseBook()
  rt.closed = true
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
end

function B.OnOpen(id, line, stakeOU, stakeFB)
  rt.round = {
    id = id, line = tonumber(line) or 0.5,
    stakeOU = tonumber(stakeOU) or 0, stakeFB = tonumber(stakeFB) or 0,
    ou = ns.Book.NewRound(nil, nil, "OU", tonumber(line) or 0.5),
    fb = ns.Book.NewRound(nil, nil, "FB"),
    state = "OPEN",
  }
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
  if not affordable(rd.stakeOU) then return end
  local nonce = genNonce()
  rd.myOU = { pick = pick, nonce = nonce }
  rd.ou.commits[myName()] = nil  -- allow local re-pick before broadcast
  send(("BCO|%s|%s"):format(rd.id, ns.Hash.Commit(pick, nonce, myName())))
  ns.Print("Over/Under bet locked in (hidden until the pull ends).")
  refreshUI()
end

-- place a First Blood bet (a raider name, or "none" for "no deaths")
function B.PlaceFB(pick)
  local rd = rt.round
  if not (rd and rd.state == "OPEN") then ns.Print("No open betting round.") return end
  if pick == myName() then ns.Print("You can't bet on your own death.") return end
  if not affordable(rd.stakeFB) then return end
  local nonce = genNonce()
  rd.myFB = { pick = pick, nonce = nonce }
  send(("BCF|%s|%s"):format(rd.id, ns.Hash.Commit(pick, nonce, myName())))
  ns.Print("First Blood bet locked in.")
  refreshUI()
end

function B.OnCommit(kind, id, sender, hash)
  local rd = rt.round
  if not (rd and rd.id == id) then return end
  local round = (kind == "OU") and rd.ou or rd.fb
  ns.Book.AddCommit(round, sender, hash)
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
  ns.Print(("Pull over: %d deaths -> %s. First blood: %s."):format(counted, rd.outcomeOU, rd.outcomeFB))
  if C_Timer and C_Timer.After then C_Timer.After(6, B.Settle) else B.Settle() end
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

  local store = ns.db and ns.db.store
  if store then
    recordResults(store, rd.ou.reveals, rd.outcomeOU, ouStakeC)
    recordResults(store, rd.fb.reveals, rd.outcomeFB, fbStakeC)
  end
  rd.state = "SETTLED"
  refreshUI()
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
  elseif tag == "BCO" then local id, h = rest:match("^([^|]*)|(.*)$"); B.OnCommit("OU", id, who, h)
  elseif tag == "BCF" then local id, h = rest:match("^([^|]*)|(.*)$"); B.OnCommit("FB", id, who, h)
  elseif tag == "BRO" then local id, p, n = rest:match("^([^|]*)|([^|]*)|(.*)$"); B.OnReveal("OU", id, who, p, n)
  elseif tag == "BRF" then local id, p, n = rest:match("^([^|]*)|([^|]*)|(.*)$"); B.OnReveal("FB", id, who, p, n)
  elseif tag == "BDO" then local id, a = rest:match("^([^|]*)|(.*)$"); if senderIsAdmin(who) then B.OnDraftOpen(id, a) end
  elseif tag == "BDC" then local id, h = rest:match("^([^|]*)|(.*)$"); B.OnDraftCommit(id, who, h)
  elseif tag == "BDR" then local id, s = rest:match("^([^|]*)|(.*)$"); B.OnDraftReveal(id, who, s)
  elseif tag == "BSET" then
    if senderIsAdmin(who) then B.OnCloseBook() end
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
    elseif event == "ENCOUNTER_END" or event == "PLAYER_REGEN_ENABLED" then
      resolveRound()
    end
  end))
end)
