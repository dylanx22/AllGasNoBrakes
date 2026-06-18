local _, ns = ...
ns = ns or __AGNB_NS
ns.Ledger = ns.Ledger or {}
local L = ns.Ledger

-- Default title ladder: {threshold, title} ascending by threshold.
L.ladder = {
  { 0,  "The Immortal" },
  { 1,  "Has a Pulse" },
  { 5,  "Speed Bump" },
  { 10, "Crash Test Dummy" },
  { 20, "Frequent Flyer" },
  { 35, "Professional Faceplanter" },
  { 50, "One With The Floor" },
}

-- counts: { player = deaths }. Returns { pot, owed={player=gold}, winner }.
function L.Settle(counts, buyIn)
  buyIn = buyIn or 1
  local pot, owed = 0, {}
  local winner, fewest = nil, math.huge
  -- deterministic winner tie-break by name
  local names = {}
  for p in pairs(counts) do names[#names+1] = p end
  table.sort(names)
  for _, p in ipairs(names) do
    local n = counts[p]
    owed[p] = n * buyIn
    pot = pot + n * buyIn
    if n < fewest then fewest, winner = n, p end
  end
  return { pot = pot, owed = owed, winner = winner }
end

-- Funny one-off awards for the end-of-raid podium's top 3, so they don't all read
-- the same death-count title. Assigned deterministically per player (stable across
-- re-opens) and de-duplicated across the three slots.
L.PODIUM_AWARDS = {
  "Floor Inspector", "Durability Donor", "Gravity's Chosen", "Repair Bill Hero",
  "Professional Victim", "Faceplant Laureate", "The Human Speed Bump", "Wipe Architect",
  "Corpse Run Cardio", "Ankh Economy", "Soulstone Subscriber", "Res Sickness Veteran",
  "Crash Test Legend", "Designated Dier", "Pavement Enthusiast", "Spirit Healer's Bestie",
}

local function strhash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return h
end

-- A funny podium award for `player`, avoiding any already in `taken` (a set).
function L.PodiumAward(player, taken)
  taken = taken or {}
  local pool = L.PODIUM_AWARDS
  local n = #pool
  local start = (strhash(tostring(player)) % n) + 1
  for off = 0, n - 1 do
    local award = pool[((start - 1 + off) % n) + 1]
    if not taken[award] then return award end
  end
  return pool[start]
end

-- Largest ladder threshold <= deaths.
function L.Title(deaths, ladder)
  ladder = ladder or L.ladder
  local title = ladder[1][2]
  for _, entry in ipairs(ladder) do
    if deaths >= entry[1] then title = entry[2] else break end
  end
  return title
end

-- counts: {player=deaths}. Each non-winner owes buyIn*deaths to the winner
-- (fewest deaths, name tie-break). Returns { winner, pot, owes={player={to,amount}} }.
-- participants (optional set {player=true}): when given, ONLY those players are in
-- the pot -- the anti-prize is opt-in, so nobody is on the hook for gold unless
-- they joined. nil = everyone (legacy / pre-opt-in behavior).
function L.Settlement(counts, buyIn, participants)
  buyIn = buyIn or 1
  local names = {}
  for p in pairs(counts) do
    if not participants or participants[p] then names[#names+1] = p end
  end
  table.sort(names)
  local winner, fewest, pot = nil, math.huge, 0
  for _, p in ipairs(names) do
    pot = pot + counts[p] * buyIn
    if counts[p] < fewest then fewest, winner = counts[p], p end
  end
  local owes = {}
  for _, p in ipairs(names) do
    if p ~= winner and counts[p] > 0 then
      owes[p] = { to = winner, amount = counts[p] * buyIn }
    end
  end
  return { winner = winner, pot = pot, owes = owes }
end

-- raid: { zone, deaths = {death,...} }. Returns lowlights summary.
function L.Lowlights(raid)
  local counts, env, body = {}, {}, 0
  local abil, src = {}, {}   -- abil[ability]=n ; src[ability][source]=n
  local firstBlood, firstTime = nil, math.huge
  for _, d in ipairs(raid.deaths or {}) do
    if d.classification ~= "wipeCascade" then
      counts[d.player] = (counts[d.player] or 0) + 1
      body = body + 1
      if d.isEnv then env[d.player] = (env[d.player] or 0) + 1 end
      if d.time < firstTime then firstTime, firstBlood = d.time, d.player end
      if d.ability then
        abil[d.ability] = (abil[d.ability] or 0) + 1
        local sm = src[d.ability]; if not sm then sm = {}; src[d.ability] = sm end
        local s = d.sourceName or "Unknown"
        sm[s] = (sm[s] or 0) + 1
      end
    end
  end
  -- deterministic "max by count, tie-break by name" over a string->number map
  local function topOf(tbl)
    local best, bestN = nil, 0
    local keys = {}
    for k in pairs(tbl) do keys[#keys+1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do if tbl[k] > bestN then best, bestN = k, tbl[k] end end
    return best, bestN
  end
  local feeder, feederDeaths = topOf(counts)
  local deadliestAbility = topOf(abil)
  local deadliestSource = deadliestAbility and topOf(src[deadliestAbility]) or nil
  return {
    zone = raid.zone,
    feeder = feeder,
    feederDeaths = feederDeaths or 0,
    faceplanter = topOf(env),
    firstBlood = firstBlood,
    bodyCount = body,
    deadliestAbility = deadliestAbility,
    deadliestSource = deadliestSource,
  }
end
