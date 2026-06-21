local _, ns = ...
ns = ns or __AGNB_NS
ns.Debug = ns.Debug or {}
local D = ns.Debug

-- "dev" is the firehose: per-message sync/book wire traffic. Above "debug" so normal
-- troubleshooting on "debug" isn't buried under it -- only set "dev" when chasing sync timing.
D.LEVELS = { off = 0, error = 1, info = 2, debug = 3, dev = 4 }
D.MAX = 500

-- ----- pure core -----
function D.LevelValue(name)
  if type(name) == "number" then return name end
  return D.LEVELS[name or "off"] or 0
end

-- Log a message of msgLevel given the configured currentLevel? (off logs nothing)
function D.ShouldLog(currentLevel, msgLevel)
  local cur = D.LevelValue(currentLevel)
  local m = D.LevelValue(msgLevel)
  if cur <= 0 then return false end
  return m >= 1 and m <= cur
end

-- "[clock] [LEVEL] msg"
function D.Format(clock, level, msg)
  local lvl = type(level) == "string" and level:upper() or tostring(level)
  return "[" .. tostring(clock or "") .. "] [" .. lvl .. "] " .. tostring(msg)
end

-- Append line to ring; trim oldest beyond max. Returns ring.
function D.Push(ring, line, max)
  ring[#ring + 1] = line
  max = max or D.MAX
  while #ring > max do table.remove(ring, 1) end
  return ring
end

-- ----- glue: public logging entry point -----
function ns.Log(level, msg)
  local cfg = ns.cfg or {}
  if not D.ShouldLog(cfg.debugLevel or "error", level) then return end
  local clock = (date and date("%H:%M:%S")) or (time and tostring(time())) or "?"
  local line = D.Format(clock, level, msg)
  ns.db = ns.db or {}
  ns.db.debugLog = ns.db.debugLog or {}
  D.Push(ns.db.debugLog, line, D.MAX)
  if level == "error" then ns.Print("|cffff5555[debug] " .. tostring(msg) .. "|r") end
end

-- Wrap fn so any error is logged (instead of being swallowed by the default handler).
function D.Guard(label, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then ns.Log("error", (label or "?") .. ": " .. tostring(err)) end
  end
end

-- ----- glue: copyable viewer -----
function D.Build()
  if D.frame then return D.frame end
  local f = CreateFrame("Frame", "AGNB_DebugFrame", UIParent, "BackdropTemplate")
  f:SetSize(560, 400); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
    f:SetBackdropColor(0.03,0.03,0.04,0.97); f:SetBackdropBorderColor(0.3,0.3,0.35,1)
  end
  local title = f:CreateFontString(nil,"OVERLAY","GameFontNormal")
  title:SetPoint("TOPLEFT",12,-10); title:SetText("AGNB Debug Log"); title:SetTextColor(1,0.85,0.4)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT",2,2)

  local scroll = CreateFrame("ScrollFrame", "AGNB_DebugScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -34); scroll:SetPoint("BOTTOMRIGHT", -30, 40)
  local eb = CreateFrame("EditBox", nil, scroll)
  eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetWidth(500)
  eb:SetAutoFocus(false); eb:EnableMouse(true)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  scroll:SetScrollChild(eb)
  f.edit = eb

  local hint = f:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT",12,14)
  hint:SetText("Click the text, Ctrl+A, Ctrl+C to copy.  /agnb debug clear  |  /agnb debug level <off|error|info|debug|dev>")
  D.frame = f
  return f
end

function D.Show()
  local f = D.Build()
  local lines = (ns.db and ns.db.debugLog) or {}
  -- Show first, then fill: an EditBox won't paint text set while it's hidden, so
  -- seeding after Show() guarantees the log is visible on the first open.
  f:Show()
  f.edit:SetText(table.concat(lines, "\n"))
  f.edit:SetCursorPosition(0)
end

function D.Clear()
  ns.db = ns.db or {}
  ns.db.debugLog = {}
  if D.frame and D.frame.edit then D.frame.edit:SetText("") end
  ns.Print("Debug log cleared.")
end

function D.SetLevel(name)
  name = name or "error"
  if D.LEVELS[name] == nil then ns.Print("debug levels: off, error, info, debug, dev"); return end
  ns.cfg = ns.cfg or {}
  ns.cfg.debugLevel = name
  ns.Print("Debug level set to " .. name)
end
