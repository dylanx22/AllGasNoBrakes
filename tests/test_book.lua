local B = __AGNB_NS.Book
local Hash = __AGNB_NS.Hash

-- ----- round state machine + commit/reveal -----
local r = B.NewRound("raid-1", 3, "OU", 2.5)
T.eq(r.state, "OPEN", "new round is open")
T.ok(B.AddCommit(r, "Grug", "hashG"), "commit accepted while open")
T.ok(not B.AddCommit(r, "Grug", "other"), "no changing a locked-in bet")
B.Lock(r)
T.eq(r.state, "LOCKED", "locked")
T.ok(not B.AddCommit(r, "Late", "hashL"), "commit rejected after lock")

-- reveal must match the committed (pick, nonce, player)
local r2 = B.NewRound("raid-1", 4, "OU", 2.5)
B.AddCommit(r2, "Grug", Hash.Commit("over", "nG", "Grug"))
B.Lock(r2)
T.ok(not B.AddReveal(r2, "Nobody", "over", "x"), "reveal needs a prior commit")
T.ok(not B.AddReveal(r2, "Grug", "under", "nG"), "tampered pick rejected")
T.ok(not B.AddReveal(r2, "Grug", "over", "WRONG"), "tampered nonce rejected")
T.ok(B.AddReveal(r2, "Grug", "over", "nG"), "valid reveal accepted")
T.eq(r2.reveals["Grug"], "over", "reveal recorded")

-- ----- Over/Under -----
T.eq(B.AutoLine({}, 2.5), 2.5, "fallback when no history")
T.eq(B.AutoLine(nil), 0.5, "default fallback is the lowest line 0.5")
T.eq(B.AutoLine({ 1, 2, 3, 8 }, 2.5), 2.5, "median 2.5 stays 2.5")
T.eq(B.AutoLine({ 4, 4, 4 }), 4.5, "median 4 -> 4.5 (push-proof)")
T.eq(B.AutoLine({ 2, 5 }), 3.5, "median 3.5")

local deaths = {
  { player = "A", time = 1, pullId = 3, classification = "counted" },
  { player = "B", time = 2, pullId = 3, classification = "counted" },
  { player = "C", time = 3, pullId = 3, classification = "wipeCascade" },
  { player = "Z", time = 9, pullId = 9, classification = "counted" },
}
T.eq(B.ResolveOU(2.5, deaths, 3), "under", "2 counted < 2.5")
T.eq(B.ResolveOU(1.5, deaths, 3), "over", "2 counted > 1.5")
T.eq(B.ResolveOU(0.5, deaths, 7), "under", "no deaths in pull 7 -> under")
-- nil pullId: list is already the pull's window (glue path)
local window = { deaths[1], deaths[2], deaths[3] }   -- 2 counted + 1 cascade
T.eq(B.ResolveOU(1.5, window, nil), "over", "window list, pullId nil -> count all (2)")
T.eq(B.ResolveFirstBlood(window, nil), "A", "window list first blood by time")

