local D = __AGNB_NS.Demo

-- SyntheticDeaths: deterministic with an injected rng. Players are sampled from a
-- skewed weight, so a constant rng deterministically lands on the same player.
local d = D.SyntheticDeaths({ "A", "B" }, 6, function() return 0.5 end)
T.eq(#d, 6, "count honored")
for _, x in ipairs(d) do T.eq(x.player, "A", "skewed pick is deterministic, not round-robin") end
T.ok(d[1].ability ~= nil and d[1].ability ~= "", "has an ability")
T.ok(d[1].sourceName ~= nil, "has a source")
T.eq(d[1].classification, "counted", "rng 0.5 => counted")
T.eq(d[1].isEnv, false, "rng 0.5 => not environmental")
T.ok(d[1].time < d[2].time, "times strictly increase (dedupe-safe)")
T.ok(d[1].pullId ~= nil, "has a pull id")

-- A varying rng produces a varied distribution (multiple players, with ties) --
-- the whole point of the skew: not one death apiece.
local seq, k = { 0.02, 0.45, 0.95, 0.6, 0.1, 0.8, 0.3, 0.5 }, 0
local function stepRng() k = k + 1; return seq[((k - 1) % #seq) + 1] end
local many = D.SyntheticDeaths({ "A", "B", "C", "D" }, 40, stepRng)
local counts = {}
for _, x in ipairs(many) do counts[x.player] = (counts[x.player] or 0) + 1 end
local distinct, maxc = 0, 0
for _, c in pairs(counts) do distinct = distinct + 1; if c > maxc then maxc = c end end
T.ok(distinct >= 2, "varied distribution spans multiple players")
T.ok(maxc >= 2, "at least one player dies multiple times (not 1-each)")

-- SyntheticDeathsVaried: every name gets a counted deaths total in [min,max].
local vary = D.SyntheticDeathsVaried({ "A", "B", "C" }, 1, 6, function() return 0.5 end)
local vc = {}
for _, x in ipairs(vary) do
  vc[x.player] = (vc[x.player] or 0) + 1
  T.eq(x.classification, "counted", "varied deaths all count (no wipe-cascade)")
end
for _, name in ipairs({ "A", "B", "C" }) do
  T.ok(vc[name] and vc[name] >= 1 and vc[name] <= 6, name .. " has 1-6 deaths")
end
