local _, ns = ...
ns = ns or __AGNB_NS
ns.Killcam = ns.Killcam or {}
local KC = ns.Killcam

KC.MAX_EVENTS = 12
KC.WINDOW = 10   -- seconds of history kept before a death

function KC.NewTimeline() return {} end

-- Append an event to a player's timeline; trim to the window (relative to the
-- newest event) and to MAX_EVENTS. evt = { t, kind, source, spell, amount },
-- kind in "dmg" | "heal" | "cast".
function KC.Record(tl, player, evt)
  if not (tl and player and evt) then return end
  local list = tl[player]
  if not list then list = {}; tl[player] = list end
  list[#list + 1] = evt
  local newest = evt.t or 0
  local i = 1
  while i <= #list do
    if (newest - (list[i].t or 0)) > KC.WINDOW then table.remove(list, i)
    else i = i + 1 end
  end
  while #list > KC.MAX_EVENTS do table.remove(list, 1) end
end

-- Events for `player` within [deathTime - WINDOW, deathTime], oldest-first,
-- capped to MAX_EVENTS. Returns a fresh array (safe to persist on a death).
function KC.Snapshot(tl, player, deathTime)
  local list = tl and tl[player]
  if not list then return {} end
  local out = {}
  for _, e in ipairs(list) do
    local t = e.t or 0
    if t >= (deathTime - KC.WINDOW) and t <= deathTime then
      out[#out + 1] = { t = t, kind = e.kind, source = e.source, spell = e.spell, amount = e.amount }
    end
  end
  table.sort(out, function(a, b) return (a.t or 0) < (b.t or 0) end)
  while #out > KC.MAX_EVENTS do table.remove(out, 1) end
  return out
end

-- Display rows for a snapshot: { rel = "-3.2s", kind, source, spell, amount }.
function KC.Format(events, deathTime)
  local out = {}
  for _, e in ipairs(events or {}) do
    local dt = (deathTime or 0) - (e.t or (deathTime or 0))
    out[#out + 1] = {
      rel = string.format("-%.1fs", dt),
      kind = e.kind, source = e.source, spell = e.spell, amount = e.amount,
    }
  end
  return out
end
