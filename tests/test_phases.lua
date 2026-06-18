local P = __AGNB_NS.Phases

-- Vashj (628): Magic Barrier aura on -> P2, off -> P3; forward-only; ignores noise.
do
  local s = { encounterID = 628, phaseIndex = 1 }
  P.Advance(s, "cast", 99999);        T.eq(s.phaseIndex, 1, "unknown spell does nothing")
  P.Advance(s, "auraOn", 38112);      T.eq(s.phaseIndex, 2, "Magic Barrier on -> P2")
  P.Advance(s, "auraOn", 38112);      T.eq(s.phaseIndex, 2, "re-apply is idempotent")
  P.Advance(s, "auraOff", 38112);     T.eq(s.phaseIndex, 3, "Magic Barrier off -> P3")
  P.Advance(s, "auraOn", 38112);      T.eq(s.phaseIndex, 3, "forward-only, never goes back")
  T.eq(P.Name(628, 2), "P2 Elementals", "phase name lookup")
end
-- Uncurated encounter: phase never advances, no name.
do
  local s = { encounterID = 777, phaseIndex = 1 }
  P.Advance(s, "auraOn", 38112);      T.eq(s.phaseIndex, 1, "uncurated stays phase 1")
  T.eq(P.Name(777, 1), nil, "uncurated has no phase name")
  T.eq(P.For(nil), nil, "nil encounter is nil")
end

-- Curated multi-phase bosses advance through their mined triggers in order.
do
  local s = { encounterID = 661, phaseIndex = 1 }   -- Prince Malchezaar
  P.Advance(s, "cast", 30843); T.eq(s.phaseIndex, 2, "Enfeeble -> P2 (infernals)")
  P.Advance(s, "cast", 39095); T.eq(s.phaseIndex, 3, "Amplify Damage -> P3 (dual axes)")
  T.eq(P.Name(661, 3), "P3 Dual Axes", "Prince final phase name")
  local k = { encounterID = 733, phaseIndex = 1 }   -- Kael'thas
  P.Advance(k, "cast", 35941); T.eq(k.phaseIndex, 2, "Gravity Lapse -> Kael final phase")
end
