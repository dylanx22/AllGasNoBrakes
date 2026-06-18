local A = __AGNB_NS.Achievements

-- Fresh-ish record: a few deaths, nothing special.
local rookie = { deaths = 12, wipeDeaths = 0, environment = 2, byAbility = { Fireball = 4 }, byCause = { ["Fireball\31Boss"] = 4 } }
local r = A.For(rookie)
local ids = {}; for _, a in ipairs(r) do ids[a.id] = true end
T.ok(ids["d10"], "10 deaths earns Getting Comfortable")
T.ok(not ids["d25"], "not yet Frequent Flyer at 12")
T.eq(A.CountFor(rookie), 1, "one achievement so far")

-- Veteran feeder: lots of deaths, repeats, env, cascades.
local vet = {
  deaths = 120, wipeDeaths = 60, environment = 15,
  byAbility = { ["Shadow Bolt"] = 30, Cleave = 10 },
  byCause = { ["Shadow Bolt\31Prince"] = 22, ["Cleave\31Gruul"] = 8 },
}
local v = A.For(vet)
local vids = {}; for _, a in ipairs(v) do vids[a.id] = true end
T.ok(vids["d10"] and vids["d25"] and vids["d50"] and vids["d100"], "death milestones up to 100")
T.ok(not vids["d250"], "not 250 yet")
T.ok(vids["env10"], "environmental deaths")
T.ok(vids["habit"], "same (spell,mob) 20+ times")
T.ok(vids["slow"], "one ability 25+ times")
T.ok(vids["casc"], "50+ wipe-cascade deaths")

T.eq(#A.For(nil), 0, "nil record -> no achievements")
