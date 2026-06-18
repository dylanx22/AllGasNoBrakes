local AN = __AGNB_NS.Announce

-- ShouldAnnounce throttles bursts: within the wipe window, only the first passes;
-- the rest are suppressed in favor of a single summary.
local state = AN.NewState()
T.eq(AN.ShouldAnnounce(state, 100, 5), true, "first death announces")
T.eq(AN.ShouldAnnounce(state, 100, 5), false, "same instant burst suppressed")
T.eq(AN.ShouldAnnounce(state, 100.5, 5), false, "still within 5s window suppressed")
T.eq(AN.ShouldAnnounce(state, 106, 5), true, "after window announces again")

-- BurstCount tracks how many were suppressed since the last announce (for the summary).
T.ok(AN.BurstCount(state) >= 0, "burst count available")

-- ----- per-kind announce gate -----
local AN = __AGNB_NS.Announce

-- KINDS enumerates every toggleable announcement.
do
  local keys = {}
  for _, k in ipairs(AN.KINDS) do keys[k.key] = true end
  T.ok(keys.death and keys.milestone and keys.achievement and keys.survival, "kinds present")
end

-- ShouldFire honors per-kind config; ChannelFor defaults to SELF.
do
  __AGNB_NS.cfg = { announce_milestone = true, announceChan_milestone = "RAID", announce_death = false }
  T.eq(AN.ShouldFire("milestone"), true, "enabled kind fires")
  T.eq(AN.ShouldFire("death"), false, "disabled kind does not fire")
  T.eq(AN.ShouldFire("survival"), false, "absent key defaults off")
  T.eq(AN.ChannelFor("milestone"), "RAID", "configured channel")
  T.eq(AN.ChannelFor("death"), "SELF", "default channel is SELF")
end

-- OnMilestone routes to the configured non-SELF channel (captured in _sent).
do
  _sent = {}
  __AGNB_NS.cfg = { announce_milestone = true, announceChan_milestone = "RAID" }
  AN.OnMilestone("Grug", { 10 })
  T.eq(#_sent, 1, "one milestone message sent to chat")
  T.eq(_sent[1].chan, "RAID", "sent on configured channel")
  T.ok(_sent[1].msg:find("Grug", 1, true) ~= nil, "names the player")
end

-- A disabled kind sends nothing.
do
  _sent = {}
  __AGNB_NS.cfg = { announce_milestone = false }
  AN.OnMilestone("Grug", { 10 })
  T.eq(#_sent, 0, "disabled kind is silent")
end
