local _, ns = ...
ns = ns or __AGNB_NS
ns.Book = ns.Book or {}
local B = ns.Book

-- All wager logic is pure (no WoW calls) and resolves from the shared death log,
-- so every client computes the same outcome. Commit/reveal (backed by ns.Hash)
-- binds bets; the draft seed + self-exclusion keep it un-riggable by one person.

-- ----- round state machine + commit/reveal -----
-- kind: "OU" (over/under) or "FB" (first blood). line: the O/U number (FB ignores).
function B.NewRound(raidId, pullId, kind, line)
  return { raidId = raidId, pullId = pullId, kind = kind, line = line,
           state = "OPEN", commits = {}, reveals = {} }
end

-- Accept a commitment only while OPEN, and only once per player (immutable bet).
function B.AddCommit(round, player, commitHash)
  if round.state ~= "OPEN" then return false end
  if round.commits[player] then return false end
  round.commits[player] = commitHash
  return true
end

function B.Lock(round) round.state = "LOCKED"; return round end
function B.Resolve(round, outcome) round.outcome = outcome; round.state = "RESOLVED"; return round end

-- Accept a reveal only after lock, and only if it matches the locked commitment.
function B.AddReveal(round, player, pick, nonce)
  if round.state ~= "LOCKED" and round.state ~= "RESOLVED" then return false end
  local c = round.commits[player]
  if not c then return false end
  if ns.Hash.Commit(pick, nonce, player) ~= c then return false end
  round.reveals[player] = pick
  return true
end

