local M = __AGNB_NS.Milestones

-- Thresholds: fires only for marks crossed between prev and cur.
do
  T.eq(#M.Thresholds(4, 5), 1, "crossing 5 fires once")
  T.eq(M.Thresholds(4, 5)[1], 5, "the crossed mark is 5")
  T.eq(#M.Thresholds(5, 6), 0, "already past 5 -> nothing")
  T.eq(#M.Thresholds(9, 11, { 5, 10, 25 }), 1, "crossing 10 within a jump")
  T.eq(#M.Thresholds(0, 0), 0, "no deaths -> nothing")
end

-- NewAchievements: returns entries whose id wasn't in the previous set.
do
  local prev = { d10 = true }
  local cur = { { id = "d10", name = "Getting Comfortable" }, { id = "d25", name = "Frequent Flyer" } }
  local new = M.NewAchievements(prev, cur)
  T.eq(#new, 1, "one newly earned")
  T.eq(new[1].id, "d25", "the new one is d25")
  T.eq(#M.NewAchievements({ d10 = true, d25 = true }, cur), 0, "nothing new when all known")
end

-- CleanPull: true only for a boss pull with zero deaths.
do
  T.eq(M.CleanPull(0, true), true, "boss pull, nobody died")
  T.eq(M.CleanPull(1, true), false, "someone died")
  T.eq(M.CleanPull(0, false), false, "not a boss pull")
end
