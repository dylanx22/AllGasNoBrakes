local B = __AGNB_NS.Book

-- ----- TargetCount: ~1 target per 6 raiders, clamped [2,5] -----
T.eq(B.TargetCount(1), 2, "tiny raid still floors at 2 targets")
T.eq(B.TargetCount(6), 2, "6 raiders -> round(1) = 1 -> floored to 2")
T.eq(B.TargetCount(15), 3, "15 raiders -> round(2.5)=3")
T.eq(B.TargetCount(25), 4, "25 raiders -> round(4.17)=4")
T.eq(B.TargetCount(40), 5, "40 raiders -> round(6.7)=7 -> capped at 5")

-- ----- SurvivalLine: relative to the raid average, clamped [0.10,0.80] -----
do
  local roster = { "Feeder", "Avg", "Clean" }
  local counts = { Feeder = 6, Avg = 3, Clean = 0 }
  -- avg = 3; Avg sits at the mean -> ~0.5
  T.eq(B.SurvivalLine(counts, roster, "Avg"), 0.5, "average player is pick'em")
  -- Feeder = 2x mean -> 0.5*2 = 1.0 -> clamped to 0.80
  T.eq(B.SurvivalLine(counts, roster, "Feeder"), 0.8, "heavy feeder clamps to 0.80")
  -- Clean = 0 -> 0 -> clamped up to 0.10
  T.eq(B.SurvivalLine(counts, roster, "Clean"), 0.1, "clean player clamps to 0.10")
  -- unknown player (not in counts) -> 0 -> 0.10
  T.eq(B.SurvivalLine(counts, roster, "Stranger"), 0.1, "no record -> survivor floor")
end
do
  -- no death data at all -> pick'em
  local roster = { "A", "B" }
  T.eq(B.SurvivalLine({}, roster, "A"), 0.5, "no raid deaths -> 0.50 pick'em")
  T.eq(B.SurvivalLine(nil, roster, "A"), 0.5, "nil counts -> 0.50 pick'em")
end

-- ----- OddsFromProb: American odds, rounded to nearest 5 -----
T.eq(B.OddsFromProb(0.5), "EVEN", "pick'em is EVEN")
T.eq(B.OddsFromProb(0.75), "-300", "75% favorite -> -300")
T.eq(B.OddsFromProb(0.25), "+300", "25% underdog -> +300")
T.eq(B.OddsFromProb(0.8), "-400", "80% -> -400")
T.eq(B.OddsFromProb(0.1), "+900", "10% -> +900")