-- ----- Over/Under -----
-- Auto line from recent counts: median snapped to X.5 (push-proof). With no
-- history, falls back to the lowest line (default 0.5 = "anyone dies at all").
function B.AutoLine(history, fallback)
  fallback = fallback or 0.5
  if not history or #history == 0 then return fallback end
  local s = {}
  for _, v in ipairs(history) do s[#s + 1] = v end
  table.sort(s)
  local n = #s
  local med = (n % 2 == 1) and s[(n + 1) / 2] or (s[n / 2] + s[n / 2 + 1]) / 2
  return math.floor(med) + 0.5
end

-- Count this pull's (non-wipe-cascade) deaths and compare to the line. `pullId`
-- nil means `deaths` is already the pull's list (the glue filters by time window,
-- since pullId isn't a reliable cross-client key).
function B.ResolveOU(line, deaths, pullId)
  local n = 0
  for _, d in ipairs(deaths) do
    if (pullId == nil or d.pullId == pullId) and d.classification ~= "wipeCascade" then n = n + 1 end
  end
  if n > line then return "over" elseif n < line then return "under" else return "push" end
end

-- ----- First Blood -----
-- Earliest death in the pull (all classifications), ties broken by player name.
-- Returns nil if nobody died (the "no deaths" pickers win).
function B.ResolveFirstBlood(deaths, pullId)
  local best
  for _, d in ipairs(deaths) do
    if pullId == nil or d.pullId == pullId then
      if not best or d.time < best.time or (d.time == best.time and d.player < best.player) then
        best = d
      end
    end
  end
  return best and best.player or nil
end

-- The pickable list for First Blood excludes the bettor (no betting on your own
-- death -> can't suicide-pull for your own payout).
function B.FirstBloodCandidates(roster, selfName)
  local out = {}
  for _, p in ipairs(roster) do if p ~= selfName then out[#out + 1] = p end end
  return out
end

-- ----- settlement -----
-- bets: {player=pick}. Winners (pick==outcome) collect; losers each pay `stake`,
-- distributed across winners. Returns { pot, winners, owes={player={to,amount}} }.
function B.SettleRound(bets, outcome, stake)
  stake = stake or 0
  local players = {}
  for p in pairs(bets) do players[#players + 1] = p end
  table.sort(players)
  local winners, losers = {}, {}
  for _, p in ipairs(players) do
    if bets[p] == outcome then winners[#winners + 1] = p else losers[#losers + 1] = p end
  end
  local owes = {}
  if #winners > 0 then
    for i, p in ipairs(losers) do
      owes[p] = { to = winners[((i - 1) % #winners) + 1], amount = stake }
    end
  end
  return { pot = #players * stake, winners = winners, owes = owes }
end

-- Per-round NET deltas (in the smallest money unit, e.g. copper) using an EVEN
-- pari-mutuel split, so two players who won the same bet are paid the same.
-- reveals: {player=pick}. Losers each forfeit `stake`; the pot is split evenly
-- among winners, and the leftover units go one-at-a-time to winners in sorted-name
-- order. Returns {player=delta}; sum(deltas) == 0 exactly. Replaces SettleRound's
-- round-robin `owes` as the source of truth for who gained/lost what.
function B.RoundDeltas(reveals, outcome, stake)
  stake = stake or 0
  local players = {}
  for p in pairs(reveals) do players[#players + 1] = p end
  table.sort(players)
  local deltas, winners, losers = {}, {}, {}
  for _, p in ipairs(players) do
    deltas[p] = 0
    if reveals[p] == outcome then winners[#winners + 1] = p else losers[#losers + 1] = p end
  end
  if #winners == 0 or #losers == 0 or stake <= 0 then return deltas end
  local pot = #losers * stake
  for _, p in ipairs(losers) do deltas[p] = -stake end
  local base = math.floor(pot / #winners)
  local rem = pot - base * #winners
  for i, p in ipairs(winners) do
    deltas[p] = base + (i <= rem and 1 or 0)  -- winners sorted by name; first `rem` get +1 copper
  end
  return deltas
end

-- Group a raid's deaths into pulls (by local pullId) for the admin ignore-pull
-- picker. start/end are death.time (epoch) bounds so the broadcast void window is
-- cross-client stable. Most-recent pull first, capped to `limit` (default 6).
function B.RecentPulls(deaths, limit)
  limit = limit or 6
  local byPull, order = {}, {}
  for _, d in ipairs(deaths) do
    local id = d.pullId or 0
    local g = byPull[id]
    if not g then
      g = { pullId = id, boss = d.boss, startTime = d.time, endTime = d.time, count = 0 }
      byPull[id] = g; order[#order + 1] = id
    end
    if d.time < g.startTime then g.startTime = d.time end
    if d.time > g.endTime then g.endTime = d.time end
    if d.classification ~= "wipeCascade" then g.count = g.count + 1 end
    g.boss = g.boss or d.boss
  end
  local out = {}
  for _, id in ipairs(order) do out[#out + 1] = byPull[id] end
  table.sort(out, function(a, b) return a.startTime > b.startTime end)
  while #out > limit do table.remove(out) end
  return out
end

-- ----- stake validation (personal bankroll guard) -----
-- All amounts in gold. maxPct (e.g. 50) is the user's optional bankroll cap.
function B.ValidateStake(stake, playerGold, maxPct)
  if type(stake) ~= "number" or stake <= 0 then return false, "Stake must be a positive amount." end
  if stake > (playerGold or 0) then return false, "You don't have that much gold." end
  if maxPct and maxPct > 0 then
    local cap = math.floor((playerGold or 0) * maxPct / 100)
    if stake > cap then return false, "Over your " .. maxPct .. "% bankroll cap (" .. cap .. "g)." end
  end
  return true
end

-- ----- death draft (random sweepstakes, self-excluded) -----
-- A deterministic PRNG stream from the shared seed.
local function prngFromSeed(seed)
  local i = 0
  return function()
    i = i + 1
    return tonumber(ns.Hash.SHA256(seed .. ":" .. i):sub(1, 8), 16)
  end
end

-- secretsByPlayer: {player=secret|false}. false/nil = didn't reveal (excluded).
-- roster: every raider that can be drawn. Returns {participant = assignedRaider},
-- a derangement w.r.t. self (you're never assigned yourself).
function B.DraftAssign(secretsByPlayer, roster)
  local participants, filtered = {}, {}
  for p, sec in pairs(secretsByPlayer) do
    if sec then participants[#participants + 1] = p; filtered[p] = sec end
  end
  table.sort(participants)
  if #participants == 0 then return {} end

  local rnd = prngFromSeed(ns.Hash.Seed(filtered))
  local pool = {}
  for _, r in ipairs(roster) do pool[#pool + 1] = r end
  for i = #pool, 2, -1 do            -- Fisher-Yates
    local j = (rnd() % i) + 1
    pool[i], pool[j] = pool[j], pool[i]
  end

  local assign = {}
  for idx, p in ipairs(participants) do assign[p] = pool[idx] end
  -- self-exclusion: deterministically swap anyone assigned themselves
  for _, p in ipairs(participants) do
    if assign[p] == p then
      local swapped = false
      for _, q in ipairs(participants) do
        if q ~= p and assign[q] ~= p then
          assign[p], assign[q] = assign[q], assign[p]; swapped = true; break
        end
      end
      if not swapped and assign[p] == p then assign[p] = nil end  -- degenerate: refund
    end
  end
  return assign
end

-- assign: {participant=raider}. Score each by their raider's counted deaths.
function B.DraftStandings(assign, deaths)
  local byRaider = {}
  for _, d in ipairs(deaths) do
    if d.classification ~= "wipeCascade" then
      byRaider[d.player] = (byRaider[d.player] or 0) + 1
    end
  end
  local out = {}
  for participant, raider in pairs(assign) do
    out[#out + 1] = { player = participant, raider = raider, deaths = byRaider[raider] or 0 }
  end
  table.sort(out, function(a, b)
    if a.deaths ~= b.deaths then return a.deaths > b.deaths end
    return a.player < b.player
  end)
  return out
end
