local _, ns = ...
ns = ns or __AGNB_NS
ns.History = ns.History or {}
local H = ns.History

local function sortedKeys(set)
  local k = {}
  for key in pairs(set) do k[#k + 1] = key end
  table.sort(k)
  return k
end

-- Walk a raid's deaths once, collecting the shared aggregates List and Report need.
local function scan(raid)
  local zoneSet, bossSet, wipePulls, counts = {}, {}, {}, {}
  local body, first, last = 0, nil, nil
  for _, d in ipairs(raid.deaths or {}) do
    local z = d.zone or raid.zone
    if z then zoneSet[z] = true end
    if d.boss then bossSet[d.boss] = true end
    if d.classification == "wipeCascade" then
      wipePulls[d.pullId or 0] = true
    else
      body = body + 1
      counts[d.player] = (counts[d.player] or 0) + 1
    end
    local t = d.time or 0
    if not first or t < first then first = t end
    if not last or t > last then last = t end
  end
  local zones = sortedKeys(zoneSet)
  if #zones == 0 and raid.zone then zones = { raid.zone } end
  local wipeCount = 0
  for _ in pairs(wipePulls) do wipeCount = wipeCount + 1 end
  return {
    zones = zones, bossCount = #sortedKeys(bossSet), wipeCount = wipeCount,
    bodyCount = body, counts = counts,
    duration = (first and last) and (last - first) or 0,
    startTime = raid.startTime or first or 0,
  }
end

-- One row per recorded raid, newest-first.
function H.List(store)
  local out = {}
  for raidId, raid in pairs((store and store.raids) or {}) do
    local s = scan(raid)
    out[#out + 1] = {
      raidId = raidId, startTime = s.startTime, zones = s.zones,
      bodyCount = s.bodyCount, wipeCount = s.wipeCount,
      bossCount = s.bossCount, duration = s.duration,
    }
  end
  table.sort(out, function(a, b) return (a.startTime or 0) > (b.startTime or 0) end)
  return out
end

-- Structured per-night report, or nil if the raid id is unknown.
function H.Report(store, raidId, buyIn)
  local raid = store and store.raids and store.raids[raidId]
  if not raid then return nil end
  buyIn = buyIn or 1
  local s = scan(raid)
  local ledger = ns.Ledger.Settlement(s.counts, buyIn)
  return {
    raidId = raidId,
    meta = {
      startTime = s.startTime, zones = s.zones, duration = s.duration,
      wipeCount = s.wipeCount, bossCount = s.bossCount, bodyCount = s.bodyCount,
      pot = ledger.pot, winner = ledger.winner,
    },
    lowlights = ns.Ledger.Lowlights(raid),
    perBoss = ns.Insights.ByBoss(raid.deaths or {}),
    ledger = ledger,
  }
end
