local BN = __AGNB_NS.Banner

-- DetectWipe: a wipe is "combat ended and (nearly) everyone dead".
T.eq(BN.DetectWipe(25, 25, true), true, "all dead + combat ended => wipe")
T.eq(BN.DetectWipe(25, 25, false), false, "still in combat => not yet")
T.eq(BN.DetectWipe(10, 25, true), false, "partial deaths => not a wipe")
T.eq(BN.DetectWipe(5, 0, true), false, "raidSize 0 => not a wipe")

-- Quip is deterministic with an injected rng and non-empty.
local q = BN.Quip(function() return 0 end)
T.ok(type(q) == "string" and #q > 0, "quip is a non-empty string")

-- StatLine assembles brand/zone/boss/deaths/seconds/quip; omits a nil boss cleanly.
local s = BN.StatLine("Liquid", "Karazhan", "Prince", 9, 5, "Magnificent.")
T.ok(s:find("Liquid") and s:find("Karazhan") and s:find("Prince"), "names present")
T.ok(s:find("9 dead in 5"), "death/seconds present")
local s2 = BN.StatLine("Liquid", "Karazhan", nil, 9, 5, "Magnificent.")
T.ok(not s2:find(" %-  %-"), "no empty boss segment")
