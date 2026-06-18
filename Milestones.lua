local _, ns = ...
ns = ns or __AGNB_NS
ns.Milestones = ns.Milestones or {}
local M = ns.Milestones

M.MARKS = { 5, 10, 25, 50, 100 }

-- Marks in `marks` strictly above prev and reached by cur (ascending).
function M.Thresholds(prev, cur, marks)
  marks = marks or M.MARKS
  local out = {}
  for _, mk in ipairs(marks) do
    if (prev or 0) < mk and (cur or 0) >= mk then out[#out + 1] = mk end
  end
  return out
end

-- Achievements in curList (from ns.Achievements.For) whose id is not in prevIds set.
function M.NewAchievements(prevIds, curList)
  prevIds = prevIds or {}
  local out = {}
  for _, a in ipairs(curList or {}) do
    if not prevIds[a.id] then out[#out + 1] = a end
  end
  return out
end

-- A boss pull (wasBoss == true) in which nobody died.
function M.CleanPull(diedCount, wasBoss)
  return (wasBoss == true) and ((diedCount or 0) == 0)
end
