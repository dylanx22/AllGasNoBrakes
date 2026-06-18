local _, ns = ...
ns = ns or __AGNB_NS
ns.Export = ns.Export or {}
local E = ns.Export

local DOT = " \194\183 "   -- " · "

local function fmtDuration(sec)
  local m = math.floor((sec or 0) / 60)
  return m .. "m"
end

local function zonesText(zones)
  if not zones or #zones == 0 then return "Unknown" end
  return table.concat(zones, ", ")
end

-- Discord-ready multi-line string built from a History.Report object.
function E.Text(report)
  local m = report.meta
  local lines = {}
  lines[#lines + 1] = "All Gas No Brakes - " .. zonesText(m.zones)
  lines[#lines + 1] = "Body count: " .. (m.bodyCount or 0)
    .. DOT .. (m.bossCount or 0) .. " bosses"
    .. DOT .. (m.wipeCount or 0) .. " wipes"
    .. DOT .. fmtDuration(m.duration)
  local low = report.lowlights or {}
  if low.feeder then
    lines[#lines + 1] = "Feeder of the Night: " .. low.feeder .. " (" .. (low.feederDeaths or 0) .. ")"
  end
  if low.deadliestAbility then
    lines[#lines + 1] = "Deadliest: " .. low.deadliestAbility
      .. (low.deadliestSource and (" - " .. low.deadliestSource) or "")
  end
  if low.firstBlood then lines[#lines + 1] = "First blood: " .. low.firstBlood end
  for _, b in ipairs(report.perBoss or {}) do
    lines[#lines + 1] = b.boss .. ": " .. b.deaths .. " (" .. (b.topCause or "?") .. ")"
  end
  if m.pot and m.pot > 0 then
    lines[#lines + 1] = "Anti-prize pot: " .. m.pot .. "g - winner " .. (m.winner or "?")
  end
  return table.concat(lines, "\n")
end

-- Pure layout data for the scorecard frame: ordered sections of {label,value} rows.
function E.Card(report)
  local m = report.meta
  local sections = {}
  sections[#sections + 1] = { title = "Raid", rows = {
    { label = "Zone", value = zonesText(m.zones) },
    { label = "Body count", value = tostring(m.bodyCount or 0) },
    { label = "Bosses", value = tostring(m.bossCount or 0) },
    { label = "Wipes", value = tostring(m.wipeCount or 0) },
    { label = "Duration", value = fmtDuration(m.duration) },
  } }
  local low = report.lowlights or {}
  local lrows = {}
  if low.feeder then lrows[#lrows + 1] = { label = "Feeder", value = low.feeder .. " (" .. (low.feederDeaths or 0) .. ")" } end
  if low.deadliestAbility then lrows[#lrows + 1] = { label = "Deadliest", value = low.deadliestAbility } end
  if low.firstBlood then lrows[#lrows + 1] = { label = "First blood", value = low.firstBlood } end
  if #lrows > 0 then sections[#sections + 1] = { title = "Lowlights", rows = lrows } end
  local brows = {}
  for _, b in ipairs(report.perBoss or {}) do
    brows[#brows + 1] = { label = b.boss, value = b.deaths .. " (" .. (b.topCause or "?") .. ")" }
  end
  if #brows > 0 then sections[#sections + 1] = { title = "Per-boss", rows = brows } end
  if m.pot and m.pot > 0 then
    sections[#sections + 1] = { title = "Anti-Prize", rows = {
      { label = "Pot", value = m.pot .. "g" },
      { label = "Winner", value = m.winner or "?" },
    } }
  end
  return sections
end
