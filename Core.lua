local ADDON, ns = ...
ns = ns or __AGNB_NS

ns.name = ADDON or "AllGasNoBrakes"
ns.version = "1.2.0"
ns.modules = {}            -- init hooks, registered by other modules
ns.slash = {}              -- subcommand -> function(args)

-- Register a function to run once SavedVariables are loaded.
function ns.OnInit(fn)
  ns.modules[#ns.modules + 1] = fn
end

-- Print a prefixed message to the default chat frame.
function ns.Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd966[AGNB]|r " .. tostring(msg))
  end
end

-- Run fn after `sec` seconds via C_Timer, or immediately if C_Timer is unavailable
-- (e.g. the headless test harness). One guarded entry point so call sites stay consistent.
function ns.After(sec, fn)
  if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end

local frame = CreateFrame and CreateFrame("Frame") or nil
if frame then
  frame:RegisterEvent("ADDON_LOADED")
  frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ns.name then
      AGNB_DB = AGNB_DB or {}
      ns.db = AGNB_DB
      for _, fn in ipairs(ns.modules) do
        local ok, err = pcall(fn)
        if not ok then ns.Print("init error: " .. tostring(err)) end
      end
      ns.Print("loaded v" .. ns.version .. ". Type /agnb for commands.")
    end
  end)
end
