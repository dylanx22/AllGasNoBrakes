local E = __AGNB_NS.Export

local function report(opts)
  opts = opts or {}
  return {
    meta = { zones = { "Karazhan" }, duration = 3600, wipeCount = 3, bossCount = 4,
             bodyCount = 14, pot = opts.pot, winner = opts.winner },
    lowlights = { feeder = "Anna", feederDeaths = 6, deadliestAbility = "Cleave",
                  deadliestSource = "Attumen", firstBlood = "Bob" },
    perBoss = { { boss = "Attumen", deaths = 5, topCause = "Cleave" },
                { boss = "Moroes", deaths = 4, topCause = "Garrote" } },
  }
end

-- Text: Discord-ready lines covering meta, lowlights, per-boss.
do
  local txt = E.Text(report({ pot = 14, winner = "Cara" }))
  T.ok(txt:find("Body count: 14", 1, true) ~= nil, "body count line")
  T.ok(txt:find("Feeder of the Night: Anna", 1, true) ~= nil, "feeder line")
  T.ok(txt:find("Attumen: 5", 1, true) ~= nil, "per-boss line")
  T.ok(txt:find("Anti%-prize pot: 14g") ~= nil, "pot line when pot > 0")
  T.eq(txt:find("\226\128\148"), nil, "no em-dash glyph")  -- U+2014
end

-- Text: pot line omitted when pot is zero/absent.
do
  local txt = E.Text(report({ pot = 0 }))
  T.eq(txt:find("Anti-prize pot", 1, true), nil, "no pot line at zero")
end

-- Card: ordered sections; Raid always present, Lowlights/Per-boss present,
-- Anti-Prize only when pot > 0.
do
  local c = E.Card(report({ pot = 14, winner = "Cara" }))
  T.eq(c[1].title, "Raid", "first section is Raid")
  local titles = {}
  for _, s in ipairs(c) do titles[s.title] = true end
  T.ok(titles["Lowlights"], "lowlights section")
  T.ok(titles["Per-boss"], "per-boss section")
  T.ok(titles["Anti-Prize"], "anti-prize section present with pot")
end
do
  local c = E.Card(report({ pot = 0 }))
  for _, s in ipairs(c) do T.ok(s.title ~= "Anti-Prize", "no anti-prize section at zero pot") end
end
