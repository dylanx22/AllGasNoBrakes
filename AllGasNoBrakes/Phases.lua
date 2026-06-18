local _, ns = ...
ns = ns or __AGNB_NS
ns.Phases = ns.Phases or {}
local P = ns.Phases

-- Curated boss phases keyed by encounterID (from ENCOUNTER_START). Phase 1 is the
-- implicit fight start; each trigger advances to a later phase when its combat-log
-- event fires. event: "cast" (SPELL_CAST_SUCCESS), "auraOn" (SPELL_AURA_APPLIED on
-- the boss), "auraOff" (SPELL_AURA_REMOVED). Matched by spellId. Bosses with no
-- entry are single-phase. Trigger IDs are mined from real combat logs (see the
-- curation task); Lady Vashj is confirmed from the player's own log.
P.PHASES = {
  [628] = { name = "Lady Vashj", phases = { "P1 Gauntlet", "P2 Elementals", "P3 Burn" },
    triggers = {
      { event = "auraOn",  spellId = 38112, phase = 2 },   -- Magic Barrier up
      { event = "auraOff", spellId = 38112, phase = 3 },   -- Magic Barrier down
    } },
  -- Trigger IDs below mined from the player's combat logs (casts) + known mechanics.
  [651] = { name = "Magtheridon", phases = { "P1 Banished", "P2 Released" },
    triggers = {
      { event = "cast", spellId = 30616, phase = 2 },   -- Blast Nova (only once released)
    } },
  [661] = { name = "Prince Malchezaar", phases = { "P1 Axes Sheathed", "P2 Infernals", "P3 Dual Axes" },
    triggers = {
      { event = "cast", spellId = 30843, phase = 2 },   -- Enfeeble (P2)
      { event = "cast", spellId = 39095, phase = 3 },   -- Amplify Damage (P3 dual axes)
    } },
  [730] = { name = "Al'ar", phases = { "P1 Flight", "P2 Ground" },
    triggers = {
      { event = "cast", spellId = 35369, phase = 2 },   -- Rebirth (lands as P2)
      { event = "cast", spellId = 34229, phase = 2 },   -- Flame Quills (ground-only)
    } },
  [732] = { name = "High Astromancer Solarian", phases = { "P1 Astromancer", "P2 Voidwalker" },
    triggers = {
      { event = "cast", spellId = 39329, phase = 2 },   -- Void Bolt (voidwalker form)
    } },
  [733] = { name = "Kael'thas Sunstrider", phases = { "P1 Advisors & Weapons", "P2 Gravity Lapse" },
    triggers = {
      { event = "cast", spellId = 35941, phase = 2 },   -- Gravity Lapse (final phase)
    } },
}

function P.For(encounterID) return encounterID and P.PHASES[encounterID] or nil end

-- Display name for a phase index in an encounter (nil if uncurated).
function P.Name(encounterID, phaseIndex)
  local def = P.For(encounterID)
  return def and def.phases and def.phases[phaseIndex] or nil
end

-- Advance a phase state from a combat-log event. state = { encounterID, phaseIndex }.
-- Forward-only (re-applied auras / repeated casts are idempotent). Returns phaseIndex.
function P.Advance(state, event, spellId)
  local def = P.For(state.encounterID)
  if not (def and def.triggers) then return state.phaseIndex end
  for _, t in ipairs(def.triggers) do
    if t.event == event and t.spellId == spellId and t.phase > state.phaseIndex then
      state.phaseIndex = t.phase
    end
  end
  return state.phaseIndex
end
