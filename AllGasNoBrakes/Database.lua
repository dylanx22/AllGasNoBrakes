local _, ns = ...
ns = ns or __AGNB_NS
ns.DB = ns.DB or {}
local DB = ns.DB

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

-- Returns true if recorded, false if a duplicate (same player+time) already exists.
function DB.RecordDeath(store, raidId, death)
  local raid = ensureRaid(store, raidId)
  for _, existing in ipairs(raid.deaths) do
    if existing.player == death.player and existing.time == death.time then
      return false
    end
  end
  raid.deaths[#raid.deaths + 1] = death

  applyAllTime(store, death)
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
    for _, d in ipairs(store.raids[k].deaths) do all[#all + 1] = d end
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

-- Recompute all-time aggregates from scratch from every recorded death.
function DB.RebuildAllTime(store)
  store.allTime = {}
  for _, raid in pairs(store.raids) do
    for _, death in ipairs(raid.deaths) do
      applyAllTime(store, death)
    end
  end
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
  DB.RebuildAllTime(store)
  return removed
end
