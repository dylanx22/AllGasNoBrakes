-- Shared namespace the addon modules attach to under test.
__AGNB_NS = {}

local T = { passed = 0, failed = 0, failures = {} }

function T.eq(actual, expected, msg)
  if actual ~= expected then
    T.failed = T.failed + 1
    T.failures[#T.failures+1] = string.format("%s\n    expected: %s\n    actual:   %s",
      tostring(msg or "eq"), tostring(expected), tostring(actual))
  else
    T.passed = T.passed + 1
  end
end

function T.ok(cond, msg)
  if cond then T.passed = T.passed + 1
  else
    T.failed = T.failed + 1
    T.failures[#T.failures+1] = tostring(msg or "expected truthy")
  end
end

function T.summary()
  print(string.format("\n%d passed, %d failed", T.passed, T.failed))
  for _, f in ipairs(T.failures) do print("FAIL: " .. f) end
  return T.failed == 0
end

return T
