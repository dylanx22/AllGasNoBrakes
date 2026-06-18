local KC = __AGNB_NS.Killcam

-- Record appends per-player; Snapshot returns the window oldest-first.
do
  local tl = KC.NewTimeline()
  KC.Record(tl, "Pyro", { t = 100, kind = "dmg", source = "Boss", spell = "Shadow Bolt", amount = 4000 })
  KC.Record(tl, "Pyro", { t = 103, kind = "heal", source = "Healer", spell = "Flash Heal", amount = 2500 })
  KC.Record(tl, "Pyro", { t = 105, kind = "cast", source = "Pyro", spell = "Pyroblast" })
  local snap = KC.Snapshot(tl, "Pyro", 105)
  T.eq(#snap, 3, "all three events in window")
  T.eq(snap[1].spell, "Shadow Bolt", "oldest first")
  T.eq(snap[3].kind, "cast", "newest last")
  T.eq(#KC.Snapshot(tl, "Nobody", 105), 0, "unknown player -> empty")
end

-- Events older than WINDOW (10s) before the newest are trimmed on Record.
do
  local tl = KC.NewTimeline()
  KC.Record(tl, "A", { t = 1, kind = "dmg", source = "X", spell = "Old" })
  KC.Record(tl, "A", { t = 20, kind = "dmg", source = "X", spell = "New" })
  local snap = KC.Snapshot(tl, "A", 20)
  T.eq(#snap, 1, "stale event trimmed")
  T.eq(snap[1].spell, "New", "only recent kept")
end

-- Within the window, the ring caps at MAX_EVENTS (12), keeping the most recent.
do
  local tl = KC.NewTimeline()
  -- 20 events inside a 2s span (well within the 10s window) -> the count cap binds.
  for i = 1, 20 do KC.Record(tl, "A", { t = 1000 + i * 0.1, kind = "dmg", source = "X", spell = "S" .. i }) end
  local snap = KC.Snapshot(tl, "A", 1002)
  T.eq(#snap, KC.MAX_EVENTS, "capped at MAX_EVENTS within the window")
  T.eq(snap[#snap].spell, "S20", "newest retained")
end

-- Snapshot includes events within [deathTime - WINDOW, deathTime].
do
  local tl = KC.NewTimeline()
  KC.Record(tl, "A", { t = 90,  kind = "dmg", source = "X", spell = "Before" })
  KC.Record(tl, "A", { t = 96,  kind = "dmg", source = "X", spell = "In" })
  KC.Record(tl, "A", { t = 100, kind = "dmg", source = "X", spell = "AtDeath" })
  local snap = KC.Snapshot(tl, "A", 100)
  T.eq(#snap, 3, "events within the 10s window up to deathTime")
  T.eq(snap[1].spell, "Before", "t=90 is exactly WINDOW before death, included")
  T.eq(snap[3].spell, "AtDeath", "event at deathTime included")
end

-- Snapshot excludes events after deathTime.
do
  local tl = KC.NewTimeline()
  KC.Record(tl, "A", { t = 96,  kind = "dmg", source = "X", spell = "In" })
  KC.Record(tl, "A", { t = 102, kind = "dmg", source = "X", spell = "After" })
  local snap = KC.Snapshot(tl, "A", 100)
  T.eq(#snap, 1, "event after deathTime excluded")
  T.eq(snap[1].spell, "In", "only the pre-death event")
end

-- Format produces relative-time strings and passes through fields.
do
  local rows = KC.Format({
    { t = 96, kind = "dmg", source = "Boss", spell = "Bolt", amount = 4000 },
    { t = 100, kind = "cast", source = "A", spell = "Heal" },
  }, 100)
  T.eq(rows[1].rel, "-4.0s", "relative time of first")
  T.eq(rows[1].amount, 4000, "amount passthrough")
  T.eq(rows[2].rel, "-0.0s", "death-moment cast")
  T.eq(rows[2].amount, nil, "cast has no amount")
end
