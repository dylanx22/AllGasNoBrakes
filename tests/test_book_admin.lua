local B = __AGNB_NS.Book

-- Pure resolver: appointer authority is required to change the designation.
T.eq(B.ResolveAdminMsg(nil, "set|Bob", true), "Bob", "appointer sets admin")
T.eq(B.ResolveAdminMsg(nil, "set|Bob", false), nil, "non-appointer cannot set")
T.eq(B.ResolveAdminMsg("Bob", "clear", true), nil, "appointer clears admin")
T.eq(B.ResolveAdminMsg("Bob", "set|Carol", true), "Carol", "reassign replaces")
T.eq(B.ResolveAdminMsg("Bob", "set|Eve", false), "Bob", "delegate-forwarded appoint rejected")
T.eq(B.ResolveAdminMsg("Bob", "garbage", true), "Bob", "unknown op leaves designation")

-- Delegate inclusion: a designated name is admin (and a valid action sender)
-- without holding WoW rank; appointer-status stays false for them.
do
  local savedDb, savedName, savedDemo = __AGNB_NS.db, __AGNB_NS.MyName, (__AGNB_NS.Demo and __AGNB_NS.Demo.active)
  if __AGNB_NS.Demo then __AGNB_NS.Demo.active = false end
  __AGNB_NS.db = { designatedAdmin = "Bob" }
  __AGNB_NS.MyName = "Bob"
  T.ok(B.CanAdmin(), "delegate has CanAdmin")
  T.ok(B.senderIsAdmin("Bob"), "delegate accepted as action sender")
  T.ok(not B.senderIsAppointer("Bob"), "delegate is NOT an appointer")
  __AGNB_NS.MyName = "Carol"
  T.ok(not B.CanAdmin(), "non-delegate non-leader lacks CanAdmin")
  __AGNB_NS.db, __AGNB_NS.MyName = savedDb, savedName
  if __AGNB_NS.Demo then __AGNB_NS.Demo.active = savedDemo end
end

-- OnOpen guard: a live round is never clobbered by a second open. Re-applying the same
-- id is an idempotent no-op (keeps pending commits); a different id while a round is in
-- progress is rejected; a settled round may be replaced.
do
  local rt = __AGNB_NS.Book.rt
  local saved = rt.round
  rt.round = nil
  B.OnOpen("r1", 2.5, 5, 5)
  T.eq(rt.round and rt.round.id, "r1", "first open creates the round")
  rt.round.ou.commits["Bob"] = "hash"           -- a pending bet on the live round
  B.OnOpen("r1", 9.5, 9, 9)                      -- same id again
  T.eq(rt.round.line, 2.5, "same-id re-open is a no-op (line unchanged)")
  T.eq(rt.round.ou.commits["Bob"], "hash", "same-id re-open keeps pending commits")
  B.OnOpen("r2", 1.5, 1, 1)                      -- a different id while r1 is live
  T.eq(rt.round.id, "r1", "a different id cannot clobber a live round")
  rt.round.state = "SETTLED"
  B.OnOpen("r3", 3.5, 7, 7)                      -- settled rounds may be replaced
  T.eq(rt.round.id, "r3", "a settled round is replaced by a new open")
  rt.round = saved
end

-- A Hot Seat open (BOH) that arrives before the round open (BO) is buffered and applied
-- when BO lands -- addon messages can reorder under throttle.
do
  local rt = __AGNB_NS.Book.rt
  local saved, savedPending = rt.round, rt._pendingHS
  rt.round, rt._pendingHS = nil, nil
  __AGNB_NS.Book.OnOpenHotSeat("rx", "seedx", "5", "Goat=0.50")   -- arrives first, no round yet
  T.eq(rt.round, nil, "BOH before BO does not create a round")
  T.ok(rt._pendingHS ~= nil, "BOH is buffered")
  __AGNB_NS.Book.OnOpen("rx", 2.5, 5, 5)                          -- now the round open arrives
  T.ok(rt.round and rt.round.hs ~= nil, "buffered Hot Seat is applied when BO lands")
  T.eq(rt.round.hs.targets[1], "Goat", "buffered targets applied")
  T.eq(rt._pendingHS, nil, "pending buffer cleared after applying")
  rt.round, rt._pendingHS = saved, savedPending
end

