local CFG = __AGNB_NS.Config

-- Every user-facing key is covered by exactly one tab.
local covered = CFG.CoveredKeys()
for _, key in ipairs(CFG.USER_FACING_KEYS) do
  T.ok(covered[key] ~= nil, "setting covered by a tab: " .. key)
end

-- No tab covers a key that isn't declared user-facing (no orphan controls).
local declared = {}
for _, k in ipairs(CFG.USER_FACING_KEYS) do declared[k] = true end
for key in pairs(covered) do
  T.ok(declared[key], "covered key is declared user-facing: " .. key)
end

-- The announce table expands to both the toggle and the channel for each kind.
for _, k in ipairs(__AGNB_NS.Announce.KINDS) do
  T.eq(covered["announce_" .. k.key], "chat", "announce toggle in chat tab: " .. k.key)
  T.eq(covered["announceChan_" .. k.key], "chat", "announce channel in chat tab: " .. k.key)
end

-- Tabs are in the agreed order.
local ids = {}
for _, tab in ipairs(CFG.SETTINGS_LAYOUT) do ids[#ids+1] = tab.id end
T.eq(table.concat(ids, ","), "tracking,chat,overlays,gold_book,advanced", "tab order")
