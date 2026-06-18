local L = __AGNB_NS.Ledger

-- Settle: each player owes buyIn * deaths; pot is the sum; winner has fewest (>=0) deaths.
local res = L.Settle({ Pyro=7, Grug=5, Lightbringer=0 }, 1)
T.eq(res.pot, 12, "pot = total deaths * buyIn")
T.eq(res.owed["Pyro"], 7, "Pyro owes 7")
T.eq(res.owed["Lightbringer"], 0, "zero deaths owe nothing")
T.eq(res.winner, "Lightbringer", "fewest deaths wins the pot")

-- Title ladder: largest threshold <= deaths.
T.eq(L.Title(0), "The Immortal", "0 deaths title")
T.eq(L.Title(1), "Has a Pulse", "1 death title")
T.eq(L.Title(7), "Speed Bump", "5-9 band")
T.eq(L.Title(12), "Crash Test Dummy", "10-19 band")
T.eq(L.Title(99), "One With The Floor", "top band")

-- Lowlights from a raid's death list.
local raid = { zone="Karazhan", deaths = {
  { player="Pyro", time=10, ability="Shadow Bolt", isEnv=false, classification="counted" },
  { player="Pyro", time=20, ability="Cleave", isEnv=false, classification="counted" },
  { player="Grug", time=5,  ability="Cleave", isEnv=false, classification="counted" },
  { player="Dotmaster", time=30, ability="Lava", isEnv=true, envType="Lava", classification="counted" },
}}
local low = L.Lowlights(raid)
T.eq(low.feeder, "Pyro", "feeder = most counted deaths")
T.eq(low.bodyCount, 4, "body count includes all counted deaths")
T.eq(low.firstBlood, "Grug", "first blood = earliest death")
T.eq(low.faceplanter, "Dotmaster", "faceplanter = most env deaths")

-- Lowlights now also reports the deadliest ability, its caster, and the feeder's count.
local raid2 = { zone="Karazhan", deaths = {
  { player="Pyro", time=10, ability="Shadow Bolt", sourceName="Prince", isEnv=false, classification="counted" },
  { player="Pyro", time=20, ability="Shadow Bolt", sourceName="Prince", isEnv=false, classification="counted" },
  { player="Grug", time=5,  ability="Cleave", sourceName="Gruul", isEnv=false, classification="counted" },
}}
local low2 = L.Lowlights(raid2)
T.eq(low2.feeder, "Pyro", "feeder")
T.eq(low2.feederDeaths, 2, "feeder count")
T.eq(low2.deadliestAbility, "Shadow Bolt", "deadliest ability")
T.eq(low2.deadliestSource, "Prince", "deadliest caster")

-- Settlement: losers each owe buyIn*deaths to the winner (fewest deaths).
local set = L.Settlement({ Pyro=7, Grug=5, Lightbringer=0 }, 1)
T.eq(set.winner, "Lightbringer", "winner = fewest deaths")
T.eq(set.pot, 12, "pot = total deaths * buyIn")
T.eq(set.owes["Pyro"].to, "Lightbringer", "Pyro owes the winner")
T.eq(set.owes["Pyro"].amount, 7, "Pyro owes 7")
T.eq(set.owes["Grug"].amount, 5, "Grug owes 5")
T.eq(set.owes["Lightbringer"], nil, "winner owes nothing")

-- Podium awards: deterministic per player, and de-duplicated across slots.
T.eq(L.PodiumAward("Ayanski", {}), L.PodiumAward("Ayanski", {}), "same player -> same award")
local taken = {}
local a1 = L.PodiumAward("Ayanski", taken); taken[a1] = true
local a2 = L.PodiumAward("Fatpots", taken); taken[a2] = true
local a3 = L.PodiumAward("Kiekie", taken); taken[a3] = true
T.ok(a1 ~= a2 and a2 ~= a3 and a1 ~= a3, "top 3 awards are distinct")
local pool = {}; for _, w in ipairs(L.PODIUM_AWARDS) do pool[w] = true end
T.ok(pool[a1] and pool[a2] and pool[a3], "awards come from the pool")

-- Opt-in: with a participants set, only opted-in players are in the pot.
local optedIn = { Pyro = true, Grug = true }   -- Lightbringer did NOT opt in
local set2 = L.Settlement({ Pyro=7, Grug=5, Lightbringer=0 }, 1, optedIn)
T.eq(set2.pot, 12, "pot counts only opted-in players' deaths")
T.eq(set2.winner, "Grug", "winner is the fewest-deaths OPTED-IN player")
T.eq(set2.owes["Pyro"].to, "Grug", "Pyro owes the opted-in winner")
T.eq(set2.owes["Lightbringer"], nil, "non-participant never owes")
-- Nobody opted in -> no pot, no debts.
local set3 = L.Settlement({ Pyro=7, Grug=5 }, 1, {})
T.eq(set3.pot, 0, "empty participants => empty pot")
T.eq(next(set3.owes), nil, "empty participants => nobody owes")
