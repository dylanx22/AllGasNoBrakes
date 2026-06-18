local B = __AGNB_NS.Book

-- A gold offer tied to dying trips the heuristic (score 2).
do
  local s = B.ScoreWhisper("yo I'll give you 10g if you die on this pull")
  T.eq(s, 2, "rigging offer scores 2")
end
-- Innocent trash talk with a death word but no gold offer does not trip it.
do
  local s = B.ScoreWhisper("good luck, try not to die lol")
  T.ok(s < 2, "death talk alone is not flagged")
end
-- A gold loan with no death language does not trip it.
do
  local s = B.ScoreWhisper("can you lend me 50g for my mount")
  T.ok(s < 2, "gold alone is not flagged")
end
-- Empty / nil is safe.
do
  T.eq(B.ScoreWhisper(""), 0, "empty is 0")
  T.eq(B.ScoreWhisper(nil), 0, "nil is 0")
end
