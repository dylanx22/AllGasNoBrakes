local _, ns = ...
ns = ns or __AGNB_NS
ns.Banner = ns.Banner or {}
local BN = ns.Banner

BN.QUIPS = { "Magnificent.", "Inspiring.", "Textbook.", "Beautiful.", "A masterclass.", "Chef's kiss." }

-- A wipe: combat has ended and the whole raid (>= 100% by default) is dead.
function BN.DetectWipe(deadCount, raidSize, combatEnded, fraction)
  if not combatEnded then return false end
  if not raidSize or raidSize <= 0 then return false end
  return (deadCount / raidSize) >= (fraction or 1.0)
end

function BN.Quip(rng)
  local n = #BN.QUIPS
  local r = rng and rng() or math.random()
  local idx = math.floor(r * n) + 1
  if idx > n then idx = n end
  return BN.QUIPS[idx]
end

-- "<brand> - <zone> - <boss> - N dead in Ys. <quip>" (boss omitted if nil).
function BN.StatLine(brand, zone, boss, deaths, seconds, quip)
  local parts = { brand or "All Gas No Brakes", zone or "the raid" }
  if boss and boss ~= "" then parts[#parts + 1] = boss end
  local head = table.concat(parts, " - ")
  return head .. " - " .. deaths .. " dead in " .. seconds .. "s. " .. (quip or "")
end

-- ----- WoW glue: banner frame + fade + wipe trigger -----
local STYLES = {
  gold    = { border = {0.42,0.33,0.15}, bg = {0.08,0.06,0.03}, text = {1,0.85,0.4} },
  redline = { border = {0.88,0.02,0.0},  bg = {0.03,0.03,0.04}, text = {1,1,1} },
  hazard  = { border = {0.95,0.76,0.05}, bg = {0.10,0.10,0.10}, text = {0.96,0.96,0.96} },
  frost   = { border = {0.18,0.44,0.66}, bg = {0.04,0.07,0.12}, text = {0.75,0.9,1} },
}

local function build()
  if BN.frame then return BN.frame end
  local f = CreateFrame("Frame", "AGNB_Banner", UIParent, "BackdropTemplate")
  -- Sit above the Release Spirit dialog (which pops top-center on death) instead
  -- of being half-hidden behind it.
  f:SetFrameStrata("HIGH"); f:SetSize(560, 64); f:SetPoint("TOP", 0, -90); f:Hide()
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=2 })
  end
  f.tag = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  f.tag:SetPoint("TOP", 0, -10)
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.sub:SetPoint("TOP", f.tag, "BOTTOM", 0, -4)
  BN.frame = f
  return f
end

-- ctx: { tagline, statline }
function BN.Show(ctx)
  local cfg = ns.cfg or {}
  if not (cfg.wipeBannerEnabled ~= false) then return end
  local f = build()
  local style = STYLES[cfg.wipeBannerStyle or "gold"] or STYLES.gold
  if f.SetBackdrop then
    f:SetBackdropColor(style.bg[1], style.bg[2], style.bg[3], 0.92)
    f:SetBackdropBorderColor(style.border[1], style.border[2], style.border[3], 1)
  end
  f.tag:SetText("\194\187  " .. (ctx.tagline or cfg.wipeTagline or "ALL GAS, NO BRAKES") .. "  \194\171")
  f.tag:SetTextColor(style.text[1], style.text[2], style.text[3])
  f.sub:SetText(ctx.statline or "")
  f:SetAlpha(1); f:Show()
  if cfg.wipeBannerSound ~= false and PlaySound then PlaySound(8959, "Master") end
  local secs = cfg.wipeBannerSeconds or 4
  ns.After(secs, function()
    if UIFrameFadeOut then UIFrameFadeOut(f, 0.6, 1, 0) end
    ns.After(0.7, function() f:Hide() end)
  end)
end

-- Build the local wipe context from the current pull and fire the banner.
function BN.FireWipe(boss)
  local cfg = ns.cfg or {}
  local pull = ns.Tracking and ns.Tracking.pull
  local deaths = pull and pull.dead or 0
  local secs = 0
  if pull and pull.startTime then secs = math.max(0, math.floor((GetTime() - pull.startTime))) end
  local brand = ns.Brand.Resolve(cfg, GetGuildInfo and GetGuildInfo("player") or nil)
  local zone = (GetRealZoneText and GetRealZoneText()) or "the raid"
  local statline = BN.StatLine(brand, zone, boss, deaths, secs, BN.Quip())
  local ctx = { tagline = cfg.wipeTagline, statline = statline }
  ns.Log("info", "wipe banner: boss=" .. tostring(boss) .. " deaths=" .. tostring(deaths))
  BN.Show(ctx)
  if ns.Sync and ns.Sync.MaybeBroadcastBanner then ns.Sync.MaybeBroadcastBanner(ctx) end
end
