local _, ns = ...
ns = ns or __AGNB_NS
ns.AntiPrize = ns.AntiPrize or {}
local AP = ns.AntiPrize

-- The anti-prize is OPT-IN: you can't put someone on the hook for gold unless they
-- chose to join. This registry tracks who's in (synced across addon users), so every
-- client computes the same pot from the same participant set.
AP.optedIn = AP.optedIn or {}   -- short player name -> true

local function myName()
  return ns.MyName or (UnitName and UnitName("player")) or nil
end

-- Join prompt shown to group members when an admin pushes a pot invite.
if StaticPopupDialogs then
  StaticPopupDialogs["AGNB_POT_INVITE"] = {
    text = "%s is running the AGNB anti-prize pot this raid.\nJoin? (Most deaths owes the pot; gold is settled manually.)",
    button1 = "Join", button2 = "No thanks",
    OnAccept = function() if ns.AntiPrize then ns.AntiPrize.SetSelf(true) end end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
end

-- Only the raid leader / assist (or a dev, or the delegated AGNB admin) may push invites.
local function canInvite()
  if ns.db and ns.db.designatedAdmin and ns.db.designatedAdmin == myName() then return true end
  local isL = UnitIsGroupLeader and UnitIsGroupLeader("player") or false
  local isA = UnitIsGroupAssistant and UnitIsGroupAssistant("player") or false
  local tag; if BNGetInfo then local _, bt = BNGetInfo(); tag = bt end
  return ns.Summary and ns.Summary.CanBroadcast(isL, isA, myName(), tag) or false
end
AP.CanInvite = canInvite

-- Set passed to Ledger.Settlement so only opted-in players are in the pot.
function AP.Participants() return AP.optedIn end

-- Drop everyone except the local player (used when clearing demo data so mock
-- opt-ins don't linger in the real registry).
function AP.ResetToSelf()
  AP.optedIn = {}
  local me = myName()
  if me and ns.cfg and ns.cfg.antiPrizeOptIn then AP.optedIn[me] = true end
end

function AP.Count()
  local n = 0
  for _ in pairs(AP.optedIn) do n = n + 1 end
  return n
end

-- Record another player's opt-in state (received over sync).
function AP.OnSync(player, optedIn)
  if not player then return end
  AP.optedIn[player] = optedIn and true or nil
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

-- Tell the group our current opt-in state.
function AP.Broadcast()
  local chan = ns.Sync and ns.Sync.Channel and ns.Sync.Channel()
  if not (chan and C_ChatInfo) then return end
  local opted = ns.cfg and ns.cfg.antiPrizeOptIn
  C_ChatInfo.SendAddonMessage(ns.Sync.PREFIX, "OI|" .. (opted and "1" or "0"), chan)
end

-- Admin: invite every addon user in the group to join the anti-prize pot.
function AP.Invite()
  if not canInvite() then ns.Print("Only the raid leader/assist can invite to the pot.") return end
  local chan = ns.Sync and ns.Sync.Channel and ns.Sync.Channel()
  if not (chan and C_ChatInfo) then ns.Print("Join a group to invite players to the pot.") return end
  C_ChatInfo.SendAddonMessage(ns.Sync.PREFIX, "OINV|" .. (myName() or "?"), chan)
  AP.SetSelf(true)  -- the inviter joins the pot too
  ns.Print("Invited the group to the anti-prize pot.")
end

-- Receive a pot invite: prompt to join (unless already in).
function AP.OnInvite(fromName)
  if ns.cfg and ns.cfg.antiPrizeOptIn then return end
  if StaticPopup_Show then StaticPopup_Show("AGNB_POT_INVITE", fromName or "The raid") end
end

-- The local player's opt-in choice: persist, update the registry, announce it.
function AP.SetSelf(optedIn)
  optedIn = optedIn and true or false
  if ns.cfg then ns.cfg.antiPrizeOptIn = optedIn end
  local me = myName()
  if me then AP.optedIn[me] = optedIn or nil end
  AP.Broadcast()
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

ns.OnInit(function()
  local me = myName()
  if me and ns.cfg and ns.cfg.antiPrizeOptIn then AP.optedIn[me] = true end
  -- announce our state once comms are up, and whenever the group changes so
  -- newcomers learn everyone's choice.
  if C_Timer and C_Timer.After then C_Timer.After(3, AP.Broadcast) end
  local f = CreateFrame("Frame")
  f:RegisterEvent("GROUP_ROSTER_UPDATE")
  f:SetScript("OnEvent", ns.Debug.Guard("AntiPrize.OnEvent", function() AP.Broadcast() end))
end)
