local R = __AGNB_NS.Report

-- PackLine joins entries with " · " into lines no longer than maxLen.
local entries = { "1. Pyro - 7", "2. Grug - 5", "3. Backstabz - 4" }
local lines = R.PackEntries(entries, 22)   -- small cap forces splitting
T.ok(#lines >= 2, "packs into multiple lines under cap")
for _, l in ipairs(lines) do T.ok(#l <= 22, "line within cap: " .. l) end

-- A single entry longer than the cap still emerges as its own line (never dropped).
local long = R.PackEntries({ "x" .. string.rep("y", 300) }, 255)
T.eq(#long, 1, "oversized entry kept as one line")

-- BuildTonight returns a header + packed body honoring topN.
local board = {
  { player="Pyro", deaths=7, topCause="Shadow Bolt" },
  { player="Grug", deaths=5, topCause="Cleave" },
  { player="Backstabz", deaths=4, topCause="Lava" },
}
local out = R.BuildTonight(board, { zone="Karazhan", topN=2, emoji=false })
T.eq(out[1], R.TITLE, "title line first")
T.ok(out[2]:find("Karazhan"), "header names zone")
local joined = table.concat(out, "\n")
T.ok(joined:find("Pyro"), "includes #1")
T.ok(joined:find("Grug"), "includes #2")
T.ok(not joined:find("Backstabz"), "respects topN=2")

-- BuildAllTime: header with brand + all-time label, packed body honoring topN.
local atboard = {
  { player="Pyro", deaths=40 }, { player="Grug", deaths=33 }, { player="Backstabz", deaths=21 },
}
local atout = R.BuildAllTime(atboard, { brand="Liquid", topN=2, emoji=false })
T.eq(atout[1], R.TITLE, "title line first")
T.ok(atout[2]:find("Liquid"), "header has brand")
T.ok(atout[2]:find("All%-Time"), "header says all-time")
local atj = table.concat(atout, "\n")
T.ok(atj:find("Pyro"), "includes #1")
T.ok(atj:find("Grug"), "includes #2")
T.ok(not atj:find("Backstabz"), "respects topN")

-- BuildLowlights: header + named feeder/ability/caster, body count, all lines capped.
local low = { zone="Karazhan", feeder="Pyro", feederDeaths=7, faceplanter="Dotmaster",
              firstBlood="Grug", bodyCount=22, deadliestAbility="Shadow Bolt", deadliestSource="Prince" }
local lout = R.BuildLowlights(low, { brand="Liquid", emoji=false })
local lj = table.concat(lout, "\n")
T.eq(lout[1], R.TITLE, "title line first")
T.ok(lout[2]:find("Liquid"), "header brand")
T.ok(lj:find("Pyro"), "feeder named")
T.ok(lj:find("Shadow Bolt"), "deadliest ability named")
T.ok(lj:find("Prince"), "caster named")
T.ok(lj:find("22"), "body count present")
for _, l in ipairs(lout) do T.ok(#l <= 255, "line within cap") end

-- BuildLedger: header + winner, pot, owers and amounts, all lines capped.
local settle = { winner="Lightbringer", pot=12,
                 owes={ Pyro={to="Lightbringer", amount=7}, Grug={to="Lightbringer", amount=5} } }
local dout = R.BuildLedger(settle, { brand="Liquid", emoji=false })
local dj = table.concat(dout, "\n")
T.eq(dout[1], R.TITLE, "title line first")
T.ok(dout[2]:find("Liquid"), "header brand")
T.ok(dj:find("Lightbringer"), "winner named")
T.ok(dj:find("12g"), "pot shown")
T.ok(dj:find("Pyro"), "ower named")
T.ok(dj:find("7g"), "amount shown")
for _, l in ipairs(dout) do T.ok(#l <= 255, "line within cap") end

-- Reports now emit one entry per line (title line + one line per rank).
local oneper = R.BuildAllTime(
  { {player="A",deaths=9},{player="B",deaths=8},{player="C",deaths=7} },
  { brand="L", topN=3, emoji=false })
T.eq(#oneper, 5, "title + header + 3 one-per-line entries")
T.ok(oneper[3]:find("A") and not oneper[3]:find("B"), "each entry on its own line")
