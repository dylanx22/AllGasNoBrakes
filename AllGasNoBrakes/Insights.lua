local _, ns = ...
ns = ns or __AGNB_NS
ns.Insights = ns.Insights or {}
local I = ns.Insights

-- max-by-count over a {key=count} map, deterministic tie-break by key. Returns key, count.
local function topKey(map)
  local k, n = nil, 0
  for key, v in pairs(map) do
    if v > n or (v == n and (not k or tostring(key) < tostring(k))) then k, n = key, v end
  end
  return k, n
end

-- Deaths per phase for one curated boss. Returns array { {name, index, count, deadliest} }
-- or nil if the boss isn't curated (single-phase). Counts non-cascade deaths only.
function I.PhaseSplit(deaths, boss, encounterID)
  local def = ns.Phases.For(encounterID)
  if not (def and def.phases) then return nil end
  local n = #def.phases
  local counts = {}
  for i = 1, n do counts[i] = 0 end
  for _, d in ipairs(deaths) do
    if d.boss == boss and d.classification ~= "wipeCascade" then
      local idx = d.phaseIndex or 1
      if idx < 1 then idx = 1 elseif idx > n then idx = n end
      counts[idx] = counts[idx] + 1
    end
  end
  local maxc, maxi = -1, 1
  for i = 1, n do if counts[i] > maxc then maxc, maxi = counts[i], i end end
  local out = {}
  for i = 1, n do
    out[i] = { name = def.phases[i], index = i, count = counts[i], deadliest = (i == maxi and maxc > 0) }
  end
  return out
end

-- Group tonight's (non-cascade) deaths by boss. Each entry: boss, encounterID, deaths,
-- topCause (ability), topSource (mob), feeder + feederCount, and a phase split
-- (nil for uncurated bosses). Sorted by deaths desc, boss name asc.
function I.ByBoss(deaths)
  local groups, order = {}, {}
  for _, d in ipairs(deaths) do
    if d.classification ~= "wipeCascade" then
      local key = d.boss or "Unknown"
      local g = groups[key]
      if not g then
        g = { boss = key, encounterID = d.encounterID, deaths = 0, causes = {}, sources = {}, feeders = {} }
        groups[key] = g; order[#order + 1] = key
      end
      g.deaths = g.deaths + 1
      if d.ability then g.causes[d.ability] = (g.causes[d.ability] or 0) + 1 end
      if d.sourceName then g.sources[d.sourceName] = (g.sources[d.sourceName] or 0) + 1 end
      if d.player then g.feeders[d.player] = (g.feeders[d.player] or 0) + 1 end
    end
  end
  local out = {}
  for _, key in ipairs(order) do
    local g = groups[key]
    local feeder, fc = topKey(g.feeders)
    out[#out + 1] = {
      boss = g.boss, encounterID = g.encounterID, deaths = g.deaths,
      topCause = (topKey(g.causes)), topSource = (topKey(g.sources)),
      feeder = feeder, feederCount = fc,
      phases = I.PhaseSplit(deaths, g.boss, g.encounterID),
    }
  end
  table.sort(out, function(a, b)
    if a.deaths ~= b.deaths then return a.deaths > b.deaths end
    return a.boss < b.boss
  end)
  return out
end

-- Deaths in a pull, time-ordered, each with seconds since pull start. pull is a
-- { pullId, startTime } record (e.g. from ns.Book.RecentPulls). cause = ability · mob.
function I.PullTimeline(deaths, pull)
  local out = {}
  for _, d in ipairs(deaths) do
    if d.pullId == pull.pullId then
      out[#out + 1] = {
        player = d.player, time = d.time,
        cause = (d.ability or "?") .. (d.sourceName and (" \194\183 " .. d.sourceName) or ""),
        offset = (d.time or 0) - (pull.startTime or 0),
      }
    end
  end
  table.sort(out, function(a, b) return (a.time or 0) < (b.time or 0) end)
  return out
end
