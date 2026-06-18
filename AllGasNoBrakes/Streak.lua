local _, ns = ...
ns = ns or __AGNB_NS
ns.Streak = ns.Streak or {}
local S = ns.Streak

-- Returns the new leader's name only when an existing leader is overtaken by a
-- different player. board is a desc-sorted leaderboard (array of {player=...}).
function S.DetectLeadChange(prevLeader, board)
  local newLeader = board[1] and board[1].player or nil
  if prevLeader and newLeader and newLeader ~= prevLeader then return newLeader end
  return nil
end

function S.NewState() return { streaks = {} } end

-- diedPlayers: array of player names who died in the pull that just ended.
-- Increments each of their streaks; resets everyone else to 0. Returns the
-- (sorted) list of players whose streak hits exactly `threshold` this pull.
function S.RecordPull(state, diedPlayers, threshold)
  threshold = threshold or 3
  local died = {}
  for _, p in ipairs(diedPlayers) do
    died[p] = true
    state.streaks[p] = state.streaks[p] or 0
  end
  local fired = {}
  for p, n in pairs(state.streaks) do
    if died[p] then
      state.streaks[p] = n + 1
      if state.streaks[p] == threshold then fired[#fired + 1] = p end
    else
      state.streaks[p] = 0
    end
  end
  table.sort(fired)
  return fired
end
