local _, ns = ...
ns = ns or __AGNB_NS
ns.Tracking = ns.Tracking or {}
local TR = ns.Tracking

-- ----- pure: damage buffer -----
function TR.NewBuffer() return {} end

function TR.RecordDamage(buf, dest, source, spell, time, isEnv)
  buf[dest] = { source = source, spell = spell, time = time, isEnv = isEnv or nil }
end

function TR.LastHit(buf, dest) return buf[dest] end

-- ----- pure: raid bucket id -----
-- Bucket deaths by the instance lockout so a reload/relog or leaving and
-- re-entering the same raid keeps one History entry. In an instance with a real
-- instanceID we key by it; otherwise fall back to the per-session id.
function TR.RaidIdFor(inInstance, instanceID, sessionId)
  if inInstance and instanceID and instanceID ~= 0 then
    return "inst-" .. tostring(instanceID)
  end
  return sessionId
end

-- ----- pure: environmental type normalization -----
local ENV = { FALLING="Fall", DROWNING="Drowning", FATIGUE="Fatigue",
              FIRE="Fire", LAVA="Lava", SLIME="Slime" }

-- ----- pure: parse a normalized combat-log row into a partial death record -----
-- Only UNIT_DIED is a death. ENVIRONMENTAL_DAMAGE is NOT -- it fires whenever a player
-- TAKES fall/lava/fire damage (surviving a fall would otherwise log a phantom death). The
-- env cause is buffered as a last-hit (see OnCombatLog) and attached when UNIT_DIED fires.
function TR.ParseDeath(info)
  if not info or not info.destIsPlayer then return nil end
  if info.subevent == "UNIT_DIED" then
    return { player = info.destName, isEnv = false }
  end
  return nil
end

-- ----- pure: pull state -----
function TR.NewPull(raidSize, id)
  return setmetatable({ raidSize = raidSize, dead = 0, id = id or 1,
                        startTime = (GetTime and GetTime()) or 0, died = {} }, {
    __index = {
      OnDeath = function(self)
        local before = self.dead
        self.dead = self.dead + 1
        return before
      end,
    },
  })
end

-- ----- WoW glue: wire combat log to DB + classification -----
-- Reads runtime config + db from the namespace; only runs inside the game.
function TR.StartSession()
  TR.buffer = TR.NewBuffer()
  TR.killcam = ns.Killcam.NewTimeline()
  TR.pull = nil
  TR.sessionId = "raid-" .. tostring(time and time() or 0)
  TR.raidId = TR.sessionId
  TR.streak = ns.Streak.NewState()
  TR.earned = {}
  TR.leader = nil
  TR.pullSeq = 0
end

-- WoW glue: recompute the raid bucket from the current instance. Called on
-- PLAYER_ENTERING_WORLD (instance enter / reload / login).
function TR.ResolveRaidId()
  local inInstance = (IsInInstance and (IsInInstance())) and true or false
  local instanceID = nil
  if inInstance and GetInstanceInfo then instanceID = select(8, GetInstanceInfo()) end
  TR.raidId = TR.RaidIdFor(inInstance, instanceID, TR.sessionId)
  -- keep the current raid's killcams; strip older raids' so the save doesn't grow a
  -- per-death timeline across a season (idempotent -- already-stripped deaths are skipped).
  if ns.db and ns.db.store then ns.DB.PruneKillcams(ns.db.store, TR.raidId) end
  return TR.raidId
end

local function raidSize()
  return (GetNumGroupMembers and GetNumGroupMembers()) or 1
end

local function nextPull()
  TR.pullSeq = (TR.pullSeq or 0) + 1
  return TR.NewPull(raidSize(), TR.pullSeq)
end

