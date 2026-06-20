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

-- Group a raid's deaths into pulls by TIME-GAP clustering (deaths more than `gapSec`
-- apart begin a new pull), for the admin ignore-pull picker + the pull-timeline view.
-- NOT by pullId: synced deaths carry the broadcaster's LOCAL pullId, so pullId isn't a
-- cross-client-stable key (it fragmented pulls across clients). start/end are death.time
-- (epoch) bounds, so the void window is cross-client stable. Most-recent pull first,
-- capped to `limit` (default 6).
function B.RecentPulls(deaths, limit, gapSec)
  limit = limit or 6
  gapSec = gapSec or 90
  local sorted = {}
  for _, d in ipairs(deaths) do sorted[#sorted + 1] = d end
  table.sort(sorted, function(a, b) return (a.time or 0) < (b.time or 0) end)
  local out, cur = {}, nil
  for _, d in ipairs(sorted) do
    local t = d.time or 0
    if not cur or (t - cur.endTime) > gapSec then
      cur = { boss = d.boss, startTime = t, endTime = t, count = 0 }
      out[#out + 1] = cur
    end
    cur.endTime = t
    if d.classification ~= "wipeCascade" then cur.count = cur.count + 1 end
    cur.boss = cur.boss or d.boss
  end
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

-- ===== Hot Seat (per-pull head-to-head survival betting) =====

-- Number of spotlight targets for a roster: ~1 per 6 raiders, clamped to [2,5].
function B.TargetCount(rosterSize)
  local n = math.floor((rosterSize or 0) / 6 + 0.5)
  if n < 2 then n = 2 elseif n > 5 then n = 5 end
  return n
end

-- Probability the player dies this pull, RELATIVE to the present raid's death
-- counts (we have no true per-pull denominator). avg=0 -> pick'em. Clamped
-- [0.10,0.80] so odds/stakes stay sane (favorite never risks > 4x the base).
function B.SurvivalLine(deathCounts, roster, player)
  deathCounts = deathCounts or {}
  local total, n = 0, 0
  for _, name in ipairs(roster or {}) do
    total = total + (deathCounts[name] or 0); n = n + 1
  end
  if n == 0 or total == 0 then return 0.5 end
  local avg = total / n
  local p = 0.5 * ((deathCounts[player] or 0) / avg)
  if p < 0.10 then p = 0.10 elseif p > 0.80 then p = 0.80 end
  return p
end

-- Per-raid counted (non-cascade) death counts for one player, only for raids they were
-- present in (had any death record), sorted by raid key for cross-client determinism.
-- Feeds Book.AutoLine to set the Raid Hot Seat line from recent history.
function B.SubjectRaidCounts(store, subject)
  local out = {}
  local keys = {}
  for k in pairs((store and store.raids) or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local raid = store.raids[k]
    local counted, present = 0, false
    for _, d in ipairs((raid and raid.deaths) or {}) do
      if d.player == subject then
        present = true
        if d.classification ~= "wipeCascade" then counted = counted + 1 end
      end
    end
    if present then out[#out + 1] = counted end
  end
  return out
end

local function round5(x) return math.floor(x / 5 + 0.5) * 5 end

-- American moneyline string for a win probability p.
function B.OddsFromProb(p)
  if p == 0.5 then return "EVEN" end
  if p > 0.5 then return "-" .. round5(100 * p / (1 - p)) end
  return "+" .. round5(100 * (1 - p) / p)
end

-- Up to n distinct targets from the roster, deterministic from seed. Roster is
-- sorted first so the slate is independent of receipt order.
function B.RollTargets(seed, roster, n)
  local pool = {}
  for _, name in ipairs(roster or {}) do pool[#pool + 1] = name end
  table.sort(pool)
  local rnd = prngFromSeed(tostring(seed))
  for i = #pool, 2, -1 do            -- Fisher-Yates
    local j = (rnd() % i) + 1
    pool[i], pool[j] = pool[j], pool[i]
  end
  local out = {}
  for i = 1, math.min(n or 0, #pool) do out[i] = pool[i] end
  return out
end

-- One target for a player, deterministic from seed+player (roster-independent so
-- every client can validate any player's deal). Self-deal is allowed; the caller
-- restricts a self-dealt player to the "survives" side.
function B.DealTarget(seed, targets, player)
  if not targets or #targets == 0 then return nil end
  local h = tonumber(ns.Hash.SHA256(tostring(seed) .. ":" .. tostring(player)):sub(1, 8), 16)
  return targets[(h % #targets) + 1]
end

-- Did the target survive this pull? Literal: ANY recorded death (cascade or not)
-- means "dies". `deaths` is the pull's windowed list.
function B.ResolveHotSeat(target, deaths)
  for _, d in ipairs(deaths or {}) do
    if d.player == target then return "dies" end
  end
  return "survives"
end

-- Stake handicap from the line: the underdog stakes `base`, the favorite stakes
-- base*(pFav/pDog). Winner takes the pot, so the realized odds equal the line.
function B.HotSeatStakes(pDie, base)
  base = base or 0
  if pDie == 0.5 then return { favStake = base, dogStake = base, favSide = "even" } end
  local favSide = (pDie > 0.5) and "dies" or "survives"
  local pFav = (pDie > 0.5) and pDie or (1 - pDie)
  local pDog = 1 - pFav
  local favStake = math.floor(base * (pFav / pDog) + 0.5)
  return { favStake = favStake, dogStake = base, favSide = favSide }
end

-- Head-to-head matching + settlement for one round of Hot Seat orders.
-- Per target, pair dies-bettors with survives-bettors (sorted by name) at the
-- target's handicap; the side matching the outcome wins the opponent's stake.
-- Surplus on the longer side is unmatched (refunded). Gold deltas sum to 0.
function B.MatchHotSeat(orders, outcomes, lines, base)
  local deltas, pairs_, unmatched = {}, {}, {}
  -- bucket players by target + side
  local byTarget = {}
  local names = {}
  for player in pairs(orders) do names[#names + 1] = player end
  table.sort(names)
  for _, player in ipairs(names) do
    deltas[player] = 0
    local o = orders[player]
    local t = byTarget[o.target]
    if not t then t = { dies = {}, survives = {} }; byTarget[o.target] = t end
    t[o.side][#t[o.side] + 1] = player
  end
  -- match within each target
  local tkeys = {}
  for k in pairs(byTarget) do tkeys[#tkeys + 1] = k end
  table.sort(tkeys)
  for _, target in ipairs(tkeys) do
    local t = byTarget[target]
    local stk = B.HotSeatStakes(lines[target] or 0.5, base)
    local outcome = outcomes[target]
    -- only pair bettors when the outcome actually resolved to dies/survives; an unknown or
    -- missing outcome would otherwise fall to the else-branch below and silently pay the
    -- "survives" side. Leave both sides unmatched (no payout) instead of mis-settling.
    local nPair = (outcome == "dies" or outcome == "survives") and math.min(#t.dies, #t.survives) or 0
    for i = 1, nPair do
      local diesP, survP = t.dies[i], t.survives[i]
      -- stake per side from favSide
      local diesStake = (stk.favSide == "dies") and stk.favStake or stk.dogStake
      local survStake = (stk.favSide == "survives") and stk.favStake or stk.dogStake
      local winner, loser, amount
      if outcome == "dies" then
        winner, loser, amount = diesP, survP, survStake
      else
        winner, loser, amount = survP, diesP, diesStake
      end
      deltas[winner] = deltas[winner] + amount
      deltas[loser] = deltas[loser] - amount
      pairs_[#pairs_ + 1] = { target = target, winner = winner, loser = loser, amount = amount }
    end
    -- surplus on the longer side is unmatched
    for i = nPair + 1, #t.dies do unmatched[#unmatched + 1] = { player = t.dies[i], target = target, side = "dies" } end
    for i = nPair + 1, #t.survives do unmatched[#unmatched + 1] = { player = t.survives[i], target = target, side = "survives" } end
  end
  table.sort(unmatched, function(a, b) return a.player < b.player end)
  return { deltas = deltas, pairs = pairs_, unmatched = unmatched }
end