-- ----- RollTargets: deterministic, distinct, seed-stable -----
do
  local roster = { "A", "B", "C", "D", "E" }
  local t1 = B.RollTargets("seed-x", roster, 3)
  local t2 = B.RollTargets("seed-x", { "E", "D", "C", "B", "A" }, 3) -- different order
  T.eq(#t1, 3, "rolls n targets")
  T.eq(t1[1], t2[1], "seed-stable regardless of roster order (1)")
  T.eq(t1[2], t2[2], "seed-stable (2)")
  T.eq(t1[3], t2[3], "seed-stable (3)")
  -- distinct
  T.ok(t1[1] ~= t1[2] and t1[2] ~= t1[3] and t1[1] ~= t1[3], "targets are distinct")
  -- different seed -> (usually) different slate
  local seen = {}
  for i = 1, 20 do seen[B.RollTargets("s" .. i, roster, 1)[1]] = true end
  local distinct = 0; for _ in pairs(seen) do distinct = distinct + 1 end
  T.ok(distinct >= 2, "varies across seeds")
  -- n larger than roster -> capped to roster size
  T.eq(#B.RollTargets("s", { "A", "B" }, 5), 2, "n capped to roster size")
end

-- ----- DealTarget: deterministic per (seed, player), self-deal allowed -----
do
  local targets = { "X", "Y", "Z" }
  local d1 = B.DealTarget("seed-q", targets, "Grug")
  local d2 = B.DealTarget("seed-q", targets, "Grug")
  T.eq(d1, d2, "same seed+player -> same deal")
  T.ok(d1 == "X" or d1 == "Y" or d1 == "Z", "deal is one of the targets")
  -- different players spread across targets (probabilistically)
  local seen = {}
  for i = 1, 30 do seen[B.DealTarget("seed-q", targets, "P" .. i)] = true end
  local distinct = 0; for _ in pairs(seen) do distinct = distinct + 1 end
  T.ok(distinct >= 2, "different players land on different targets")
  -- self-deal is possible and not special-cased here
  T.ok(B.DealTarget("s", { "Grug" }, "Grug") == "Grug", "single target deals to self")
end

-- ----- ResolveHotSeat: literal survival (any death = dies, cascade included) -----
do
  local window = {
    { player = "A", time = 1, classification = "counted" },
    { player = "B", time = 2, classification = "wipeCascade" },
  }
  T.eq(B.ResolveHotSeat("A", window), "dies", "counted death -> dies")
  T.eq(B.ResolveHotSeat("B", window), "dies", "cascade death still counts as dies")
  T.eq(B.ResolveHotSeat("C", window), "survives", "no death -> survives")
  T.eq(B.ResolveHotSeat("A", {}), "survives", "empty window -> survives")
end

-- ----- HotSeatStakes: odds set the stake handicap -----
do
  local s = B.HotSeatStakes(0.75, 10)   -- dies is 75% favorite
  T.eq(s.favSide, "dies", "dies favored at 0.75")
  T.eq(s.dogStake, 10, "underdog stakes the base")
  T.eq(s.favStake, 30, "favorite stakes base * (.75/.25) = 30")
  local s2 = B.HotSeatStakes(0.25, 10)  -- survives is favorite
  T.eq(s2.favSide, "survives", "survives favored at 0.25")
  T.eq(s2.favStake, 30, "favorite stakes 30 at 0.25 too")
  local e = B.HotSeatStakes(0.5, 10)
  T.eq(e.favSide, "even", "0.5 is even")
  T.eq(e.favStake, 10, "even -> both base"); T.eq(e.dogStake, 10, "even -> both base")
  local cap = B.HotSeatStakes(0.8, 10)  -- clamp ceiling
  T.eq(cap.favStake, 40, "0.80 caps favorite at 4x base")
end

-- ----- MatchHotSeat: head-to-head pairs, surplus unmatched, sum-zero -----
do
  -- One target "Carol", line 0.75 (dies favored: fav stakes 30, dog 10).
  -- Bettors: Ann/Bob on "dies" (favorite), Cy on "survives" (underdog).
  local orders = {
    Ann = { target = "Carol", side = "dies" },
    Bob = { target = "Carol", side = "dies" },
    Cy  = { target = "Carol", side = "survives" },
  }
  local r = B.MatchHotSeat(orders, { Carol = "survives" }, { Carol = 0.75 }, 10)
  -- 1 pair forms (min(2 dies,1 survives)); Ann (first dies by name) matches Cy.
  -- Outcome survives -> Cy (underdog) wins +favStake(30); Ann (favorite) -30.
  T.eq(r.deltas.Cy, 30, "underdog wins the favorite's 30g stake")
  T.eq(r.deltas.Ann, -30, "matched favorite loses 30g")
  T.eq(r.deltas.Bob, 0, "surplus dies-bettor is unmatched -> 0")
  T.eq(r.deltas.Ann + r.deltas.Bob + r.deltas.Cy, 0, "deltas sum to zero")
  T.eq(#r.unmatched, 1, "one unmatched"); T.eq(r.unmatched[1].player, "Bob", "Bob unmatched")
  T.eq(#r.pairs, 1, "one matched pair"); T.eq(r.pairs[1].winner, "Cy", "Cy won the pair")
end
do
  -- Favorite outcome: dies hits -> favorite (dies) wins the dog's 10g.
  local orders = {
    Ann = { target = "Carol", side = "dies" }, Cy = { target = "Carol", side = "survives" },
  }
  local r = B.MatchHotSeat(orders, { Carol = "dies" }, { Carol = 0.75 }, 10)
  T.eq(r.deltas.Ann, 10, "favorite wins the underdog's 10g")
  T.eq(r.deltas.Cy, -10, "underdog loses 10g")
end
do
  -- Everyone same side -> no pairs, all unmatched, all refunded.
  local orders = { Ann = { target = "T", side = "dies" }, Bob = { target = "T", side = "dies" } }
  local r = B.MatchHotSeat(orders, { T = "dies" }, { T = 0.6 }, 10)
  T.eq(r.deltas.Ann, 0, "no opposite -> refund"); T.eq(r.deltas.Bob, 0, "no opposite -> refund")
  T.eq(#r.pairs, 0, "no pairs"); T.eq(#r.unmatched, 2, "both unmatched")
end