-- Normalize CombatLogGetCurrentEventInfo() varargs into the table ParseDeath expects.
-- Field order (TBC Classic, same as retail base params):
--   1 timestamp, 2 subevent, 3 hideCaster, 4 sourceGUID, 5 sourceName,
--   6 sourceFlags, 7 sourceRaidFlags, 8 destGUID, 9 destName, 10 destFlags,
--   11 destRaidFlags, then event-specific params (12+).
-- SPELL_* : 12 spellId, 13 spellName, 14 spellSchool.
-- ENVIRONMENTAL_DAMAGE : 12 environmentalType.
-- Subevents we actually act on (last-hit buffer, killcam, death). Everything else
-- (auras, casts we ignore, energize, etc.) is dropped before any allocation.
local PROCESSED = {
  SPELL_DAMAGE = true, SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true,
  SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true, SPELL_CAST_SUCCESS = true,
  UNIT_DIED = true, ENVIRONMENTAL_DAMAGE = true,
}

-- Resolve a spellId to a readable name (modern C_Spell, then legacy GetSpellInfo). Never
-- returns a bare number -- a death's ability MUST be a string, or the leaderboard's
-- cause/source maps mix number+string keys and crash their tie-break (DB topKey()). Falls
-- back to "Spell <id>" so an unresolved spell still reads as a spell, not a random number.
local function resolveSpellName(spellId)
  local id = tonumber(spellId)
  if not id then return "Unknown" end
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(id)
    if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then return info.name end
  end
  if GetSpellInfo then
    local n = GetSpellInfo(id)
    if type(n) == "string" and n ~= "" then return n end
  end
  return "Spell " .. id
end

-- One-time-ish cleanup: re-resolve deaths whose ability was saved as a bare number (an
-- earlier build stored the combat-log NAME slot, which was sometimes a number, not the spell
-- name). Resolve via the spell API where the id is real; otherwise "Unknown" -- the real
-- spellId is unrecoverable for the bogus ones, so never leave a raw number on the board.
-- Idempotent: once abilities are names this finds nothing to change.
function TR.ResolveStoredSpells(store)
  local changed = 0
  for _, raid in pairs((store and store.raids) or {}) do
    for _, d in ipairs(raid.deaths or {}) do
      local ab = d.ability
      local numeric = (type(ab) == "number") or (type(ab) == "string" and ab:match("^%-?%d+$"))
      if numeric then
        local id = tonumber(ab)
        local name = (id and id > 0) and resolveSpellName(id) or "Unknown"
        if id and name == ("Spell " .. id) then name = "Unknown" end  -- bogus id: don't fake it
        if name ~= ab then d.ability = name; changed = changed + 1 end
      end
    end
  end
  if changed > 0 and ns.DB and ns.DB.RebuildAllTime then ns.DB.RebuildAllTime(store) end
  return changed
end

-- Pure: normalize the combat-log vararg tuple into the `info` table OnCombatLog
-- consumes, or nil for subevents we don't track. Taking the params directly (instead
-- of packing CombatLogGetCurrentEventInfo() into a table) and early-bailing BEFORE
-- allocating keeps this allocation-free on every ignored event -- and this runs on the
-- hottest event in the game, so per-event garbage is what causes raid-combat GC stutter.
-- Field order (TBC Classic, same base params as retail):
--   1 timestamp, 2 subevent, 3 hideCaster, 4 sourceGUID, 5 sourceName, 6 sourceFlags,
--   7 sourceRaidFlags, 8 destGUID, 9 destName, 10 destFlags, 11 destRaidFlags, 12+ event-specific.
-- SPELL_* : 12 spellId, 13 spellName, 14 spellSchool, 15 amount.  SWING_DAMAGE : 12 amount.
-- ENVIRONMENTAL_DAMAGE : 12 environmentalType.
function TR.ReadEvent(ts, se, _hideCaster, _srcGUID, srcName, srcFlags,
                      _srcRaidFlags, _destGUID, destName, destFlags, _destRaidFlags,
                      p12, p13, p14, p15)
  if not PROCESSED[se] then return nil, ts end
  -- Spell NAME: p13 is the name slot, p12 the spellId. On the Anniversary client the name
  -- slot sometimes comes back as a NUMBER (or empty) -- that number is NOT the spellId, so
  -- resolve the real name from the spellId (p12), not the bogus name-slot value. SWING has
  -- no spell ("Melee"); UNIT_DIED / ENVIRONMENTAL_DAMAGE carry no spell here.
  local spell
  if se == "SWING_DAMAGE" then
    spell = "Melee"
  elseif se ~= "UNIT_DIED" and se ~= "ENVIRONMENTAL_DAMAGE" then
    spell = (type(p13) == "string" and p13 ~= "" and p13) or resolveSpellName(p12)
  end
  local info = {
    subevent = se,
    sourceName = srcName,
    destName = destName,
    destIsPlayer = false,
    spell = spell,
    envType = p12,
  }
  if destFlags and bit and bit.band then
    info.destIsPlayer = bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER or 0x400) > 0
  end
  if srcFlags and bit and bit.band then
    info.sourceIsPlayer = bit.band(srcFlags, COMBATLOG_OBJECT_TYPE_PLAYER or 0x400) > 0
  end
  if se == "SWING_DAMAGE" then
    info.amount = p12
  elseif se == "SPELL_DAMAGE" or se == "RANGE_DAMAGE" or se == "SPELL_PERIODIC_DAMAGE"
      or se == "SPELL_HEAL" or se == "SPELL_PERIODIC_HEAL" then
    info.amount = p15
  end
  return info, ts
