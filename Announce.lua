local _, ns = ...
ns = ns or __AGNB_NS
ns.Announce = ns.Announce or {}
local AN = ns.Announce

-- ----- pure: throttle state -----
function AN.NewState() return { last = nil, suppressed = 0 } end

-- Returns true if this death should announce; false if within the burst window
-- (suppressed deaths are counted for a later summary).
function AN.ShouldAnnounce(state, now, windowSec)
  if state.last == nil or (now - state.last) >= windowSec then
    state.last = now
    state.suppressed = 0
    return true
  end
  state.suppressed = state.suppressed + 1
  return false
end

function AN.BurstCount(state) return state.suppressed or 0 end

-- ----- per-kind announcement gate -----
-- Every announcement is individually opt-in and routed to its own channel
-- (default private SELF), so nothing hits raid/guild chat unless the user enables it.
AN.KINDS = {
  { key = "death",        label = "deaths (snark)" },
  { key = "combobreaker", label = "lead changes" },
  { key = "streak",       label = "death streaks" },
  { key = "achievement",  label = "achievement unlocks" },
  { key = "milestone",    label = "death-count milestones" },
  { key = "survival",     label = "survival callouts" },
}

function AN.ShouldFire(kind)
  local cfg = ns.cfg or {}
  return cfg["announce_" .. kind] == true
end

function AN.ChannelFor(kind)
  local cfg = ns.cfg or {}
  return cfg["announceChan_" .. kind] or "SELF"
end

-- Send `text` for announcement `kind` on that kind's channel (SELF -> local print).
function AN.Send(text, kind)
  local chan = AN.ChannelFor(kind or "death")
  if chan == "SELF" or not SendChatMessage then
    ns.Print(text)
  else
    SendChatMessage(text, chan)
  end
end

-- Called by Tracking on each recorded death. board = current tonight leaderboard.
function AN.OnDeath(death, board)
  local cfg = ns.cfg or {}
  if not AN.ShouldFire("death") then return end
  AN.state = AN.state or AN.NewState()
  local now = death.time or (GetTime and GetTime()) or 0
  if not AN.ShouldAnnounce(AN.state, now, cfg.announceWindow or 5) then return end

  local myDeaths = 0
  for _, b in ipairs(board or {}) do if b.player == death.player then myDeaths = b.deaths end end
  local kind = death.isEnv and "faceplant" or "death"
  if #(board or {}) == 1 and myDeaths == 1 then kind = "firstblood" end

  if cfg.soundEnabled and PlaySound then
    PlaySound(death.isEnv and 8454 or 8959, "Master")
  end

  local tokens = { player = death.player, ability = death.ability,
                   envType = death.envType, count = myDeaths }
  AN.Send(ns.Snark.Line(kind, tokens), "death")
end

-- Combo breaker: a new player seized the death lead.
function AN.OnComboBreaker(newLeader, board)
  if not AN.ShouldFire("combobreaker") then return end
  local count = 0
  for _, b in ipairs(board or {}) do if b.player == newLeader then count = b.deaths end end
  AN.Send(ns.Snark.Line("combobreaker", { player = newLeader, count = count }), "combobreaker")
end

-- Death streaks: players who died N pulls in a row.
function AN.OnStreak(players, state)
  if not AN.ShouldFire("streak") then return end
  for _, p in ipairs(players) do
    local n = state and state.streaks[p] or 0
    AN.Send(p .. " has died " .. n .. " pulls in a row. Truly committed to the bit.", "streak")
  end
end

-- New all-time achievements just unlocked by `player`.
function AN.OnAchievement(player, achs)
  if not AN.ShouldFire("achievement") then return end
  for _, a in ipairs(achs or {}) do
    AN.Send(player .. " earned " .. a.name .. "!", "achievement")
  end
end

-- Death-count milestones `player` crossed tonight (e.g. {10, 25}).
function AN.OnMilestone(player, marks)
  if not AN.ShouldFire("milestone") then return end
  for _, mk in ipairs(marks or {}) do
    AN.Send(player .. " has hit " .. mk .. " deaths tonight. A milestone of mediocrity.", "milestone")
  end
end

-- A positive callout (e.g. a flawless boss pull).
function AN.OnSurvival(text)
  if not AN.ShouldFire("survival") then return end
  AN.Send(text, "survival")
end