-- One bet per round: PlaceOU locks the bet (records the local commit) and a second
-- click does not change it.
do
  local B, ns = __AGNB_NS.Book, __AGNB_NS
  local rt = B.rt
  local saved, savedName, savedGM = rt.round, ns.MyName, _G.GetMoney
  _G.GetMoney = function() return 100 * 10000 end   -- 100g, so the stake is affordable
  ns.MyName = "Me"
  rt.round = { id = "r", state = "OPEN", stakeOU = 5, stakeFB = 5,
               ou = B.NewRound(nil, nil, "OU"), fb = B.NewRound(nil, nil, "FB") }
  B.PlaceOU("over")
  T.ok(rt.round.myOU ~= nil, "first OU bet registers")
  T.eq(rt.round.myOU.pick, "over", "bet is over")
  T.ok(rt.round.ou.commits["Me"] ~= nil, "own commit recorded locally (so reveal verifies)")
  local firstNonce = rt.round.myOU.nonce
  B.PlaceOU("under")   -- attempt to change after already betting
  T.eq(rt.round.myOU.pick, "over", "second OU bet is rejected -- one bet per round")
  T.eq(rt.round.myOU.nonce, firstNonce, "the locked bet is unchanged")
  rt.round, ns.MyName, _G.GetMoney = saved, savedName, savedGM
end

-- RestoreSimConfig puts the wagering toggle back to its pre-sim value (the dev sim
-- forces it on; clearing mock data must not leave it flipped).
do
  local ns = __AGNB_NS
  local savedCfg, savedPrev = ns.cfg, ns.Book._simPrevBookEnabled
  ns.cfg = { bookEnabled = false }
  ns.Book._simPrevBookEnabled = false   -- as if DevSimOpen captured "off" then forced on
  ns.cfg.bookEnabled = true
  ns.Book.RestoreSimConfig()
  T.eq(ns.cfg.bookEnabled, false, "wagering restored to its pre-sim value")
  T.eq(ns.Book._simPrevBookEnabled, nil, "saved value cleared after restore")
  ns.cfg, ns.Book._simPrevBookEnabled = savedCfg, savedPrev
end

-- Raid Hot Seat open: builds rt.raidHS; a second open is rejected once it has LOCKED.
do
  local rt = __AGNB_NS.Book.rt
  local savedRHS = rt.raidHS
  rt.raidHS = nil
  __AGNB_NS.Book.OnOpenRaidHS("rh1", "seed1", "Goat", 3.5, 5, 1000)
  T.eq(rt.raidHS and rt.raidHS.subject, "Goat", "open builds the raid HS")
  T.eq(rt.raidHS.line, 3.5, "line carried")
  T.eq(rt.raidHS.state, "OPEN", "opens OPEN")
  rt.raidHS.state = "LOCKED"
  __AGNB_NS.Book.OnOpenRaidHS("rh2", "seed2", "Other", 4.5, 9, 2000)
  T.eq(rt.raidHS.subject, "Goat", "a locked raid HS is not clobbered by a new open")
  rt.raidHS = savedRHS
end

-- Raid Hot Seat reveal: a verified reveal lands; a reveal not matching the commit is rejected.
do
  local B = __AGNB_NS.Book
  local rt = B.rt
  local savedRHS = rt.raidHS
  rt.raidHS = { id = "rh1", subject = "Goat", line = 3.5, stake = 5, state = "OPEN",
                openTime = 0, round = B.NewRound(nil, nil, "RHS") }
  local nonce = "n1"
  rt.raidHS.round.commits["Bob"] = __AGNB_NS.Hash.Commit("over", nonce, "Bob")
  B.Lock(rt.raidHS.round)   -- reveals are only accepted after lock (no peeking before)
  B.OnRevealRaidHS("rh1", "Bob", "over", nonce)
  T.eq(rt.raidHS.round.reveals["Bob"], "over", "verified reveal recorded")
  B.OnRevealRaidHS("rh1", "Bob", "under", nonce)   -- wrong pick for the commit
  T.eq(rt.raidHS.round.reveals["Bob"], "over", "a reveal not matching the commit is rejected")
  rt.raidHS = savedRHS
end

