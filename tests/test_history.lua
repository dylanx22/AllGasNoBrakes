local H = __AGNB_NS.History

local function store()
  return { raids = {
    ["raid-100"] = { startTime = 100, zone = "Karazhan", deaths = {
      { player = "Anna", time = 100, boss = "Attumen", ability = "Cleave", sourceName = "Attumen", zone = "Karazhan", pullId = 1, classification = "counted" },
      { player = "Anna", time = 160, boss = "Attumen", ability = "Cleave", sourceName = "Attumen", zone = "Karazhan", pullId = 1, classification = "counted" },
      { player = "Bob",  time = 200, boss = "Moroes",  ability = "Garrote", sourceName = "Moroes", zone = "Karazhan", pullId = 2, classification = "wipeCascade" },
    } },
    ["raid-500"] = { startTime = 500, zone = "Gruul's Lair", deaths = {
      { player = "Cara", time = 520, boss = "Gruul", ability = "Shatter", sourceName = "Gruul", zone = "Gruul's Lair", pullId = 1, classification = "counted" },
    } },
  } }
end

-- List: newest-first, with body/wipe/boss counts and duration.
do
  local rows = H.List(store())
  T.eq(#rows, 2, "two raids")
  T.eq(rows[1].raidId, "raid-500", "newest first")
  T.eq(rows[2].bodyCount, 2, "non-cascade body count")
  T.eq(rows[2].wipeCount, 1, "one wiped pull")
  T.eq(rows[2].bossCount, 2, "two distinct bosses")
  T.eq(rows[2].duration, 100, "last - first death time")
  T.eq(rows[2].zones[1], "Karazhan", "zone from deaths")
end

-- Report: meta + composed lowlights/perBoss/ledger for one night.
do
  local r = H.Report(store(), "raid-100", 1)
  T.eq(r.meta.bodyCount, 2, "report body count")
  T.eq(r.meta.bossCount, 2, "report boss count")
  T.eq(r.meta.wipeCount, 1, "report wipe count")
  T.eq(r.lowlights.feeder, "Anna", "lowlights composed")
  T.eq(r.perBoss[1].boss, "Attumen", "perBoss composed (most deaths)")
  T.eq(r.meta.pot, 2, "anti-prize pot = body count * buyIn")
  T.ok(r.meta.winner ~= nil, "a winner is chosen")
end

-- Unknown raid id -> nil.
do
  T.eq(H.Report(store(), "nope"), nil, "missing raid -> nil")
end
