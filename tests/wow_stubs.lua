-- Minimal stub globals so addon modules load under standalone Lua.
-- Only stubs needed by pure-logic load paths; richer behavior is injected per-test.

local clock = 0
function GetTime() return clock end
function _advance(dt) clock = clock + (dt or 1); return clock end

-- C_Timer.After: tests run callbacks synchronously unless a test overrides it.
C_Timer = { After = function(_, fn) if type(fn) == "function" then fn() end end }

-- CreateFrame returns a no-op frame supporting the chained calls modules use.
local function noop() end
local frameMeta = {}
frameMeta.__index = function() return function(...) return setmetatable({}, frameMeta) end end
function CreateFrame() return setmetatable({}, frameMeta) end

DEFAULT_CHAT_FRAME = { AddMessage = noop }

-- Class color table (subset); modules look up by uppercase class token.
RAID_CLASS_COLORS = setmetatable({
  MAGE   = { colorStr = "ff69ccf0" },
  WARRIOR= { colorStr = "ffc79c6e" },
  ROGUE  = { colorStr = "fffff569" },
  PRIEST = { colorStr = "fff0f0f0" },
  WARLOCK= { colorStr = "ff9482c9" },
}, { __index = function() return { colorStr = "ffffffff" } end })

-- Addon comms / chat: capture sends so tests can inspect them.
_sent = {}
function SendChatMessage(msg, chan) _sent[#_sent+1] = { msg = msg, chan = chan } end
C_ChatInfo = {
  RegisterAddonMessagePrefix = noop,
  SendAddonMessage = function(prefix, msg, chan) _sent[#_sent+1] = { prefix = prefix, msg = msg, chan = chan } end,
}

function IsInRaid() return true end
function IsInGroup() return true end
function GetNumGroupMembers() return 25 end
