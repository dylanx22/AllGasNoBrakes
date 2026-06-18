local AP = __AGNB_NS.AntiPrize

-- The opt-in registry tracks who's in the pot; sync adds/removes players.
AP.optedIn = {}
T.eq(AP.Count(), 0, "starts empty (opt-in)")
AP.OnSync("Pyro", true)
AP.OnSync("Grug", true)
T.eq(AP.Count(), 2, "two opted in")
T.ok(AP.Participants()["Pyro"], "participant set membership")
AP.OnSync("Pyro", false)
T.eq(AP.Count(), 1, "opt-out removes from the set")
T.eq(AP.Participants()["Pyro"], nil, "opted-out player not a participant")

-- Settlement honors the registry: a non-opted-in player never owes.
local set = __AGNB_NS.Ledger.Settlement({ Grug = 5, Stranger = 9 }, 1, AP.Participants())
T.eq(set.owes["Stranger"], nil, "non-participant is excluded from the pot")
T.eq(set.pot, 5, "pot only counts opted-in Grug")
