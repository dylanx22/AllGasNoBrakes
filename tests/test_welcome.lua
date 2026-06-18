local W = __AGNB_NS.Welcome
local CFG = __AGNB_NS.Config

T.ok(W ~= nil, "Welcome module loaded")

-- Default flag is false, and ShouldShow reflects it.
local cfg = CFG.ApplyDefaults({})
T.eq(cfg.seenWelcome, false, "seenWelcome defaults false")

local db = {}
T.ok(W.ShouldShow(db), "shows when unseen")
W.MarkSeen(db)
T.eq(db.seenWelcome, true, "MarkSeen sets the flag")
T.ok(not W.ShouldShow(db), "does not show once seen")

-- Quick-setup writes the chosen keys.
local c = CFG.ApplyDefaults({})
W.ApplyQuickSetup(c, { announceDeaths = "RAID", enableWagering = true, joinPot = true })
T.eq(c.announce_death, true, "death announce enabled")
T.eq(c.announceChan_death, "RAID", "death announce channel set")
T.eq(c.bookEnabled, true, "wagering enabled")
T.eq(c.antiPrizeOptIn, true, "pot joined")

-- Omitting announceDeaths leaves the death announce untouched.
local c2 = CFG.ApplyDefaults({})
W.ApplyQuickSetup(c2, { enableWagering = false, joinPot = false })
T.eq(c2.announce_death, false, "death announce untouched when not chosen")
T.eq(c2.bookEnabled, false, "wagering left off")

-- An explicit false turns death announce OFF, even if it was already on.
local c3 = CFG.ApplyDefaults({})
c3.announce_death = true
W.ApplyQuickSetup(c3, { announceDeaths = false })
T.eq(c3.announce_death, false, "explicit off disables an already-on death announce")
