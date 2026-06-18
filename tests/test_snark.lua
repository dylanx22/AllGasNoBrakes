local S = __AGNB_NS.Snark

-- Fill replaces all tokens.
T.eq(S.Fill("{player} ate {ability} (#{count})", { player="Pyro", ability="Cleave", count=4 }),
     "Pyro ate Cleave (#4)", "fills tokens")

-- Unknown tokens are left blank, not literal.
T.eq(S.Fill("{player}{missing}", { player="Pyro" }), "Pyro", "missing token => empty")

-- Pools exist and are non-empty.
T.ok(#S.pools.death > 0, "death pool populated")
T.ok(#S.pools.faceplant > 0, "faceplant pool populated")
T.ok(#S.pools.firstblood > 0, "firstblood pool populated")

-- Line(kind, tokens, rng) is deterministic when rng is injected.
local line = S.Line("death", { player="Pyro", ability="Cleave", count=1 }, function() return 1 end)
T.ok(line:find("Pyro"), "line includes player name")
T.ok(not line:find("{"), "no leftover tokens in line")
