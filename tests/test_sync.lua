local SY = __AGNB_NS.Sync

local death = { player="Pyro", time=12345, sourceName="Prince", ability="Shadow Bolt",
                isEnv=false, envType=nil, boss="Prince", pullId=1, classification="counted" }

local wire = SY.Encode(death)
T.ok(type(wire) == "string", "encode returns string")
T.ok(not wire:find("\n"), "no newlines in wire format")

local back = SY.Decode(wire)
T.eq(back.player, "Pyro", "round-trip player")
T.eq(back.time, 12345, "round-trip time (number)")
T.eq(back.ability, "Shadow Bolt", "round-trip ability with space")
T.eq(back.isEnv, false, "round-trip bool false")
T.eq(back.classification, "counted", "round-trip classification")

-- Fields containing the delimiter are escaped safely.
local tricky = { player="Bob", time=1, sourceName="A|B", ability="C|D", isEnv=true,
                 envType="Lava", boss="X|Y", pullId=2, classification="wipeCascade" }
local rt = SY.Decode(SY.Encode(tricky))
T.eq(rt.sourceName, "A|B", "escaped delimiter in sourceName")
T.eq(rt.ability, "C|D", "escaped delimiter in ability")
T.eq(rt.isEnv, true, "round-trip bool true")

-- Malformed input decodes to nil rather than erroring.
T.eq(SY.Decode("garbage"), nil, "malformed => nil")

-- Backslash-containing fields must round-trip (escape scheme must not alias).
local bs = { player="Bob", time=9, sourceName="A\\pB", ability="C\\D", isEnv=false,
             envType=nil, boss="x", pullId=1, classification="counted" }
local rtb = SY.Decode(SY.Encode(bs))
T.eq(rtb.sourceName, "A\\pB", "backslash-p round-trips")
T.eq(rtb.ability, "C\\D", "backslash round-trips")
