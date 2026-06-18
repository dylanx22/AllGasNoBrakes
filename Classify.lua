local _, ns = ...
ns = ns or __AGNB_NS
ns.Classify = ns.Classify or {}
local C = ns.Classify

-- nDeadBefore: raiders already dead in this pull at the moment of this death.
-- Returns "wipeCascade" if the wipe was already lost (> thresholdPct dead) and
-- forgiveness is enabled, otherwise "counted".
function C.ClassifyDeath(nDeadBefore, raidSize, thresholdPct, forgive)
  if not forgive then return "counted" end
  if not raidSize or raidSize <= 0 then return "counted" end
  local deadPct = (nDeadBefore / raidSize) * 100
  if deadPct > thresholdPct then return "wipeCascade" end
  return "counted"
end
