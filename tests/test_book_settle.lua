local B = __AGNB_NS.Book

-- SettleSummary: counts settled transfers and sums outstanding (copper).
do
  local st = { transfers = {
    { from = "A", to = "B", amount = 100, paid = 100, settled = true },
    { from = "C", to = "B", amount = 50,  paid = 20,  settled = false },
    { from = "D", to = "B", amount = 30,  paid = 0,   settled = false },
  } }
  local s = B.SettleSummary(st)
  T.eq(s.total, 3, "three transfers")
  T.eq(s.settled, 1, "one settled")
  T.eq(s.outstanding, 60, "outstanding = (50-20) + (30-0)")

  local z = B.SettleSummary(nil)
  T.eq(z.total, 0, "nil state -> zero total")
  T.eq(z.outstanding, 0, "nil state -> zero outstanding")
end

-- NetDebts: minimized transfers, deterministic, balanced, <= N-1 transfers.
do
  local t = B.NetDebts({ Anna = 8, Bob = 7, Cara = -5, Dan = -5, Eve = -5 })
  -- total owed 15 == total owing 15
  local tot = 0
  for _, x in ipairs(t) do tot = tot + x.amount end
  T.eq(tot, 15, "transfers move the whole balance")
  T.ok(#t <= 4, "at most N-1 transfers")
  -- biggest creditor (Anna) is paid first from biggest debtors
  T.eq(t[1].to, "Anna", "biggest creditor paid first")
end
do
  -- determinism: same nets in any insertion order -> identical transfer list
  local a = B.NetDebts({ X = 10, Y = -10 })
  local b = B.NetDebts({ Y = -10, X = 10 })
  T.eq(#a, 1, "single transfer"); T.eq(a[1].from, "Y", "Y pays"); T.eq(a[1].to, "X", "X receives")
  T.eq(a[1].amount, 10, "full amount")
  T.eq(b[1].from, a[1].from, "order-independent from"); T.eq(b[1].to, a[1].to, "order-independent to")
end
do
  -- everyone square -> no transfers
  local t = B.NetDebts({ A = 0, B = 0 })
  T.eq(#t, 0, "no debts when all zero")
end

-- SettlementBreakdown: per-player lines whose deltas sum to that player's net,
-- with the outcome stated as derived from the death log.
do
  local rounds = {
    { seq = 1, boss = "Hydross", line = 2.5,
      ouReveals = { Anna = "over", Bob = "under" }, ouOutcome = "over", ouStake = 5, ouCount = 4,
      fbReveals = { Anna = "Cara" },                fbOutcome = "Cara", fbStake = 5 },
  }
  local bd = B.SettlementBreakdown(rounds)
  T.eq(bd.Bob.net, -5, "Bob lost the O/U")
  T.eq(bd.Anna.net, 5 + 0, "Anna won O/U (+5) and won FB alone (no losers, +0)")
  -- every player's lines sum to their net
  for _, e in pairs(bd) do
    local s = 0
    for _, ln in ipairs(e.lines) do s = s + ln.delta end
    T.eq(s, e.net, "lines sum to net")
  end
  -- outcome text is auditable
  T.eq(bd.Bob.lines[1].outcome, "4 deaths -> over", "O/U outcome shows the death count")
end

-- ApplyPayment: recipient-authoritative, cumulative (idempotent), partial-friendly.
do
  local st = B.NewSettleState({ { from = "Dan", to = "Anna", amount = 10 } })
  T.eq(st.transfers[1].settled, false, "starts unsettled")
  -- partial payment
  T.eq(B.ApplyPayment(st, "Dan", "Anna", 6), true, "partial payment registers")
  T.eq(st.transfers[1].paid, 6, "paid accumulates to cumulative total")
  T.eq(st.transfers[1].settled, false, "still owed")
  -- a stale/duplicate lower total is ignored (idempotent via max)
  T.eq(B.ApplyPayment(st, "Dan", "Anna", 6), false, "duplicate total is a no-op")
  -- final cumulative payment settles it
  T.eq(B.ApplyPayment(st, "Dan", "Anna", 10), true, "reaching amount settles")
  T.eq(st.transfers[1].settled, true, "settled when paid >= amount")
end

-- NetChecksum: identical nets (any order) -> identical hash; a change -> different.
do
  local a = B.NetChecksum({ Anna = 8, Bob = -8 })
  local b = B.NetChecksum({ Bob = -8, Anna = 8 })
  T.eq(a, b, "checksum is order-independent")
  local c = B.NetChecksum({ Anna = 7, Bob = -7 })
  T.ok(a ~= c, "different nets -> different checksum")
end
