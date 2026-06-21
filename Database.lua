local _, ns = ...
ns = ns or __AGNB_NS
ns.DB = ns.DB or {}
local DB = ns.DB

-- Session-only de-dup index (NOT persisted): each raid table -> { "player\0second" = true }.
-- Weak keys so when a raid/store is dropped (e.g. demo cleared) its index is freed too.
local seenIndex = setmetatable({}, { __mode = "k" })
-- Receipt-time index (also session-only): raid -> { player = { t = LOCAL time, d = death } }.
-- The death's stored timestamp is the recording client's clock, and PC clocks are skewed, so
-- a synced copy's stamp can land seconds from the local copy's -- past any time window. But
-- both copies of one death ARRIVE at this client within a couple seconds of each other, so we
-- also dedup by LOCAL receipt time (immune to clock skew). RECV_WINDOW < the fastest possible
-- re-death (battle-rez) so it never merges two real deaths.
local recvIndex = setmetatable({}, { __mode = "k" })
local idIndex = setmetatable({}, { __mode = "k" })   -- raid -> { [death.id] = storedDeath }
local RECV_WINDOW = 5
-- Dedup the same death seen from different sources (own combat log, a synced copy from
-- another broadcaster, a catch-up snapshot after /reload). Those copies carry timestamps
-- that differ by sub-second up to ~1s and can STRADDLE a second boundary, so a single
-- whole-second key still let some through. Mark/check a +-1 second window instead. A player
-- can't die twice within ~2s, so this window never merges genuinely distinct deaths.
local function deathSec(d) return math.floor((d.time or 0)) end
local function markSeen(seen, player, sec)
  seen[player .. "\0" .. (sec - 1)] = true
  seen[player .. "\0" .. sec] = true
  seen[player .. "\0" .. (sec + 1)] = true
end
local function isSeen(seen, player, sec)
  return seen[player .. "\0" .. (sec - 1)] or seen[player .. "\0" .. sec] or seen[player .. "\0" .. (sec + 1)]
end

function DB.NewStore()
  return { allTime = {}, raids = {}, settings = {}, bets = {} }
end

-- ----- betting win/loss record (top winners/losers) -----
-- Record a settled bet for `player`: won (bool) and the net gold change (+won / -lost).
function DB.RecordBetResult(store, player, won, netDelta)
  store.bets = store.bets or {}
  local rec = store.bets[player] or { w = 0, l = 0, net = 0 }
  if won then rec.w = rec.w + 1 else rec.l = rec.l + 1 end
  rec.net = rec.net + (netDelta or 0)
  store.bets[player] = rec
end

