local S = __AGNB_NS.Streak

-- DetectLeadChange: only fires when an existing leader is overtaken by a new player.
T.eq(S.DetectLeadChange(nil, {{player="A"}}), nil, "first leader is not a breaker")
T.eq(S.DetectLeadChange("A", {{player="A"}}), nil, "same leader = no change")
T.eq(S.DetectLeadChange("A", {{player="B"}}), "B", "B overtakes A")
T.eq(S.DetectLeadChange("A", {}), nil, "empty board = nil")

-- RecordPull: a player who dies in N consecutive pulls fires once at the threshold.
local st = S.NewState()
T.eq(#S.RecordPull(st, {"A"}, 3), 0, "pull 1: no fire")
T.eq(#S.RecordPull(st, {"A"}, 3), 0, "pull 2: no fire")
local fired = S.RecordPull(st, {"A"}, 3)
T.eq(fired[1], "A", "pull 3: A fires")
-- not dying resets the streak
S.RecordPull(st, {"B"}, 3)
T.eq(st.streaks["A"], 0, "A's streak reset after a clean pull")
