local TR = __AGNB_NS.Tracking

-- Damage buffer remembers the last hit on each player.
local buf = TR.NewBuffer()
TR.RecordDamage(buf, "Pyro", "Boss", "Shadow Bolt", 100)
TR.RecordDamage(buf, "Pyro", "Boss", "Corruption", 101)
local hit = TR.LastHit(buf, "Pyro")
T.eq(hit.spell, "Corruption", "last hit is most recent")
T.eq(hit.source, "Boss", "last hit source")
T.eq(TR.LastHit(buf, "Nobody"), nil, "no hit for unknown player")

-- ParseDeath on a UNIT_DIED row for a tracked raider returns a record.
local info = { subevent="UNIT_DIED", destName="Pyro", destIsPlayer=true }
local d = TR.ParseDeath(info)
T.eq(d.player, "Pyro", "parsed player")
T.eq(d.isEnv, false, "not environmental")

-- ParseDeath on ENVIRONMENTAL_DAMAGE flags env + type.
local envInfo = { subevent="ENVIRONMENTAL_DAMAGE", destName="Grug", destIsPlayer=true, envType="LAVA" }
local de = TR.ParseDeath(envInfo)
T.eq(de.isEnv, true, "env flagged")
T.eq(de.envType, "Lava", "env type normalized")

-- Non-player or non-death rows return nil.
T.eq(TR.ParseDeath({ subevent="SPELL_DAMAGE", destName="Pyro", destIsPlayer=true }), nil, "damage row ignored")
T.eq(TR.ParseDeath({ subevent="UNIT_DIED", destName="Boar", destIsPlayer=false }), nil, "non-player ignored")

-- Pull tracks how many were dead BEFORE each death (for classification).
local pull = TR.NewPull(25)
T.eq(pull:OnDeath(), 0, "first death: 0 dead before")
T.eq(pull:OnDeath(), 1, "second death: 1 dead before")

-- RaidIdFor: bucket by instance lockout, else fall back to the session id.
T.eq(TR.RaidIdFor(true, 533, "raid-9"), "inst-533", "in instance keys by lockout id")
T.eq(TR.RaidIdFor(true, 0, "raid-9"), "raid-9", "zero instance id falls back to session")
T.eq(TR.RaidIdFor(false, 533, "raid-9"), "raid-9", "outside instance uses session")
T.eq(TR.RaidIdFor(true, nil, "raid-9"), "raid-9", "nil instance id falls back")
