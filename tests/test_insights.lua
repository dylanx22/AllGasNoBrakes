local I = __AGNB_NS.Insights

-- ByBoss: groups counted deaths, picks deadliest ability/source and top feeder.
do
  local deaths = {
    { player = "Anna", boss = "Gruul", ability = "Shatter", sourceName = "Gruul", classification = "counted" },
    { player = "Anna", boss = "Gruul", ability = "Shatter", sourceName = "Gruul", classification = "counted" },
    { player = "Bob",  boss = "Gruul", ability = "Cave In", sourceName = "Gruul", classification = "counted" },
    { player = "Cara", boss = "Gruul", ability = "Shatter", sourceName = "Gruul", classification = "wipeCascade" },
    { player = "Bob",  boss = "Magtheridon", ability = "Blast Nova", sourceName = "Magtheridon", classification = "counted" },
  }
  local b = I.ByBoss(deaths)
  T.eq(b[1].boss, "Gruul", "Gruul has the most deaths")
  T.eq(b[1].deaths, 3, "cascade excluded from count")
  T.eq(b[1].topCause, "Shatter", "deadliest ability")
  T.eq(b[1].feeder, "Anna", "top feeder")
  T.eq(b[1].feederCount, 2, "feeder count")
  T.eq(b[2].boss, "Magtheridon", "second boss")
end

-- PhaseSplit: buckets a curated boss's deaths by phaseIndex, flags the deadliest.
do
  local deaths = {
    { player = "A", boss = "Lady Vashj", encounterID = 628, phaseIndex = 1, classification = "counted" },
    { player = "B", boss = "Lady Vashj", encounterID = 628, phaseIndex = 2, classification = "counted" },
    { player = "C", boss = "Lady Vashj", encounterID = 628, phaseIndex = 2, classification = "counted" },
    { player = "D", boss = "Lady Vashj", encounterID = 628, phaseIndex = 3, classification = "wipeCascade" },
  }
  local ph = I.PhaseSplit(deaths, "Lady Vashj", 628)
  T.eq(#ph, 3, "three phases")
  T.eq(ph[2].count, 2, "P2 has two deaths")
  T.eq(ph[2].deadliest, true, "P2 is the deadliest phase")
  T.eq(ph[1].deadliest, false, "P1 not deadliest")
  T.eq(ph[3].count, 0, "cascade death excluded from P3")
end
-- Uncurated boss -> nil (single phase, no split).
do
  T.eq(I.PhaseSplit({}, "Gruul", 650), nil, "uncurated boss has no phase split")
end

-- PullTimeline: deaths of one pull, time-ordered, with offset from pull start.
do
  local deaths = {
    { player = "A", pullId = 7, time = 1000, ability = "Cleave", sourceName = "Boss", classification = "counted" },
    { player = "B", pullId = 7, time = 1084, ability = "Fire",  sourceName = "Boss", classification = "counted" },
    { player = "X", pullId = 6, time = 900,  ability = "Old",   sourceName = "Boss", classification = "counted" },
  }
  local tl = I.PullTimeline(deaths, { pullId = 7, startTime = 1000 })
  T.eq(#tl, 2, "only pull 7's deaths")
  T.eq(tl[1].player, "A", "earliest first")
  T.eq(tl[1].offset, 0, "first death at +0")
  T.eq(tl[2].offset, 84, "second death offset seconds")
  T.ok(tl[2].cause:find("Fire", 1, true) ~= nil, "cause includes ability")
end
