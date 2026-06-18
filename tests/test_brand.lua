local B = __AGNB_NS.Brand

-- explicit override wins
T.eq(B.Resolve({ brandName = "Liquid" }, "SomeGuild"), "Liquid", "override wins")
-- empty override falls back to guild
T.eq(B.Resolve({ brandName = "" }, "Murloc Inc"), "Murloc Inc", "empty => guild")
T.eq(B.Resolve({}, "Murloc Inc"), "Murloc Inc", "nil override => guild")
-- no override and no guild => default
T.eq(B.Resolve({}, nil), "All Gas No Brakes", "no guild => default")
T.eq(B.Resolve({ brandName = "" }, ""), "All Gas No Brakes", "empty guild => default")
