local D = __AGNB_NS.Debug

-- Level values
T.eq(D.LevelValue("off"), 0, "off=0")
T.eq(D.LevelValue("error"), 1, "error=1")
T.eq(D.LevelValue("info"), 2, "info=2")
T.eq(D.LevelValue("debug"), 3, "debug=3")
T.eq(D.LevelValue("bogus"), 0, "unknown=0")

-- ShouldLog: log a message if its level is within the configured level (and not off).
T.eq(D.ShouldLog("info", "error"), true, "info config logs errors")
T.eq(D.ShouldLog("info", "info"), true, "info config logs info")
T.eq(D.ShouldLog("info", "debug"), false, "info config drops debug")
T.eq(D.ShouldLog("off", "error"), false, "off logs nothing")
T.eq(D.ShouldLog("debug", "debug"), true, "debug config logs debug")

-- Format
local f = D.Format("12:00:00", "error", "boom")
T.ok(f:find("12:00:00"), "has timestamp")
T.ok(f:find("ERROR"), "has uppercased level")
T.ok(f:find("boom"), "has message")

-- Push: ring buffer trims oldest beyond max
local r = {}
for i = 1, 5 do D.Push(r, "l" .. i, 3) end
T.eq(#r, 3, "trimmed to max")
T.eq(r[1], "l3", "oldest dropped")
T.eq(r[3], "l5", "newest kept")
