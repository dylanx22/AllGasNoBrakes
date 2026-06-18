local Help = __AGNB_NS.Help
local CFG = __AGNB_NS.Config

T.ok(Help ~= nil, "Help module loaded")

-- Every GUIDE block is renderable (non-empty title + body).
for i, b in ipairs(Help.GUIDE) do
  T.ok(type(b.title) == "string" and #b.title > 0, "guide block has title #" .. i)
  T.ok(type(b.body) == "string" and #b.body > 0, "guide block has body #" .. i)
end

-- Every tooltip key is a real setting (exists in DEFAULTS).
for key in pairs(Help.SETTING) do
  T.ok(CFG.DEFAULTS[key] ~= nil, "tooltip key is a real setting: " .. key)
end

-- Every `help` key referenced by the layout has tooltip text (no dangling refs).
for _, tab in ipairs(CFG.SETTINGS_LAYOUT) do
  for _, group in ipairs(tab.groups) do
    for _, c in ipairs(group.controls) do
      if c.help then
        T.ok(Help.SETTING[c.help] ~= nil, "layout help key has text: " .. c.help)
      end
    end
  end
end