end

local function readEvent()
  return TR.ReadEvent(CombatLogGetCurrentEventInfo())
end

-- Is `name` a member of the player's guild? (short name match against the roster)
-- The roster set is cached and rebuilt only when the member count changes, so a death
-- during a guildOnly raid is an O(1) lookup instead of a full-roster scan per death.
local guildSet, guildSetN = nil, -1
local function guildMemberSet()
  local n = (GetNumGuildMembers and GetNumGuildMembers()) or 0
  if guildSet and guildSetN == n then return guildSet end
  local set = {}
  for i = 1, n do
    local full = GetGuildRosterInfo and GetGuildRosterInfo(i)
    if full then set[full:match("^[^-]+") or full] = true end
  end
  guildSet, guildSetN = set, n
  return set
end
local function isGuildMember(name)
  if not name then return false end
  return guildMemberSet()[name] == true
end

-- Guard rails: ignore deaths outside instances / outside combat when configured.
-- Battlegrounds and arenas are NEVER tracked (instanceType "pvp"/"arena").
local function trackingAllowed()
  local cfg = ns.cfg or {}
  if IsInInstance then
    local inInstance, instanceType = IsInInstance()
    if instanceType == "pvp" or instanceType == "arena" then return false end
    if cfg.onlyInstances and not inInstance then return false end
    if cfg.raidOnly and instanceType ~= "raid" then return false end  -- ignore 5-man dungeons
  end
  if cfg.combatOnly and InCombatLockdown and not InCombatLockdown() then
    -- still allow env deaths mid-pull; combatOnly only gates non-combat world deaths
    if not TR.pull then return false end
  end
  return true
end

