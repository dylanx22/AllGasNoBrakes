local _, ns = ...
ns = ns or __AGNB_NS
ns.Achievements = ns.Achievements or {}
local A = ns.Achievements

-- All-time, death-based achievements. Evaluated against a player's allTime record
-- (deaths, wipeDeaths, environment, byAbility, byCause). Pure + testable.

local function maxVal(map)
  local m = 0
  for _, v in pairs(map or {}) do if v > m then m = v end end
  return m
end

A.DEFS = {
  { id = "d10",   name = "Getting Comfortable", desc = "Die 10 times",            test = function(p) return (p.deaths or 0) >= 10 end },
  { id = "d25",   name = "Frequent Flyer",      desc = "Die 25 times",            test = function(p) return (p.deaths or 0) >= 25 end },
  { id = "d50",   name = "Crash Test Dummy",    desc = "Die 50 times",            test = function(p) return (p.deaths or 0) >= 50 end },
  { id = "d100",  name = "Century of Shame",    desc = "Die 100 times",           test = function(p) return (p.deaths or 0) >= 100 end },
  { id = "d250",  name = "One With The Floor",  desc = "Die 250 times",           test = function(p) return (p.deaths or 0) >= 250 end },
  { id = "env10", name = "Death by Scenery",    desc = "10 environmental deaths", test = function(p) return (p.environment or 0) >= 10 end },
  { id = "habit", name = "Creature of Habit",   desc = "Die the same way 20+ times", test = function(p) return maxVal(p.byCause) >= 20 end },
  { id = "slow",  name = "Slow Learner",        desc = "Die to one ability 25+ times", test = function(p) return maxVal(p.byAbility) >= 25 end },
  { id = "casc",  name = "Cascade Casualty",    desc = "50 wipe-cascade deaths",  test = function(p) return (p.wipeDeaths or 0) >= 50 end },
}

-- Earned achievements for an allTime record, in definition order.
function A.For(record)
  local out = {}
  if not record then return out end
  for _, d in ipairs(A.DEFS) do
    if d.test(record) then out[#out + 1] = { id = d.id, name = d.name, desc = d.desc } end
  end
  return out
end

function A.CountFor(record) return #A.For(record) end
