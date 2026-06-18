local _, ns = ...
ns = ns or __AGNB_NS
ns.Settlement = ns.Settlement or {}
local ST = ns.Settlement

-- End-of-raid settlement glue. Pure math lives in BookSettle.lua; this wires it to
-- trade/mail events and addon comms. A debt settles ONLY on the recipient's
-- confirmation (recipient-authoritative), and confirmations carry the recipient's
-- cumulative received total so they apply idempotently.

local function send(msg)
  local chan = ns.Sync and ns.Sync.Channel and ns.Sync.Channel()
  if chan and C_ChatInfo then C_ChatInfo.SendAddonMessage(ns.Sync.PREFIX, msg, chan) end
end
local function myName() return ns.MyName or (UnitName and UnitName("player")) or "?" end
local function refresh() if ns.BookUI and ns.BookUI.Refresh then ns.BookUI.Refresh() end end

-- Build nets from the Book session ledger and the minimized transfer list.
function ST.Compute()
  local ledger = (ns.Book and ns.Book.rt and ns.Book.rt.ledger) or {}
  local bd = ns.Book.SettlementBreakdown(ledger)
  local nets = ns.Book.NetsFromBreakdown(bd)
  ST.breakdown = bd
  ST.nets = nets
  ST.state = ns.Book.NewSettleState(ns.Book.NetDebts(nets))
  ST.checksum = ns.Book.NetChecksum(nets)
  ST.received = {}
  ST.peerChecksums = { [myName()] = ST.checksum }
  ST.desync = false
  refresh()
  return ST.state
end

-- Transfers where I am the payer (what I owe and to whom).
function ST.MyDebts()
  local out = {}
  if ST.state then
    for _, t in ipairs(ST.state.transfers) do
      if t.from == myName() then out[#out + 1] = t end
    end
  end
  return out
end

-- The whole raid's wager math from the last Compute(): every player's bet-by-bet
-- lines and session net, biggest winners first (ties broken by name). Admin-only
-- overview -- the per-player detail the transfer list alone doesn't show.
function ST.AllMath()
  local out = {}
  for p, e in pairs(ST.breakdown or {}) do
    out[#out + 1] = { player = p, net = e.net or 0, lines = e.lines or {} }
  end
  table.sort(out, function(a, b)
    if a.net ~= b.net then return a.net > b.net end
    return a.player < b.player
  end)
  return out
end

-- The viewer's first still-unsettled outgoing transfer, for the mail pre-fill.
-- Returns { to, amount } where amount is the remaining copper owed, or nil.
function ST.MailNext()
  if not ST.state then return nil end
  local me = myName()
  for _, t in ipairs(ST.state.transfers) do
    if t.from == me and not t.settled then
      return { to = t.to, amount = (t.amount or 0) - (t.paid or 0) }
    end
  end
  return nil
end

-- Recipient side: record cumulative gold received from `from` and broadcast it.
function ST.ReceivedGold(from, copper)
  if not (ST.state and from and copper and copper > 0) then return end
  ST.received = ST.received or {}
  ST.received[from] = (ST.received[from] or 0) + copper
  if ns.Book.ApplyPayment(ST.state, from, myName(), ST.received[from]) then
    send(("BPAID|%s|%s|%d"):format(from, myName(), ST.received[from]))
    refresh()
  end
end

-- Recipient clicks "mark paid" on a debt owed to them (mail/in-person/etc.).
function ST.MarkPaid(from)
  if not ST.state then return end
  local me = myName()
  for _, t in ipairs(ST.state.transfers) do
    if t.from == from and t.to == me then
      ST.received = ST.received or {}
      ST.received[from] = t.amount
      ns.Book.ApplyPayment(ST.state, from, me, t.amount)
      send(("BPAID|%s|%s|%d"):format(from, me, t.amount))
    end
  end
  refresh()
end

-- Receive a peer's payment confirmation. Only the recipient (`to`) may confirm.
function ST.OnPaid(from, to, paidTotal, sender)
  if not ST.state then return end
  if sender ~= to then return end
  ns.Book.ApplyPayment(ST.state, from, to, paidTotal)
  refresh()
end

-- Receive a peer's net checksum; flag desync if the majority disagree with ours.
function ST.OnChecksum(sender, hash)
  ST.peerChecksums = ST.peerChecksums or {}
  ST.peerChecksums[sender] = hash
  local mine, agree, disagree = ST.checksum, 0, 0
  for _, h in pairs(ST.peerChecksums) do
    if h == mine then agree = agree + 1 else disagree = disagree + 1 end
  end
  ST.desync = disagree > agree
  refresh()
end

-- ----- WoW glue: trade + mail detection (recipient-authoritative) -----
ns.OnInit(function()
  local f = CreateFrame("Frame")
  f:RegisterEvent("TRADE_ACCEPT_UPDATE")
  f:RegisterEvent("TRADE_REQUEST_CANCEL")
  f:RegisterEvent("TRADE_CLOSED")
  local cap = { accepted = false, partner = nil, money = 0 }
  f:SetScript("OnEvent", ns.Debug.Guard("Settlement.OnEvent", function(_, event, p1, p2)
    if event == "TRADE_ACCEPT_UPDATE" then
      if p1 == 1 and p2 == 1 then       -- both parties accepted
        cap.accepted = true
        cap.partner = (UnitName and UnitName("NPC")) or nil
        cap.money = (GetTargetTradeMoney and GetTargetTradeMoney()) or 0  -- copper the partner gave me
      end
    elseif event == "TRADE_REQUEST_CANCEL" then
      cap.accepted = false
    elseif event == "TRADE_CLOSED" then
      if cap.accepted and cap.partner and cap.money > 0 then
        ST.ReceivedGold(cap.partner:match("^[^-]+") or cap.partner, cap.money)
      end
      cap.accepted, cap.partner, cap.money = false, nil, 0
    end
  end))

  -- Mail: when I take money from an inbox item, confirm receipt from the sender.
  if hooksecurefunc and TakeInboxMoney then
    hooksecurefunc("TakeInboxMoney", function(index)
      if not GetInboxHeaderInfo then return end
      local _, _, sender, _, money = GetInboxHeaderInfo(index)
      if sender and money and money > 0 then
        ST.ReceivedGold(sender:match("^[^-]+") or sender, money)
      end
    end)
  end
end)