-- All bettors sorted by net gold (descending), tie-broken by name. The top of the
-- list are the biggest winners; the tail, the biggest losers.
function DB.BetLeaderboard(store)
  local out = {}
  for player, rec in pairs(store.bets or {}) do
    out[#out + 1] = { player = player, w = rec.w, l = rec.l, net = rec.net }
  end
  table.sort(out, function(a, b)
    if a.net ~= b.net then return a.net > b.net end
    return a.player < b.player
  end)
  return out
end

local function ensurePlayer(store, player)
  local p = store.allTime[player]
  if not p then
    p = { deaths = 0, wipeDeaths = 0, environment = 0, byAbility = {}, byBoss = {},
          byCause = {}, lastDeath = 0, firstSeen = nil }
    store.allTime[player] = p
  end
  return p
end

local function ensureRaid(store, raidId)
  local r = store.raids[raidId]
  if not r then
    r = { startTime = nil, zone = nil, deaths = {}, pulls = {} }
    store.raids[raidId] = r
  end
  return r
end

local function applyAllTime(store, death)
  local p = ensurePlayer(store, death.player)
  p.firstSeen = p.firstSeen or death.time
  p.lastDeath = math.max(p.lastDeath, death.time)
  if death.classification == "wipeCascade" then
    p.wipeDeaths = p.wipeDeaths + 1
  else
    p.deaths = p.deaths + 1
    if death.ability then p.byAbility[death.ability] = (p.byAbility[death.ability] or 0) + 1 end
    if death.boss then p.byBoss[death.boss] = (p.byBoss[death.boss] or 0) + 1 end
    -- coherent (spell, caster) pair so all-time shows the player's real nemesis
    -- combo, not an independent most-spell + most-mob that never co-occurred.
    p.byCause = p.byCause or {}
    local key = (death.ability or "?") .. "\31" .. (death.sourceName or "?")
    p.byCause[key] = (p.byCause[key] or 0) + 1
    if death.isEnv then p.environment = p.environment + 1 end
  end
end

-- Returns true if recorded, false if it's a duplicate. `now` (optional, GetTime() from the
-- caller) enables the clock-skew-proof receipt-time dedup; without it only the timestamp
-- window applies (used by the headless tests).
function DB.RecordDeath(store, raidId, death, now)
  local raid = ensureRaid(store, raidId)
  local seen = seenIndex[raid]
  if not seen then
    seen = {}
    for _, d in ipairs(raid.deaths) do markSeen(seen, d.player or "?", deathSec(d)) end
    seenIndex[raid] = seen
  end
  local player, sec = death.player or "?", deathSec(death)

  -- ----- stable-id dedup (primary, clock-independent) -----
  if death.id then
    local ids = idIndex[raid]
    if not ids then
      ids = {}
      for _, d in ipairs(raid.deaths) do if d.id then ids[d.id] = d end end
      idIndex[raid] = ids
    end
    local existing = ids[death.id]
    if existing then
      -- already have this exact death; adopt a killcam the stored copy lacks, then drop.
      if death.killcam and not existing.killcam then existing.killcam = death.killcam end
      return false
    end
    -- new id, but a clock-skew-free local observation of the same death may already be stored
    -- without an id (we saw it on the combat log before the broadcast arrived). Converge: stamp
    -- the existing record with this id instead of adding a duplicate.
    if now then
      local rv = recvIndex[raid]
      local prev = rv and rv[player]
      if prev and prev.d and not prev.d.id and (now - prev.t) < RECV_WINDOW then
        prev.d.id = death.id
        ids[death.id] = prev.d
        if death.killcam and not prev.d.killcam then prev.d.killcam = death.killcam end
        -- note: rv[player] is intentionally not refreshed here -- the converged death now has
        -- an id, so every later copy of it takes the id branch above (never the heuristic path).
        return false
      end
    end
    ids[death.id] = death
    markSeen(seen, player, sec)
    raid.deaths[#raid.deaths + 1] = death
    if now then local rv = recvIndex[raid]; if not rv then rv = {}; recvIndex[raid] = rv end; rv[player] = { t = now, d = death } end
    if not raid.excludeAllTime then applyAllTime(store, death) end
    return true
  end

  -- ----- heuristic dedup (fallback for id-less records: local pre-broadcast / old clients) -----
  if isSeen(seen, player, sec) then return false end
  local rv
  if now then
    rv = recvIndex[raid]; if not rv then rv = {}; recvIndex[raid] = rv end
    local prev = rv[player]
    if prev and (now - prev.t) < RECV_WINDOW then
      if death.killcam and prev.d and not prev.d.killcam then prev.d.killcam = death.killcam end
      return false
    end
  end
  markSeen(seen, player, sec)
  raid.deaths[#raid.deaths + 1] = death
  if rv then rv[player] = { t = now, d = death } end
  if not raid.excludeAllTime then applyAllTime(store, death) end
  return true
end

-- Sort helper: array of {key,count,...} descending by count, tie-broken by key.
local function sortDesc(arr)
  table.sort(arr, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return tostring(a.sortKey) < tostring(b.sortKey)
  end)
  return arr
end

function DB.LeaderboardTonight(store, raidId)
  local raid = store.raids[raidId]
  local out = {}
  if not raid then return out end
  local agg = {}  -- player -> {deaths, causes={ability=n}, sources={src=n}}
  for _, d in ipairs(raid.deaths) do
    if d.classification ~= "wipeCascade" then
      local a = agg[d.player]
      if not a then a = { deaths = 0, causes = {}, sources = {} }; agg[d.player] = a end
      a.deaths = a.deaths + 1
      if d.ability then a.causes[d.ability] = (a.causes[d.ability] or 0) + 1 end
      if d.sourceName then a.sources[d.sourceName] = (a.sources[d.sourceName] or 0) + 1 end
    end
  end
  local function topKey(map)
    local key, n = nil, 0
    for k, v in pairs(map) do
      if v > n or (v == n and (not key or tostring(k) < tostring(key))) then key, n = k, v end
    end
    return key
  end
  for player, a in pairs(agg) do
    out[#out+1] = { player = player, deaths = a.deaths, topCause = topKey(a.causes),
                    topSource = topKey(a.sources), count = a.deaths, sortKey = player }
  end
  return sortDesc(out)
end

local function topKey(map)
  local key, n = nil, 0
  for k, v in pairs(map or {}) do
    if v > n or (v == n and (not key or tostring(k) < tostring(key))) then key, n = k, v end
  end
  return key
end

function DB.LeaderboardAllTime(store)
  local out = {}
  for player, p in pairs(store.allTime) do
    if p.deaths > 0 then
      -- nemesis = the most frequent (spell, caster) pair this player has died to.
      -- Falls back to the old independent modes for data recorded before byCause.
      local cause, source
      local pair = topKey(p.byCause)
      if pair then cause, source = pair:match("^(.-)\31(.*)$") end
      out[#out+1] = { player = player, deaths = p.deaths, count = p.deaths, sortKey = player,
                      topCause = cause or topKey(p.byAbility),
                      topSource = source or topKey(p.byBoss) }
    end
  end
  return sortDesc(out)
end

-- Deadliest abilities aggregated across every raid (with most-frequent caster).
function DB.AbilityBoardAllTime(store)
  local agg = {}
  for _, raid in pairs(store.raids) do
   if not raid.excludeAllTime then
    for _, d in ipairs(raid.deaths) do
      if d.classification ~= "wipeCascade" and d.ability then
        local a = agg[d.ability]
        if not a then a = { count = 0, sources = {} }; agg[d.ability] = a end
        a.count = a.count + 1
        local s = d.sourceName or "Unknown"
        a.sources[s] = (a.sources[s] or 0) + 1
      end
    end
   end
  end
  local out = {}
  for ability, a in pairs(agg) do
    out[#out+1] = { ability = ability, count = a.count, topSource = topKey(a.sources), sortKey = ability }
  end
  return sortDesc(out)
end

-- Most-recent deaths first, capped to `limit`. raidId scope.
function DB.DeathLog(store, raidId, limit)
  local raid = store.raids[raidId]
  local out = {}
  if not raid then return out end
  limit = limit or 50
  local d = raid.deaths
  for i = #d, math.max(1, #d - limit + 1), -1 do out[#out + 1] = d[i] end
  return out
end

-- Most-recent deaths across all raids first, capped to `limit`.
function DB.DeathLogAllTime(store, limit)
  limit = limit or 50
  local all, keys = {}, {}
  for k in pairs(store.raids) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    if not store.raids[k].excludeAllTime then
      for _, d in ipairs(store.raids[k].deaths) do all[#all + 1] = d end
    end
  end
  local out = {}
  for i = #all, math.max(1, #all - limit + 1), -1 do out[#out + 1] = all[i] end
  return out
end

function DB.AbilityBoard(store, raidId)
  local raid = store.raids[raidId]
  local out, agg = {}, {}
  if not raid then return out end
  for _, d in ipairs(raid.deaths) do
    if d.classification ~= "wipeCascade" and d.ability then
      local a = agg[d.ability]
      if not a then a = { count = 0, sources = {} }; agg[d.ability] = a end
      a.count = a.count + 1
      local src = d.sourceName or "Unknown"
      a.sources[src] = (a.sources[src] or 0) + 1
    end
  end
  for ability, a in pairs(agg) do
    local topSource, topN = nil, -1
    local keys = {}
    for s in pairs(a.sources) do keys[#keys+1] = s end
    table.sort(keys)
    for _, s in ipairs(keys) do
      if a.sources[s] > topN then topSource, topN = s, a.sources[s] end
    end
    out[#out+1] = { ability = ability, count = a.count, topSource = topSource, sortKey = ability }
  end
  return sortDesc(out)
end

-- Drop the heavy killcam timelines from deaths in every raid except `keepRaidId` (the
-- current session's raid), so SavedVariables doesn't accumulate a per-death timeline
-- across a whole season. Stats/aggregates are unaffected (they never read killcam).
-- Returns how many timelines were stripped.
function DB.PruneKillcams(store, keepRaidId)
  local stripped = 0
  for raidId, raid in pairs((store and store.raids) or {}) do
    if raidId ~= keepRaidId then
      for _, d in ipairs(raid.deaths or {}) do
        if d.killcam then d.killcam = nil; stripped = stripped + 1 end
      end
    end
  end
  return stripped
end

-- One-time cleanup for data that earlier builds duplicated. Two passes, both order-based
-- so they survive cross-client CLOCK SKEW (a synced copy carries another PC's clock, which
-- a time window can't reconcile): drop a death if it's within +-1s of an earlier one for
-- the same player, OR if it is identical (player+ability+source) to the immediately
-- preceding kept death -- the duplicates always land consecutively in insertion order.
-- Rebuilds all-time. Safe to run every load (idempotent).
local function deathSig(d) return (d.player or "?") .. "\0" .. tostring(d.ability) .. "\0" .. tostring(d.sourceName) end
function DB.Dedupe(store)
  local removed = 0
  for _, raid in pairs((store and store.raids) or {}) do
    local seen, kept = {}, {}
    for _, d in ipairs(raid.deaths or {}) do
      local player, sec = d.player or "?", deathSec(d)
      local prev = kept[#kept]
      -- consecutive same-player rows that are either identical (player+ability+source) OR
      -- differ only in having a killcam (the local copy carries one, the synced copy doesn't)
      -- are the same death from two sources -- collapse them, keeping the killcam.
      local prevDup = prev and (prev.player or "?") == player
        and (deathSig(prev) == deathSig(d) or ((prev.killcam ~= nil) ~= (d.killcam ~= nil)))
      if isSeen(seen, player, sec) or prevDup then
        removed = removed + 1
        if prev and d.killcam and not prev.killcam then prev.killcam = d.killcam end
      else
        markSeen(seen, player, sec); kept[#kept + 1] = d
      end
    end
    raid.deaths = kept
  end
  if removed > 0 then DB.RebuildAllTime(store) end
  return removed
end

-- Remove the phantom environmental "deaths" an earlier build created -- it logged EVERY
-- fall/lava/fire DAMAGE event as a death (so surviving a fall left a death in the log). The
-- fixed code records a real env death with sourceName "Environment"; the buggy ones carry a
-- mob/envType source. So drop isEnv deaths whose source isn't "Environment". Safe to run every
-- load: legitimately-recorded env deaths are kept. Rebuilds all-time when it changes anything.
function DB.PurgeLegacyEnvDeaths(store)
  local removed = 0
  for _, raid in pairs((store and store.raids) or {}) do
    local kept = {}
    for _, d in ipairs(raid.deaths or {}) do
      if d.isEnv and d.sourceName ~= "Environment" then removed = removed + 1
      else kept[#kept + 1] = d end
    end
    raid.deaths = kept
  end
  if removed > 0 then DB.RebuildAllTime(store) end
  return removed
end

-- Recompute all-time aggregates from scratch from every recorded death, skipping raids
-- flagged excludeAllTime (pugs you don't want in your career stats).
function DB.RebuildAllTime(store)
  store.allTime = {}
  for _, raid in pairs(store.raids) do
    if not raid.excludeAllTime then
      for _, death in ipairs(raid.deaths) do
        applyAllTime(store, death)
      end
    end
  end
end

-- Mark a raid in/out of all-time (e.g. tag a pug). Recomputes all-time. Returns the new flag.
function DB.SetRaidExcluded(store, raidId, excluded)
  local raid = store and store.raids and store.raids[raidId]
  if not raid then return nil end
  raid.excludeAllTime = excluded or nil
  DB.RebuildAllTime(store)
  return raid.excludeAllTime == true
end

-- Remove the most-recent pull's deaths from a raid and rebuild all-time.
-- Returns (removedCount, pullId).
function DB.VoidLastPull(store, raidId)
  local raid = store.raids[raidId]
  if not raid or #raid.deaths == 0 then return 0, 0 end
  local maxPull = 0
  for _, d in ipairs(raid.deaths) do maxPull = math.max(maxPull, d.pullId or 0) end
  local kept, removed = {}, 0
  for _, d in ipairs(raid.deaths) do
    if (d.pullId or 0) == maxPull then removed = removed + 1 else kept[#kept + 1] = d end
  end
  raid.deaths = kept
  seenIndex[raid] = nil   -- voided keys removed: rebuild the de-dup index on next record
  DB.RebuildAllTime(store)
  return removed, maxPull
end

-- Remove every death whose time is within [t0, t1] from a raid and rebuild
-- all-time aggregates. Returns the removed count. Used by the admin ignore-pull
-- broadcast (windows are cross-client-stable epoch death.time values).
function DB.VoidWindow(store, raidId, t0, t1)
  local raid = store.raids[raidId]
  if not raid then return 0 end
  local kept, removed = {}, 0
  for _, d in ipairs(raid.deaths) do
    local t = d.time or 0
    if t >= t0 and t <= t1 then removed = removed + 1 else kept[#kept + 1] = d end
  end
  raid.deaths = kept
  seenIndex[raid] = nil   -- voided keys removed: rebuild the de-dup index on next record
  DB.RebuildAllTime(store)
  return removed
end
