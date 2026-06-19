local TR = __AGNB_NS.Tour

T.ok(TR ~= nil, "Tour module loaded")
T.ok(#TR.STEPS >= 5, "tour has several steps")

-- every step is presentable: a title and a body, and an optional target getter
for i, s in ipairs(TR.STEPS) do
  T.ok(type(s.title) == "string" and s.title ~= "", "step " .. i .. " has a title")
  T.ok(type(s.body) == "string" and s.body ~= "", "step " .. i .. " has a body")
  T.ok(s.target == nil or type(s.target) == "function", "step " .. i .. " target is a getter or nil")
end

-- the driver entry points exist
T.ok(type(TR.Start) == "function", "Start exists")
T.ok(type(TR.Go) == "function", "Go exists")
T.ok(type(TR.Finish) == "function", "Finish exists")
T.eq(TR.replay, TR.Start, "replay aliases Start")