function TR.OnCombatLog()
  local info, ts = readEvent()
  if not info then return end   -- subevent we don't track (no allocation happened)
  local se = info.subevent
  if se == "SPELL_DAMAGE" or se == "SWING_DAMAGE" or se == "RANGE_DAMAGE" or se == "SPELL_PERIODIC_DAMAGE" then
    if info.destName then
      local spell = info.spell or (se == "SWING_DAMAGE" and "Melee") or "?"
      TR.RecordDamage(TR.buffer, info.destName, info.sourceName or "?", spell, ts)
      if info.destIsPlayer and TR.killcam then
        ns.Killcam.Record(TR.killcam, info.destName,
          { t = ts, kind = "dmg", source = info.sourceName or "?", spell = spell, amount = info.amount })
      end
    end
    return
  end
  if (se == "SPELL_HEAL" or se == "SPELL_PERIODIC_HEAL") and info.destIsPlayer and TR.killcam then
    ns.Killcam.Record(TR.killcam, info.destName,
      { t = ts, kind = "heal", source = info.sourceName or "?", spell = info.spell or "Heal", amount = info.amount })
    return
  end
  if se == "SPELL_CAST_SUCCESS" and info.sourceIsPlayer and info.sourceName and TR.killcam then
    ns.Killcam.Record(TR.killcam, info.sourceName,
      { t = ts, kind = "cast", source = info.sourceName, spell = info.spell or "?" })
    return
  end
  if se == "ENVIRONMENTAL_DAMAGE" then
    -- env damage (fall/lava/fire) is NOT a death -- it fires on every hit taken. Record it
    -- as the last-hit cause so a lethal one is attributed when UNIT_DIED fires; never a death.
    if info.destName then
      local envName = ENV[info.envType] or info.envType or "Environment"
      TR.RecordDamage(TR.buffer, info.destName, "Environment", envName, ts, true)
      if info.destIsPlayer and TR.killcam then
        ns.Killcam.Record(TR.killcam, info.destName,
          { t = ts, kind = "dmg", source = "Environment", spell = envName, amount = info.amount })
      end
    end
    return
  end

  local partial = TR.ParseDeath(info)
  if not partial then return end
  if not trackingAllowed() then return end

  local cfg = ns.cfg or {}
  if cfg.guildOnly and not isGuildMember(partial.player) then return end

  TR.pull = TR.pull or nextPull()
  local nDeadBefore = TR.pull:OnDeath()
  local cls = ns.Classify.ClassifyDeath(nDeadBefore, TR.pull.raidSize,
    cfg.wipeThresholdPct or 50, cfg.forgiveWipeDeaths ~= false)

  local lastHit = TR.LastHit(TR.buffer, partial.player)
  local death = {
    player = partial.player,
    time = ts,
    isEnv = (lastHit and lastHit.isEnv) or false,
    envType = (lastHit and lastHit.isEnv) and lastHit.spell or nil,
    ability = (lastHit and lastHit.spell) or "Unknown",
    sourceName = (lastHit and lastHit.source) or "Unknown",
    boss = ns.Tracking.currentBoss,
    encounterID = ns.PhaseTracker and ns.PhaseTracker.currentEncounterID or nil,
    phaseIndex = (ns.PhaseTracker and ns.PhaseTracker.currentPhaseIndex) or 1,
    phase = ns.PhaseTracker and ns.PhaseTracker.currentPhase or nil,
    pullId = (TR.pull and TR.pull.id) or 1,
    classification = cls,
    zone = (GetRealZoneText and GetRealZoneText()) or nil,
    killcam = ns.Killcam.Snapshot(TR.killcam, partial.player, ts),
  }

  if ns.DB.RecordDeath(ns.db.store, TR.raidId, death, (GetTime and GetTime()) or nil) then
    if TR.pull then TR.pull.died[death.player] = true end
    ns.Log("debug", "death: " .. tostring(death.player) .. " <- " .. tostring(death.ability) .. " [" .. tostring(death.classification) .. "]")
    local raid = ns.db.store.raids[TR.raidId]
    if raid and not raid.startTime then raid.startTime = death.time end
    if raid and not raid.zone then raid.zone = (GetRealZoneText and GetRealZoneText()) or nil end
    local board = ns.DB.LeaderboardTonight(ns.db.store, TR.raidId)
    if ns.Announce then ns.Announce.OnDeath(death, board) end
    local newLeader = ns.Streak.DetectLeadChange(TR.leader, board)
    if newLeader and ns.Announce then ns.Announce.OnComboBreaker(newLeader, board) end
    TR.leader = board[1] and board[1].player or TR.leader
    -- death-count milestone for this player tonight
    if ns.Milestones and ns.Announce then
      local myCount = 0
      for _, b in ipairs(board) do if b.player == death.player then myCount = b.deaths end end
      local crossed = ns.Milestones.Thresholds(myCount - 1, myCount)
      if #crossed > 0 then ns.Announce.OnMilestone(death.player, crossed) end
      -- all-time achievement unlocks
      if ns.Achievements then
        TR.earned = TR.earned or {}
        local cur = ns.Achievements.For(ns.db.store.allTime[death.player])
        -- First sighting this session: seed silently so already-earned achievements
        -- aren't re-announced; only announce unlocks that happen later tonight.
        if TR.earned[death.player] ~= nil then
          local newOnes = ns.Milestones.NewAchievements(TR.earned[death.player], cur)
          if #newOnes > 0 then ns.Announce.OnAchievement(death.player, newOnes) end
        end
        local set = {}
        for _, a in ipairs(cur) do set[a.id] = true end
        TR.earned[death.player] = set
      end
    end
    if ns.Sync then ns.Sync.Broadcast(death) end
    if ns.UI then ns.UI.Refresh() end
  end
