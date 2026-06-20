local SM = __AGNB_NS.Summary

-- FinalBoss: true only for the last boss of a TBC instance (by encounter NAME).
T.eq(SM.FinalBoss("Prince Malchezaar"), true, "Kara final boss")
T.eq(SM.FinalBoss("Kil'jaeden"), true, "Sunwell final boss")
T.eq(SM.FinalBoss("Attumen the Huntsman"), false, "not a final boss")
T.eq(SM.FinalBoss(nil), false, "nil name => false")

-- Duration: seconds -> "Hh Mm" / "Mm".
T.eq(SM.Duration(0, 8040), "2h14m", "2h14m")
T.eq(SM.Duration(0, 2820), "47m", "under an hour")
T.eq(SM.Duration(100, 100), "0m", "zero")

-- CanBroadcast: leader/assist OR a name present in DEV_BROADCASTERS. The dev table is
-- empty by default in the public build (dev access is unlocked per-character via
-- `/agnb dev on`, which injects the local name); the battletag path is cleared too.
T.eq(SM.CanBroadcast(true, false, "Random", "x#1"), true, "leader can")
T.eq(SM.CanBroadcast(false, true, "Random", "x#1"), true, "assist can")
T.eq(SM.CanBroadcast(false, false, "Random", "x#1"), false, "rando cannot")
T.eq(SM.CanBroadcast(false, false, "Anybody", nil), false, "no hardcoded dev names by default")
do
  SM.DEV_BROADCASTERS["Unlocked"] = true   -- simulates `/agnb dev on` injecting the local name
  T.eq(SM.CanBroadcast(false, false, "Unlocked", nil), true, "an unlocked dev name is allowed")
  SM.DEV_BROADCASTERS["Unlocked"] = nil
end
T.eq(SM.CanBroadcast(false, false, "Random", "vx22#1605"), false, "old dev battletag cleared")
