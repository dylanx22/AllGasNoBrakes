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

-- ReadEvent: pure normalization of the combat-log vararg tuple. Param order is
-- ts, subevent, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags, destGUID,
-- destName, destFlags, destRaidFlags, p12, p13(spell), p14, p15(amount).
do
  -- an untracked subevent early-bails to nil (no info table allocated), ts passes through
  local info, ts = TR.ReadEvent(50, "SPELL_AURA_APPLIED", false, "g", "Caster")
  T.eq(info, nil, "untracked subevent returns nil info")
  T.eq(ts, 50, "timestamp still returned on bail")

  -- SPELL_DAMAGE: amount is param 15, spell name is param 13
  local di = TR.ReadEvent(7, "SPELL_DAMAGE", false, "sg", "Boss", 0, 0, "dg", "Pyro", 0, 0,
    133, "Fireball", 4, 4321)
  T.eq(di.subevent, "SPELL_DAMAGE", "subevent carried")
  T.eq(di.sourceName, "Boss", "source name")
  T.eq(di.destName, "Pyro", "dest name")
  T.eq(di.spell, "Fireball", "spell from p13")
  T.eq(di.amount, 4321, "SPELL_DAMAGE amount from p15")

  -- SWING_DAMAGE: amount is param 12, spell defaults later in OnCombatLog (here nil)
  local sw = TR.ReadEvent(8, "SWING_DAMAGE", false, "sg", "Boss", 0, 0, "dg", "Grug", 0, 0, 999)
  T.eq(sw.amount, 999, "SWING_DAMAGE amount from p12")

  -- a numeric spellId in the name slot is stringified (no GetSpellInfo stub in tests)
  -- so cause/source maps never mix number and string keys.
  local num = TR.ReadEvent(9, "SPELL_PERIODIC_DAMAGE", false, "sg", "Boss", 0, 0, "dg", "Grug", 0, 0,
    123, 456, 4, 10)
  T.eq(num.spell, "456", "numeric spellId stringified")

  -- ENVIRONMENTAL_DAMAGE: envType is param 12, carried for ParseDeath
  local env = TR.ReadEvent(10, "ENVIRONMENTAL_DAMAGE", false, nil, nil, 0, 0, "dg", "Grug", 0, 0, "LAVA")
  T.eq(env.subevent, "ENVIRONMENTAL_DAMAGE", "env subevent carried")
  T.eq(env.envType, "LAVA", "env type from p12")
end

-- RaidIdFor: bucket by instance lockout, else fall back to the session id.
T.eq(TR.RaidIdFor(true, 533, "raid-9"), "inst-533", "in instance keys by lockout id")
T.eq(TR.RaidIdFor(true, 0, "raid-9"), "raid-9", "zero instance id falls back to session")
T.eq(TR.RaidIdFor(false, 533, "raid-9"), "raid-9", "outside instance uses session")
T.eq(TR.RaidIdFor(true, nil, "raid-9"), "raid-9", "nil instance id falls back")
