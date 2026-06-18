local _, ns = ...
ns = ns or __AGNB_NS
ns.Book = ns.Book or {}
local B = ns.Book

-- Pure end-of-raid settlement: turn each player's session net into the fewest
-- peer-to-peer transfers, an auditable per-player breakdown, an idempotent
-- payment-tracking state, and a checksum for cross-client agreement. All amounts
-- are in the smallest money unit (copper). Nets must sum to zero.

-- Greedy minimum cash-flow: match biggest creditor to biggest debtor until square.
-- nets: {player=net} (+ owed to them, - they owe). Returns ordered {from,to,amount}.
function B.NetDebts(nets)
  local names = {}
  for p in pairs(nets) do names[#names + 1] = p end
  table.sort(names)
  local creditors, debtors = {}, {}
  for _, p in ipairs(names) do
    local v = nets[p] or 0
    if v > 0 then creditors[#creditors + 1] = { player = p, amt = v }
    elseif v < 0 then debtors[#debtors + 1] = { player = p, amt = -v } end
  end
  local function byAmt(a, b)
    if a.amt ~= b.amt then return a.amt > b.amt end
    return a.player < b.player
  end
  table.sort(creditors, byAmt); table.sort(debtors, byAmt)
  local out, ci, di = {}, 1, 1
  while ci <= #creditors and di <= #debtors do
    local c, d = creditors[ci], debtors[di]
    local m = math.min(c.amt, d.amt)
    if m > 0 then out[#out + 1] = { from = d.player, to = c.player, amount = m } end
    c.amt = c.amt - m; d.amt = d.amt - m
    if c.amt == 0 then ci = ci + 1 end
    if d.amt == 0 then di = di + 1 end
  end
  return out
end

-- rounds: array of ledger entries, each:
--   { seq, boss, line, ouReveals, ouOutcome, ouStake, ouCount, fbReveals, fbOutcome, fbStake }
-- Returns {player = { net, lines = {line item, ...} }}. Deltas come straight from
-- RoundDeltas, so sum(lines.delta) == net and NetDebts(nets) is reproducible.
local function resultLabel(delta)
  if delta > 0 then return "won" elseif delta < 0 then return "lost" else return "push" end
end

function B.SettlementBreakdown(rounds)
  local out = {}
  local function ensure(p)
    if not out[p] then out[p] = { net = 0, lines = {} } end
    return out[p]
  end
  for _, r in ipairs(rounds) do
    local ou = B.RoundDeltas(r.ouReveals or {}, r.ouOutcome, r.ouStake or 0)
    for p, pick in pairs(r.ouReveals or {}) do
      local e, delta = ensure(p), ou[p] or 0
      e.net = e.net + delta
      e.lines[#e.lines + 1] = {
        seq = r.seq, boss = r.boss, bet = ("O/U %.1f"):format(r.line or 0), pick = pick,
        stake = r.ouStake or 0, outcome = ("%d deaths -> %s"):format(r.ouCount or 0, tostring(r.ouOutcome)),
        result = resultLabel(delta), delta = delta,
      }
    end
    local fb = B.RoundDeltas(r.fbReveals or {}, r.fbOutcome, r.fbStake or 0)
    for p, pick in pairs(r.fbReveals or {}) do
      local e, delta = ensure(p), fb[p] or 0
      e.net = e.net + delta
      e.lines[#e.lines + 1] = {
        seq = r.seq, boss = r.boss, bet = "First Blood", pick = pick,
        stake = r.fbStake or 0, outcome = ("first death: %s"):format(tostring(r.fbOutcome)),
        result = resultLabel(delta), delta = delta,
      }
    end
  end
  return out
end

-- Convenience: {player = net} from a breakdown, for feeding NetDebts.
function B.NetsFromBreakdown(bd)
  local nets = {}
  for p, e in pairs(bd) do nets[p] = e.net end
  return nets
end

-- A tracking state over a transfer list. `paid` is the recipient's CUMULATIVE
-- received total for that pair, so applying it is idempotent.
function B.NewSettleState(transfers)
  local st = { transfers = {} }
  for i, t in ipairs(transfers) do
    st.transfers[i] = { from = t.from, to = t.to, amount = t.amount, paid = 0, settled = false }
  end
  return st
end

-- Summarize a settle state for the admin overview: how many transfers are
-- settled, the total count, and the outstanding (unpaid) copper across all of
-- them. Never negative.
function B.SettleSummary(state)
  local settled, total, outstanding = 0, 0, 0
  for _, t in ipairs((state and state.transfers) or {}) do
    total = total + 1
    if t.settled then settled = settled + 1 end
    local owed = (t.amount or 0) - (t.paid or 0)
    if owed > 0 then outstanding = outstanding + owed end
  end
  return { settled = settled, total = total, outstanding = outstanding }
end

-- Apply a recipient's cumulative paid total. Returns true if anything changed.
function B.ApplyPayment(state, from, to, paidTotal)
  paidTotal = paidTotal or 0
  local changed = false
  for _, t in ipairs(state.transfers) do
    if t.from == from and t.to == to then
      if paidTotal > t.paid then t.paid = paidTotal; changed = true end
      t.settled = t.paid >= t.amount
    end
  end
  return changed
end

-- A short, order-independent fingerprint of a net table so clients can detect a
-- divergent (stale/desynced) computation before any gold moves.
function B.NetChecksum(nets)
  local names = {}
  for p in pairs(nets) do names[#names + 1] = p end
  table.sort(names)
  local parts = {}
  for _, p in ipairs(names) do parts[#parts + 1] = p .. "=" .. tostring(nets[p]) end
  return ns.Hash.SHA256(table.concat(parts, ";")):sub(1, 12)
end