-- Raid Hot Seat resolve+settle: counts the subject's counted deaths in the window,
-- resolves O/U, appends a pari-mutuel ledger entry, records bet results.
do
  local B, ns = __AGNB_NS.Book, __AGNB_NS
  local rt = B.rt
  local savedRHS, savedLedger, savedSeq = rt.raidHS, rt.ledger, rt.seq
  ns.Demo = ns.Demo or {}
  local savedDemo, savedRaidId, savedStore = ns.Demo.active, ns.Demo.raidId, ns.Demo.store
  ns.Demo.active = true; ns.Demo.raidId = "__t__"
  ns.Demo.store = ns.DB.NewStore()
  -- Goat dies twice (counted) in-window; a cascade and an out-of-window death don't count.
  for _, d in ipairs({
    { player = "Goat", time = 5,  classification = "counted" },
    { player = "Goat", time = 6,  classification = "counted" },
    { player = "Goat", time = 7,  classification = "wipeCascade" },
    { player = "Goat", time = 99, classification = "counted" }, -- after closeTime
  }) do ns.DB.RecordDeath(ns.Demo.store, "__t__", d) end
  rt.ledger, rt.seq = {}, 0
  rt.raidHS = { id = "rh1", subject = "Goat", line = 1.5, stake = 5, state = "LOCKED",
                openTime = 0, closeTime = 10, round = B.NewRound(nil, nil, "RHS") }
  rt.raidHS.round.reveals = { Ann = "over", Bob = "under" }
  B.ResolveAndSettleRaidHS(10)
  T.eq(rt.raidHS.count, 2, "two counted deaths in [0,10]")
  T.eq(rt.raidHS.outcome, "over", "2 deaths over the 1.5 line")
  local e = rt.ledger[#rt.ledger]
  T.eq(e.raidHS, true, "ledger entry flagged raidHS")
  T.eq(e.ouOutcome, "over", "ledger carries the outcome")
  T.eq(e.ouStake, 50000, "stake stored in copper")
  local bd = B.SettlementBreakdown(rt.ledger)
  T.eq(bd.Ann.net, 50000, "over backer won 5g")
  T.eq(bd.Ann.net + bd.Bob.net, 0, "zero-sum")
  rt.raidHS, rt.ledger, rt.seq = savedRHS, savedLedger, savedSeq
  ns.Demo.active, ns.Demo.raidId, ns.Demo.store = savedDemo, savedRaidId, savedStore
end

-- OnResolveBroadcast: adopts an admin outcome while RESOLVED; ignored once SETTLED or
-- for a different id (additive override, never double-settles).
do
  local rt = __AGNB_NS.Book.rt
  local saved = rt.round
  rt.round = { id = "r1", state = "RESOLVED", outcomeOU = "under", counted = 1,
               outcomeFB = "none", ou = B.NewRound(nil, nil, "OU"), fb = B.NewRound(nil, nil, "FB") }
  B.OnResolveBroadcast("r1", "over", 4, "Carol", "")
  T.eq(rt.round.outcomeOU, "over", "adopts admin O/U outcome")
  T.eq(rt.round.counted, 4, "adopts admin count")
  T.eq(rt.round.outcomeFB, "Carol", "adopts admin first blood")
  rt.round.state = "SETTLED"
  B.OnResolveBroadcast("r1", "under", 0, "none", "")
  T.eq(rt.round.outcomeOU, "over", "ignored once SETTLED (no late override)")
  rt.round.state = "RESOLVED"
  B.OnResolveBroadcast("other", "under", 0, "none", "")
  T.eq(rt.round.outcomeOU, "over", "ignored for a different round id")
  rt.round = saved
end

-- ResolveAndSettleRaidHS adopts an admin override instead of recomputing; a non-over/under
-- override falls back to the local count.
do
  local B, ns = __AGNB_NS.Book, __AGNB_NS
  local rt = B.rt
  local savedRHS, savedLedger, savedSeq = rt.raidHS, rt.ledger, rt.seq
  ns.Demo = ns.Demo or {}
  local sd, sr, ss = ns.Demo.active, ns.Demo.raidId, ns.Demo.store
  ns.Demo.active = true; ns.Demo.raidId = "__t2__"; ns.Demo.store = ns.DB.NewStore()  -- no deaths
  rt.ledger, rt.seq = {}, 0
  rt.raidHS = { id = "rh9", subject = "Goat", line = 1.5, stake = 5, state = "LOCKED",
                openTime = 0, closeTime = 10, round = B.NewRound(nil, nil, "RHS") }
  rt.raidHS.round.reveals = { Ann = "over", Bob = "under" }
  B.ResolveAndSettleRaidHS(10, "over", 4)   -- admin override: over with 4 deaths
  T.eq(rt.raidHS.outcome, "over", "adopts the admin override outcome (window has 0 deaths)")
  T.eq(rt.raidHS.count, 4, "adopts the admin override count")
  -- fallback: garbage override -> local compute (0 deaths -> under)
  rt.raidHS = { id = "rh10", subject = "Goat", line = 1.5, stake = 5, state = "LOCKED",
                openTime = 0, closeTime = 10, round = B.NewRound(nil, nil, "RHS") }
  rt.raidHS.round.reveals = { Ann = "over" }
  B.ResolveAndSettleRaidHS(10, "", nil)
  T.eq(rt.raidHS.outcome, "under", "garbage override falls back to local count (0 -> under)")
  ns.Demo.active, ns.Demo.raidId, ns.Demo.store = sd, sr, ss
  rt.raidHS, rt.ledger, rt.seq = savedRHS, savedLedger, savedSeq
end
