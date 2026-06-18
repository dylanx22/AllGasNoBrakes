local CFG = __AGNB_NS.Config

-- Defaults applied onto an empty table without clobbering existing values.
local saved = { announceEnabled = true }   -- user already turned this on
local cfg = CFG.ApplyDefaults(saved)
T.eq(cfg.announceEnabled, true, "keeps user value")
T.eq(cfg.announceChannel, "SELF", "default channel")
T.eq(cfg.wipeThresholdPct, 50, "default wipe threshold")
T.eq(cfg.forgiveWipeDeaths, true, "default forgive on")
T.eq(cfg.buyIn, 1, "default buy-in")
T.eq(cfg.reportTopN, 5, "default report topN")

-- ParseSlash splits a command line into subcommand + remainder.
local sub, rest = CFG.ParseSlash("report raid")
T.eq(sub, "report", "subcommand parsed")
T.eq(rest, "raid", "remainder parsed")
local sub2 = CFG.ParseSlash("")
T.eq(sub2, "", "empty command => empty subcommand")

-- v0.2 defaults
local cfg2 = CFG.ApplyDefaults({})
T.eq(cfg2.wipeBannerStyle, "gold", "default banner style")
T.eq(cfg2.wipeTagline, "ALL GAS, NO BRAKES", "default tagline")
T.eq(cfg2.autoSummaryOnFinalBoss, true, "auto summary default on")
T.eq(cfg2.streakThreshold, 3, "default streak threshold")
T.eq(cfg2.brandName, "", "brand override empty by default")
