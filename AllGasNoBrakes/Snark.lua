local _, ns = ...
ns = ns or __AGNB_NS
ns.Snark = ns.Snark or {}
local S = ns.Snark

S.pools = {
  death = {
    "{player} took a dirt nap, courtesy of {ability}. (death #{count})",
    "{player} has been deleted by {ability}. ({count} tonight)",
    "BRAKE CHECK: {player} ate {ability} face-first. (#{count})",
    "{player} forgot to press defensive. {ability} said thanks. (#{count})",
  },
  faceplant = {
    "{player} FACEPLANTED into the {envType}. Gravity: 1, {player}: 0.",
    "{player} discovered the {envType} the hard way.",
    "No boss required -- {player} solo'd the {envType}.",
  },
  firstblood = {
    "FIRST BLOOD: {player} opens the night by dying to {ability}. The bar is on the floor.",
    "{player} gets us started early -- dead to {ability}. Pace car is set.",
  },
  combobreaker = {
    "COMBO BREAKER: {player} seizes the death lead with {count}. New reigning champ.",
  },
}

-- Replace {token} with tokens[token] (stringified); unknown tokens => "".
function S.Fill(template, tokens)
  return (template:gsub("{(%w+)}", function(key)
    local v = tokens[key]
    if v == nil then return "" end
    return tostring(v)
  end))
end

-- Pick a template index from a pool. rng() must return a float in [0,1) like math.random();
-- when omitted, uses math.random.
function S.Pick(pool, rng)
  local n = #pool
  if n == 0 then return "" end
  local r = rng and rng() or math.random()
  local idx = math.floor(r * n) + 1
  if idx > n then idx = n end
  return pool[idx]
end

-- Build a finished line for a kind. rng optional (for deterministic tests).
function S.Line(kind, tokens, rng)
  local pool = S.pools[kind] or S.pools.death
  return S.Fill(S.Pick(pool, rng), tokens)
end
