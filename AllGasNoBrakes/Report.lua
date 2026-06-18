local _, ns = ...
ns = ns or __AGNB_NS
ns.Report = ns.Report or {}
local R = ns.Report

local SEP = " \194\183 "  -- " · " (UTF-8 middle dot)

-- First line of every chat report identifies the addon.
R.TITLE = "AGNB - Raid Death Tracker"

-- Greedily pack entries into lines no longer than maxLen, joined by SEP.
-- An entry longer than maxLen becomes its own line (never dropped or truncated).
function R.PackEntries(entries, maxLen)
  local lines, cur = {}, nil
  for _, e in ipairs(entries) do
    if cur == nil then
      cur = e
    elseif #cur + #SEP + #e <= maxLen then
      cur = cur .. SEP .. e
    else
      lines[#lines+1] = cur
      cur = e
    end
  end
  if cur ~= nil then lines[#lines+1] = cur end
  return lines
end

-- WoW Classic fonts can't render emoji (they show as gold ◆ boxes), so reports
-- use a render-safe guillemet accent instead. The `emoji` opt toggles it on/off.
local ACCENT = "\194\187"  -- »
local DOT = " \194\183 "   -- " · "

-- "(cause · mob)" detail, or "" when neither is known.
local function detailOf(b)
  if not (b.topCause or b.topSource) then return "" end
  local mid = b.topCause or ""
  if b.topSource then mid = (mid ~= "" and (mid .. DOT) or "") .. b.topSource end
  return " (" .. mid .. ")"
end

-- board: array of {player, deaths, topCause, topSource}. opts: {brand, zone, topN, emoji}.
-- Returns array of chat-ready strings, each <= 255 chars.
function R.BuildTonight(board, opts)
  opts = opts or {}
  local topN = opts.topN or 5
  local emoji = opts.emoji ~= false
  local brand = opts.brand or "All Gas No Brakes"
  local out = {}
  local zone = opts.zone or "the raid"
  out[#out+1] = R.TITLE
  out[#out+1] = (emoji and (ACCENT .. " ") or "") .. brand .. " - Tonight (" .. zone .. ")"

  local entries = {}
  for i = 1, math.min(topN, #board) do
    local b = board[i]
    entries[#entries+1] = i .. ". " .. b.player .. " - " .. b.deaths .. detailOf(b)
  end
  for _, e in ipairs(entries) do out[#out+1] = (#e <= 255) and e or e:sub(1, 255) end
  return out
end

-- low: a Ledger.Lowlights result. opts: {brand, emoji}. Returns chat lines (each <=255).
function R.BuildLowlights(low, opts)
  opts = opts or {}
  local brand = opts.brand or "All Gas No Brakes"
  local zone = low.zone or "the raid"
  local out = {}
  out[#out+1] = R.TITLE
  out[#out+1] = brand .. " - Lowlights (" .. zone .. ")"
  if low.feeder then
    out[#out+1] = "Feeder of the Night: " .. low.feeder .. " (" .. (low.feederDeaths or 0) .. ")"
  end
  if low.deadliestAbility then
    out[#out+1] = "Deadliest: " .. low.deadliestAbility
      .. (low.deadliestSource and (" - " .. low.deadliestSource) or "")
  end
  if low.faceplanter then out[#out+1] = "Biggest faceplant: " .. low.faceplanter end
  if low.firstBlood then out[#out+1] = "First blood: " .. low.firstBlood end
  out[#out+1] = "Body count: " .. (low.bodyCount or 0)
  local capped = {}
  for _, l in ipairs(out) do capped[#capped+1] = (#l <= 255) and l or l:sub(1, 255) end
  return capped
end

-- settle: a Ledger.Settlement result. opts: {brand, emoji}. Returns chat lines.
function R.BuildLedger(settle, opts)
  opts = opts or {}
  local brand = opts.brand or "All Gas No Brakes"
  local out = {}
  out[#out+1] = R.TITLE
  out[#out+1] = brand .. " - Anti-Prize"
  out[#out+1] = "Pot: " .. (settle.pot or 0) .. "g - winner " .. (settle.winner or "?")
  local entries = {}
  local names = {}
  for p in pairs(settle.owes or {}) do names[#names+1] = p end
  table.sort(names)
  for _, p in ipairs(names) do
    entries[#entries+1] = p .. " owes " .. settle.owes[p].amount .. "g"
  end
  for _, e in ipairs(entries) do out[#out+1] = (#e <= 255) and e or e:sub(1, 255) end
  return out
end

-- board: array of {player, deaths}. opts: {brand, topN, emoji}. Returns chat lines.
function R.BuildAllTime(board, opts)
  opts = opts or {}
  local topN = opts.topN or 5
  local emoji = opts.emoji ~= false
  local brand = opts.brand or "All Gas No Brakes"
  local out = {}
  out[#out+1] = R.TITLE
  out[#out+1] = (emoji and (ACCENT .. " ") or "") .. brand .. " - All-Time Body Count"
  local entries = {}
  for i = 1, math.min(topN, #board) do
    local b = board[i]
    entries[#entries+1] = i .. ". " .. b.player .. " - " .. b.deaths .. detailOf(b)
  end
  for _, e in ipairs(entries) do out[#out+1] = (#e <= 255) and e or e:sub(1, 255) end
  return out
end