-- ----- First Blood -----
local fb = {
  { player = "A", time = 5, pullId = 2 }, { player = "B", time = 3, pullId = 2 },
  { player = "C", time = 3, pullId = 2 }, { player = "Z", time = 1, pullId = 9 },
}
T.eq(B.ResolveFirstBlood(fb, 2), "B", "earliest time, name tiebreak B<C")
T.eq(B.ResolveFirstBlood(fb, 7), nil, "no deaths this pull -> nil")
local cand = B.FirstBloodCandidates({ "A", "B", "C" }, "B")
T.eq(#cand, 2, "self excluded from candidates")
T.ok(cand[1] == "A" and cand[2] == "C", "candidates keep order minus self")

-- ----- settlement -----
local s = B.SettleRound({ A = "over", B = "over", C = "under", D = "under" }, "over", 5)
T.eq(s.pot, 20, "pot = 4 players * 5g")
T.eq(#s.winners, 2, "two winners")
T.eq(s.owes["C"].amount, 5, "loser owes their stake")
T.eq(s.owes["A"], nil, "winner owes nothing")
local allWin = B.SettleRound({ A = "over", B = "over" }, "over", 5)
T.eq(next(allWin.owes), nil, "all on the winning side -> nobody owes")

-- ----- stake validation -----
T.ok((B.ValidateStake(10, 100, 50)), "10g of 100g under a 50% cap is fine")
T.ok(not (B.ValidateStake(0, 100, 50)), "zero rejected")
T.ok(not (B.ValidateStake(-5, 100, 50)), "negative rejected")
T.ok(not (B.ValidateStake(200, 100, 50)), "more than your gold rejected")
T.ok(not (B.ValidateStake(60, 100, 50)), "over the 50% bankroll cap rejected")
T.ok((B.ValidateStake(60, 100)), "no cap -> 60g of 100g allowed")

-- ----- draft: deterministic, distinct, self-excluded, non-revealers dropped -----
local roster = { "A", "B", "C", "D", "E" }
local a1 = B.DraftAssign({ P1 = "x", P2 = "y" }, roster)
local a2 = B.DraftAssign({ P2 = "y", P1 = "x" }, roster)   -- different receipt order
T.eq(a1.P1, a2.P1, "assignment is seed-canonical (P1)")
T.eq(a1.P2, a2.P2, "assignment is seed-canonical (P2)")
T.ok(a1.P1 ~= a1.P2, "participants get distinct raiders")
local a3 = B.DraftAssign({ P1 = "x", P2 = false }, roster)
T.eq(a3.P2, nil, "non-revealer excluded")

-- self-exclusion: with participants who are also in the roster, nobody draws self
local selfRoster = { "A", "B", "C", "D" }
local sa = B.DraftAssign({ A = "1", B = "2", C = "3", D = "4" }, selfRoster)
for _, p in ipairs(selfRoster) do T.ok(sa[p] ~= p, p .. " is not assigned themselves") end

-- fairness sanity: over many seeds, assignments vary
local seen = {}
for i = 1, 20 do
  local x = B.DraftAssign({ P1 = "s" .. i }, roster)
  seen[x.P1] = true
end
local distinct = 0; for _ in pairs(seen) do distinct = distinct + 1 end
T.ok(distinct >= 2, "draft assignment varies across seeds")

-- ----- draft standings -----
local st = B.DraftStandings({ P1 = "A", P2 = "B" }, {
  { player = "A", classification = "counted" }, { player = "A", classification = "counted" },
  { player = "B", classification = "wipeCascade" },
})
T.eq(st[1].player, "P1", "P1's raider A leads with 2 counted")
T.eq(st[1].deaths, 2, "counted deaths only")
T.eq(st[2].deaths, 0, "wipe-cascade doesn't score")

-- RoundDeltas: even pari-mutuel split in copper, deterministic remainder, sums to 0.
do
  -- 3 losers fund 2 winners: pot 15, base 7, remainder 1 -> first winner (by name) +1.
  local d = B.RoundDeltas({ Anna="over", Bob="over", Cara="under", Dan="under", Eve="under" }, "over", 5)
  T.eq(d.Cara, -5, "loser pays stake"); T.eq(d.Dan, -5, "loser pays stake"); T.eq(d.Eve, -5, "loser pays stake")
  T.eq(d.Anna, 8, "first winner by name gets remainder copper")
  T.eq(d.Bob, 7, "second winner gets base share")
  local sum = d.Anna + d.Bob + d.Cara + d.Dan + d.Eve
  T.eq(sum, 0, "round deltas sum to zero")
end
do
  -- nobody won (outcome nobody picked) -> all refunded to 0
  local d = B.RoundDeltas({ Anna="over", Bob="over" }, "under", 5)
  T.eq(d.Anna, 0, "no winners -> refund"); T.eq(d.Bob, 0, "no winners -> refund")
end
do
  -- nobody lost (everyone won) -> no pot, all 0
  local d = B.RoundDeltas({ Anna="over", Bob="over" }, "over", 5)
  T.eq(d.Anna, 0, "no losers -> no pot"); T.eq(d.Bob, 0, "no losers -> no pot")
end
do
  -- zero stake -> all zero
  local d = B.RoundDeltas({ Anna="over", Bob="under" }, "over", 0)
  T.eq(d.Anna, 0, "zero stake delta"); T.eq(d.Bob, 0, "zero stake delta")
end

-- RecentPulls: cluster deaths into pulls by TIME GAP (not pullId), most-recent first,
-- counted (non-cascade) count, with epoch start/end bounds for cross-client windowing.
do
  local deaths = {
    -- pull 1 @ ~100 (one counted + one cascade); pull 2 @ ~400 (gap >> 90s -> new pull).
    -- pullIds are intentionally mismatched/foreign to prove they aren't used for grouping.
    { player = "A", time = 100, pullId = 9, boss = "Gruul", classification = "counted" },
    { player = "B", time = 104, pullId = 3, boss = "Gruul", classification = "wipeCascade" },
    { player = "C", time = 400, pullId = 1, boss = "Mag",   classification = "counted" },
    { player = "D", time = 410, pullId = 7, boss = "Mag",   classification = "counted" },
  }
  local pulls = B.RecentPulls(deaths)
  T.eq(#pulls, 2, "two pulls split by the time gap, regardless of pullId")
  T.eq(pulls[1].startTime, 400, "most recent pull first (start 400)")
  T.eq(pulls[1].count, 2, "counts non-cascade deaths")
  T.eq(pulls[1].endTime, 410, "latest death time in the pull")
  T.eq(pulls[2].count, 1, "older pull's cascade death excluded from count")
  -- deaths within the gap window stay one pull even with different pullIds
  local same = B.RecentPulls({
    { player = "A", time = 100, pullId = 1, classification = "counted" },
    { player = "B", time = 150, pullId = 2, classification = "counted" }, -- 50s gap < 90
  })
  T.eq(#same, 1, "deaths within the gap are one pull even across pullIds")
  T.eq(same[1].count, 2, "both counted in the single pull")
end

-- SubjectRaidCounts: per-raid counted-death counts for one player, only for raids
-- they were present in (had any death record), sorted by raid key. Feeds AutoLine.
do
  local store = { raids = {
    r2 = { deaths = {
      { player = "Goat", time = 1, classification = "counted" },
      { player = "Goat", time = 2, classification = "wipeCascade" }, -- excluded from count
      { player = "Other", time = 3, classification = "counted" },
    } },
    r1 = { deaths = {
      { player = "Goat", time = 1, classification = "counted" },
      { player = "Goat", time = 2, classification = "counted" },
    } },
    r3 = { deaths = {  -- Goat absent: this raid is not in Goat's history
      { player = "Other", time = 1, classification = "counted" },
    } },
  } }
  local c = B.SubjectRaidCounts(store, "Goat")
  T.eq(#c, 2, "only raids Goat was present in")
  T.eq(c[1], 2, "r1 (sorted first): 2 counted deaths")
  T.eq(c[2], 1, "r2: 1 counted (cascade excluded)")
  T.eq(#B.SubjectRaidCounts(store, "Nobody"), 0, "absent player -> empty history")
  T.eq(#B.SubjectRaidCounts({ raids = {} }, "Goat"), 0, "no raids -> empty")
end
