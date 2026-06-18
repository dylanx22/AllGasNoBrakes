local _, ns = ...
ns = ns or __AGNB_NS
ns.Brand = ns.Brand or {}
local B = ns.Brand

B.DEFAULT = "All Gas No Brakes"

-- cfg.brandName override if non-empty; else the current guild name; else default.
function B.Resolve(cfg, guildName)
  local override = cfg and cfg.brandName
  if override and override ~= "" then return override end
  if guildName and guildName ~= "" then return guildName end
  return B.DEFAULT
end