end

ns.OnInit(function()
  ns.db.store = ns.db.store or ns.DB.NewStore()
  ns.DB.Dedupe(ns.db.store)              -- collapse duplicate deaths earlier builds accumulated
  ns.DB.PurgeLegacyEnvDeaths(ns.db.store) -- drop phantom fall/lava "deaths" from the old bug
  TR.ResolveStoredSpells(ns.db.store)    -- turn old bare-number abilities into names/Unknown
  TR.StartSession()
  local f = CreateFrame("Frame")
  f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  f:RegisterEvent("ENCOUNTER_START")     -- fires in TBC Classic for raid bosses
  f:RegisterEvent("ENCOUNTER_END")
  f:RegisterEvent("PLAYER_REGEN_DISABLED") -- entering combat (trash + fallback)
  f:RegisterEvent("PLAYER_REGEN_ENABLED")  -- leaving combat
  f:RegisterEvent("PLAYER_ENTERING_WORLD") -- instance enter / reload / login: rebucket the raid
  f:SetScript("OnEvent", ns.Debug.Guard("Tracking.OnEvent", function(_, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
      TR.OnCombatLog()
    elseif event == "PLAYER_ENTERING_WORLD" then
      TR.ResolveRaidId()
    elseif event == "ENCOUNTER_START" then
      local _, encounterName = ...
      TR.currentBoss = encounterName
      TR.pull = nextPull()
      TR.pull.fromEncounter = true
    elseif event == "ENCOUNTER_END" then
      local _, encName, _, _, success = ...
      if TR.pull then TR.pull.success = success end
      if success == 0 and ns.Banner then ns.Banner.FireWipe(TR.currentBoss) end
      TR.currentBoss = nil
      if TR.pull and TR.streak then
        local diers = {}
        for p in pairs(TR.pull.died) do diers[#diers+1] = p end
        local fired = ns.Streak.RecordPull(TR.streak, diers, (ns.cfg and ns.cfg.streakThreshold) or 3)
        if ns.Announce and #fired > 0 then ns.Announce.OnStreak(fired, TR.streak) end
      end
      if ns.Milestones and ns.Announce and success == 1 and TR.pull then
        local died = false
        for _ in pairs(TR.pull.died) do died = true; break end
        if ns.Milestones.CleanPull(died and 1 or 0, true) then
          ns.Announce.OnSurvival("Flawless. Nobody hit the floor on " .. tostring(encName) .. ".")
        end
      end
      TR.pull = nil
    elseif event == "PLAYER_REGEN_DISABLED" then
      -- Start a pull on combat only if a boss encounter didn't already start one.
      if not TR.pull then TR.pull = nextPull() end
    elseif event == "PLAYER_REGEN_ENABLED" then
      -- End combat-based pulls; leave encounter pulls to ENCOUNTER_END.
      if TR.pull and not TR.pull.fromEncounter then
        if TR.streak then
          local diers = {}
          for p in pairs(TR.pull.died) do diers[#diers+1] = p end
          local fired = ns.Streak.RecordPull(TR.streak, diers, (ns.cfg and ns.cfg.streakThreshold) or 3)
          if ns.Announce and #fired > 0 then ns.Announce.OnStreak(fired, TR.streak) end
        end
        TR.pull = nil
      end
    end
  end))
end)
