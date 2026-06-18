local C = __AGNB_NS.Classify

-- forgive off => always counted
T.eq(C.ClassifyDeath(20, 25, 50, false), "counted", "forgive off => counted")

-- forgive on, below threshold => counted (these are the causal deaths)
T.eq(C.ClassifyDeath(0, 25, 50, true), "counted", "first death counts")
T.eq(C.ClassifyDeath(12, 25, 50, true), "counted", "48% dead still counts")

-- forgive on, above threshold => wipeCascade
T.eq(C.ClassifyDeath(13, 25, 50, true), "wipeCascade", "52% dead is cascade")
T.eq(C.ClassifyDeath(24, 25, 50, true), "wipeCascade", "near-total is cascade")

-- guards
T.eq(C.ClassifyDeath(5, 0, 50, true), "counted", "raidSize 0 => counted")
T.eq(C.ClassifyDeath(5, 25, 65, true), "counted", "higher threshold keeps counted")
