local DB = __AGNB_NS.DB

-- fresh store
local s = DB.NewStore()
T.ok(type(s.allTime) == "table", "store has allTime")
T.ok(type(s.raids) == "table", "store has raids")

local d1 = { player="Pyro", time=100, sourceName="Boss", ability="Shadow Bolt",
             isEnv=false, boss="Prince", pullId=1, classification="counted" }

T.eq(DB.RecordDeath(s, "raid1", d1), true, "first record returns true")
T.eq(s.allTime["Pyro"].deaths, 1, "counted death increments deaths")
T.eq(s.allTime["Pyro"].byAbility["Shadow Bolt"], 1, "tracks ability")
T.eq(#s.raids["raid1"].deaths, 1, "death appended to raid")

-- duplicate (same player+time) is rejected
T.eq(DB.RecordDeath(s, "raid1", d1), false, "duplicate rejected")
T.eq(s.allTime["Pyro"].deaths, 1, "duplicate did not double-count")

-- wipeCascade death counts separately, not in shame total
local d2 = { player="Pyro", time=200, sourceName="Boss", ability="Cleave",
             isEnv=false, boss="Prince", pullId=1, classification="wipeCascade" }
T.eq(DB.RecordDeath(s, "raid1", d2), true, "cascade recorded")
T.eq(s.allTime["Pyro"].deaths, 1, "cascade does not increment counted deaths")
T.eq(s.allTime["Pyro"].wipeDeaths, 1, "cascade increments wipeDeaths")

-- environmental death updates environment counter + envType ability bucket
local d3 = { player="Grug", time=300, sourceName="Environment", ability="Lava",
             isEnv=true, envType="Lava", boss="Prince", pullId=1, classification="counted" }
DB.RecordDeath(s, "raid1", d3)
T.eq(s.allTime["Grug"].environment, 1, "environment counter")
T.eq(s.allTime["Grug"].byAbility["Lava"], 1, "env death buckets ability")

-- Leaderboard from a raid session: counted deaths per player, sorted desc,
-- with the player's most-frequent cause.
local s2 = DB.NewStore()
local function rec(p, t, ability, cls)
  DB.RecordDeath(s2, "r", { player=p, time=t, ability=ability, isEnv=false,
                            boss="B", pullId=1, classification=cls or "counted" })
end
rec("Pyro", 1, "Shadow Bolt"); rec("Pyro", 2, "Shadow Bolt"); rec("Pyro", 3, "Cleave")
rec("Grug", 4, "Fireball")
rec("Grug", 5, "Cleave", "wipeCascade")  -- excluded from counted total

local board = DB.LeaderboardTonight(s2, "r")
T.eq(board[1].player, "Pyro", "Pyro leads")
T.eq(board[1].deaths, 3, "Pyro counted deaths")
T.eq(board[1].topCause, "Shadow Bolt", "Pyro top cause")
T.eq(board[2].player, "Grug", "Grug second")
T.eq(board[2].deaths, 1, "Grug counted (cascade excluded)")

-- All-time leaderboard reads aggregates.
local at = DB.LeaderboardAllTime(s2)
T.eq(at[1].player, "Pyro", "all-time leader")
T.eq(at[1].deaths, 3, "all-time count")

-- Ability board across a raid: which abilities kill most.
local ab = DB.AbilityBoard(s2, "r")
T.eq(ab[1].ability, "Shadow Bolt", "deadliest ability")
T.eq(ab[1].count, 2, "deadliest ability count")

-- VoidLastPull removes only the most-recent pull's deaths and rebuilds all-time.
local sv = DB.NewStore()
local function recp(p, t, pull)
  DB.RecordDeath(sv, "rv", { player=p, time=t, ability="X", isEnv=false,
                             boss="B", pullId=pull, classification="counted" })
end
recp("A", 1, 1); recp("B", 2, 1); recp("A", 3, 2)
T.eq(sv.allTime["A"].deaths, 2, "A has 2 before void")
local removed, pull = DB.VoidLastPull(sv, "rv")
T.eq(removed, 1, "removed 1 death from the last pull")
T.eq(pull, 2, "last pull id was 2")
T.eq(#sv.raids["rv"].deaths, 2, "two deaths remain")
T.eq(sv.allTime["A"].deaths, 1, "A all-time rolled back to 1")
T.eq(sv.allTime["B"].deaths, 1, "B unchanged by void")

-- RebuildAllTime recomputes aggregates from scratch from all raids.
DB.RebuildAllTime(sv)
T.eq(sv.allTime["A"].deaths, 1, "rebuild keeps A at 1")
T.eq(sv.allTime["B"].deaths, 1, "rebuild keeps B at 1")

-- AbilityBoard reports the most frequent source (caster) per ability.
local sc = DB.NewStore()
local function recs(p, t, ability, src)
  DB.RecordDeath(sc, "rc", { player=p, time=t, ability=ability, sourceName=src,
                             isEnv=false, boss="B", pullId=1, classification="counted" })
end
recs("A", 1, "Shadow Bolt", "Prince"); recs("B", 2, "Shadow Bolt", "Prince")
recs("C", 3, "Shadow Bolt", "Imp")    -- Shadow Bolt: Prince x2, Imp x1
recs("D", 4, "Cleave", "Gruul")
local ab = DB.AbilityBoard(sc, "rc")
T.eq(ab[1].ability, "Shadow Bolt", "deadliest ability")
T.eq(ab[1].count, 3, "deadliest count")
T.eq(ab[1].topSource, "Prince", "most frequent caster")

-- LeaderboardTonight also reports each player's most frequent caster (topSource).
local st3 = DB.NewStore()
DB.RecordDeath(st3, "rs", { player="A", time=1, ability="Cleave", sourceName="Gruul", isEnv=false, classification="counted" })
DB.RecordDeath(st3, "rs", { player="A", time=2, ability="Cleave", sourceName="Gruul", isEnv=false, classification="counted" })
DB.RecordDeath(st3, "rs", { player="A", time=3, ability="Maul",   sourceName="Add",   isEnv=false, classification="counted" })
local lb = DB.LeaderboardTonight(st3, "rs")
T.eq(lb[1].player, "A", "player A")
T.eq(lb[1].topCause, "Cleave", "top cause")
T.eq(lb[1].topSource, "Gruul", "top source/mob")

-- All-time leaderboard now carries topCause (byAbility) and topSource (byBoss).
local sat = DB.NewStore()
DB.RecordDeath(sat, "r1", { player="Z", time=1, ability="Cleave", sourceName="Gruul", boss="Gruul", isEnv=false, classification="counted" })
DB.RecordDeath(sat, "r2", { player="Z", time=2, ability="Cleave", sourceName="Gruul", boss="Gruul", isEnv=false, classification="counted" })
local atb = DB.LeaderboardAllTime(sat)
T.eq(atb[1].player, "Z", "alltime player")
T.eq(atb[1].topCause, "Cleave", "alltime top cause")
T.eq(atb[1].topSource, "Gruul", "alltime top boss")

-- Bet records: track wins/losses/net, ranked by net gold (winners first).
local sb = DB.NewStore()
DB.RecordBetResult(sb, "Lucky", true, 10)
DB.RecordBetResult(sb, "Lucky", true, 5)
DB.RecordBetResult(sb, "Sucker", false, -8)
DB.RecordBetResult(sb, "Sucker", true, 3)
local bl = DB.BetLeaderboard(sb)
T.eq(bl[1].player, "Lucky", "top winner by net gold")
T.eq(bl[1].w, 2, "win count"); T.eq(bl[1].net, 15, "net gold")
T.eq(bl[#bl].player, "Sucker", "biggest loser at the tail")
T.eq(bl[#bl].net, -5, "Sucker net -5"); T.eq(bl[#bl].l, 1, "loss count")

-- All-time nemesis is a COHERENT (spell, caster) pair, not independent modes.
-- Here Shadow Bolt is the most common spell and Gruul the most common caster, but
-- that pair only happened once -- the real most-common death is Cleave from Gruul.
local sn = DB.NewStore()
local function rec(t, ab, src) DB.RecordDeath(sn, "r", { player="Y", time=t, ability=ab, sourceName=src, isEnv=false, classification="counted" }) end
rec(1, "Shadow Bolt", "Prince"); rec(2, "Shadow Bolt", "Prince")
rec(3, "Cleave", "Gruul");      rec(4, "Cleave", "Gruul")
rec(5, "Shadow Bolt", "Gruul")
local nem = DB.LeaderboardAllTime(sn)[1]
T.eq(nem.topCause, "Cleave", "nemesis spell is from the most-common real pair")
T.eq(nem.topSource, "Gruul", "nemesis mob matches that same pair")

-- AbilityBoardAllTime aggregates abilities across raids with caster.
local abat = DB.AbilityBoardAllTime(sat)
T.eq(abat[1].ability, "Cleave", "alltime deadliest ability")
T.eq(abat[1].count, 2, "alltime ability count across raids")
T.eq(abat[1].topSource, "Gruul", "alltime ability caster")

-- Regression: a raid can record some deaths with a numeric spellId as the ability
-- (Anniversary client quirk) alongside string ability names. The leaderboard's
-- topKey tie-break must not crash comparing a number key against a string key.
local smix = DB.NewStore()
DB.RecordDeath(smix, "rm", { player="Mix", time=1, ability="Sonic Scream", sourceName="Boss", isEnv=false, classification="counted" })
DB.RecordDeath(smix, "rm", { player="Mix", time=2, ability=1245,           sourceName=4788,   isEnv=false, classification="counted" })
local okTonight = pcall(DB.LeaderboardTonight, smix, "rm")
T.ok(okTonight, "tonight leaderboard survives mixed number/string ability keys")
local okAll = pcall(DB.LeaderboardAllTime, smix)
T.ok(okAll, "all-time leaderboard survives mixed number/string ability keys")

-- DeathLog returns most-recent-first.
local slog = DB.NewStore()
DB.RecordDeath(slog, "rl", { player="A", time=1, ability="X", isEnv=false, classification="counted" })
DB.RecordDeath(slog, "rl", { player="B", time=2, ability="Y", isEnv=false, classification="counted" })
local log = DB.DeathLog(slog, "rl", 50)
T.eq(log[1].player, "B", "newest death first")
T.eq(log[2].player, "A", "older death second")
T.eq(#DB.DeathLogAllTime(slog, 50), 2, "alltime log gathers all raids")

-- VoidWindow removes only in-window deaths and rebuilds all-time aggregates.
do
  local sv = DB.NewStore()
  local function rec(p, t) DB.RecordDeath(sv, "rw", { player = p, time = t, ability = "X",
    isEnv = false, boss = "B", pullId = 1, classification = "counted" }) end
  rec("A", 100); rec("B", 105); rec("C", 200)
  local removed = DB.VoidWindow(sv, "rw", 100, 150)
  T.eq(removed, 2, "removed the two in-window deaths")
  T.eq(#sv.raids["rw"].deaths, 1, "one death remains")
  T.eq(sv.allTime["A"], nil, "A rolled out of all-time")
  T.eq(sv.allTime["C"].deaths, 1, "out-of-window death intact")
  -- after a void, a death reusing a voided (player,time) is accepted again: the de-dup
  -- index must have been invalidated, not left holding the removed key.
  T.eq(DB.RecordDeath(sv, "rw", { player = "A", time = 100, ability = "X",
    isEnv = false, boss = "B", pullId = 2, classification = "counted" }), true,
    "re-recording a voided death is accepted (index invalidated)")
end

-- PruneKillcams: strips the heavy killcam timelines from every raid except the one
-- we keep (the current session), so SavedVariables doesn't accumulate a timeline per
-- death across a season. Death records + stats are untouched.
do
  local sp = DB.NewStore()
  DB.RecordDeath(sp, "old", { player = "A", time = 1, classification = "counted", killcam = { 1, 2, 3 } })
  DB.RecordDeath(sp, "cur", { player = "B", time = 2, classification = "counted", killcam = { 4, 5 } })
  local stripped = DB.PruneKillcams(sp, "cur")
  T.eq(stripped, 1, "stripped the one old-raid killcam")
  T.eq(sp.raids["old"].deaths[1].killcam, nil, "old raid killcam dropped")
  T.ok(sp.raids["cur"].deaths[1].killcam ~= nil, "current raid killcam kept")
  T.eq(sp.raids["old"].deaths[1].player, "A", "death record itself is untouched")
end
