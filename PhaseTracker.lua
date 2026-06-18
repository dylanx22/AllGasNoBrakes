local _, ns = ...
ns = ns or __AGNB_NS
ns.PhaseTracker = ns.PhaseTracker or {}
local PT = ns.PhaseTracker

-- Current phase, exposed for Tracking to stamp onto deaths.
PT.currentEncounterID = nil
PT.currentPhaseIndex = 1
PT.currentPhase = nil
PT.currentBoss = nil

local state = { encounterID = nil, phaseIndex = 1 }

local function publish()
  PT.currentEncounterID = state.encounterID
  PT.currentPhaseIndex = state.phaseIndex
  PT.currentPhase = ns.Phases.Name(state.encounterID, state.phaseIndex)
end

function PT.OnEncounterStart(encounterID, name)
  state.encounterID = tonumber(encounterID); state.phaseIndex = 1
  PT.currentBoss = name
  publish()
end

function PT.OnEncounterEnd()
  state.encounterID = nil; state.phaseIndex = 1; PT.currentBoss = nil
  publish()
end

-- Feed one normalized combat-log event into the phase machine.
function PT.Feed(event, spellId)
  if not state.encounterID then return end
  ns.Phases.Advance(state, event, spellId)
  publish()
end

local SUBEVENT = { SPELL_CAST_SUCCESS = "cast", SPELL_AURA_APPLIED = "auraOn", SPELL_AURA_REMOVED = "auraOff" }

ns.OnInit(function()
  local f = CreateFrame("Frame")
  f:RegisterEvent("ENCOUNTER_START")
  f:RegisterEvent("ENCOUNTER_END")
  f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  f:SetScript("OnEvent", ns.Debug.Guard("PhaseTracker.OnEvent", function(_, evt, ...)
    if evt == "ENCOUNTER_START" then
      local id, name = ...
      PT.OnEncounterStart(id, name)
    elseif evt == "ENCOUNTER_END" then
      PT.OnEncounterEnd()
    else
      if not state.encounterID then return end
      local t = { CombatLogGetCurrentEventInfo() }
      local event = SUBEVENT[t[2]]
      if not event then return end
      local srcName, dstName, spellId = t[5], t[9], t[12]
      local boss = PT.currentBoss
      local involves = boss and (srcName == boss or dstName == boss)
      if involves then PT.Feed(event, spellId) end
      if PT.debug and involves then
        ns.Log("info", ("phase? enc=%s id=%s %s %s"):format(
          tostring(state.encounterID), tostring(spellId), tostring(t[13]), event))
      end
    end
  end))
end)

-- Dev-only logger for confirming trigger spell IDs in a live raid.
function PT.ToggleDebug()
  if not (ns.Demo and ns.Demo.IsDev and ns.Demo.IsDev()) then ns.Print("Phase debug is dev-only.") return end
  PT.debug = not PT.debug
  ns.Print("Phase debug " .. (PT.debug and "ON (set /agnb debug level info to capture)" or "off"))
end
