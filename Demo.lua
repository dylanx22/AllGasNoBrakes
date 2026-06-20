local _, ns = ...
ns = ns or __AGNB_NS
ns.Demo = ns.Demo or {}
local D = ns.Demo

local DEMO_RAID = "__demo__"

-- ----- pure: synthetic death generator -----
-- Longer mob/ability names included so the window's column sizing gets exercised.
local ABILITIES = { "Shadow Bolt", "Cleave", "Fireball", "Pyroblast", "Shadow Nova",
                    "Arcane Missiles", "Flame Wreath", "Gravity Lapse", "Shadow of Death" }
local SOURCES   = { "Prince Malchezaar", "Gruul the Dragonkiller", "Magtheridon",
                    "Trash Pack", "Lady Vashj", "Kael'thas Sunstrider", "High King Maulgar" }
local BOSSES    = { "Prince Malchezaar", "Gruul the Dragonkiller", "Magtheridon" }
local ENVTYPES  = { "Lava", "Fire", "Fall" }
-- Color for the killcam timeline: who topped the player off and what hit them on
-- the way down, leading into the lethal blow.
local HEALERS   = { "Healbot", "Mendmaster", "Lightbringer", "Holysmokes", "Moonfyre" }
local HEALS     = { "Flash Heal", "Greater Heal", "Healing Wave", "Renew", "Regrowth" }
local INCOMING  = { "Melee", "Shadow Bolt", "Cleave", "Flame Buffet", "Crushing Blow" }

-- Canned names used to pad/replace the roster so the demo always lists a full,
-- realistic-sized raid (>= 25 so the leaderboard scrolls).
local CANNED = { "Pyroclast", "Grug", "Backstabz", "Healbot", "Dotmaster", "Tankzilla",
  "Lightbringer", "Sneakerz", "Moonfyre", "Bonkers", "Stabbathy", "Hexenhammer",
  "Frostbyte", "Cindersnap", "Grimtotem", "Voidwalkz", "Manablast", "Ragebourne",
  "Holysmokes", "Direwolfe", "Shadowmeld", "Pyrothena", "Bearforce", "Felreaver",
  "Crittergib", "Mendmaster", "Arcanika", "Thornvel", "Skullcrush", "Dotwarts" }

local function pickFrom(list, rng)
  local i = math.floor(rng() * #list) + 1
  if i > #list then i = #list end
  return list[i]
end

-- A short, believable killcam timeline ending in the lethal blow at `deathTime`,
-- so the killcam view/popup has real rows to render in demos. Derived purely from
-- `seq` (no rng draws) so it never perturbs the deterministic death sequence.
local function makeKillcam(seq, deathTime, ability, source, isEnv)
  local function amt(base, k) return base + ((seq * 37 + k * 53) % 600) end
  local function pick(list, k) return list[((seq + k) % #list) + 1] end
  local src = isEnv and "Environment" or source
  if isEnv then
    return {
      { t = deathTime - 6, kind = "dmg",  source = src, spell = ability, amount = amt(900, 1) },
      { t = deathTime - 4, kind = "heal", source = pick(HEALERS, 2), spell = pick(HEALS, 1), amount = amt(1500, 2) },
      { t = deathTime - 2, kind = "dmg",  source = src, spell = ability, amount = amt(1100, 3) },
      { t = deathTime,     kind = "dmg",  source = src, spell = ability, amount = amt(2600, 4) },
    }
  end
  return {
    { t = deathTime - 7.5, kind = "dmg",  source = src,             spell = pick(INCOMING, 1), amount = amt(800, 1) },
    { t = deathTime - 6,   kind = "heal", source = pick(HEALERS, 2), spell = pick(HEALS, 2),    amount = amt(1700, 2) },
    { t = deathTime - 4.2, kind = "cast", source = src,             spell = ability },
    { t = deathTime - 3,   kind = "dmg",  source = src,             spell = pick(INCOMING, 3), amount = amt(1200, 3) },
    { t = deathTime - 1.4, kind = "heal", source = pick(HEALERS, 4), spell = pick(HEALS, 4),    amount = amt(1400, 4) },
    { t = deathTime,       kind = "dmg",  source = src,             spell = ability,            amount = amt(3200, 5) },
  }
end

-- Build one death record for `player` at sequence position `seq`. When forceCounted
-- is true the death is never wipe-cascade (so demo counts match exactly).
local function makeDeath(seq, player, rng, forceCounted)
  local isEnv = rng() < 0.15
  local ability = isEnv and pickFrom(ENVTYPES, rng) or pickFrom(ABILITIES, rng)
  local source = isEnv and "Environment" or pickFrom(SOURCES, rng)
  local cls = (not forceCounted and rng() < 0.12) and "wipeCascade" or "counted"
  local time = seq * 5
  return {
    player = player, time = time, ability = ability, sourceName = source,
    isEnv = isEnv, envType = isEnv and ability or nil, boss = pickFrom(BOSSES, rng),
    pullId = math.floor((seq - 1) / 4) + 1, classification = cls,
    killcam = makeKillcam(seq, time, ability, source, isEnv),
  }
end

-- names: array of player names. count: how many deaths. rng() in [0,1) (defaults math.random).
-- Players are sampled from a SKEWED weight (earlier names die more often), so a real
-- run shows a realistic spread -- a couple of heavy feeders, a tied middle, a quiet
-- tail -- instead of one death apiece. Deterministic given a fixed rng.
function D.SyntheticDeaths(names, count, rng)
  rng = rng or math.random
  local weights, total = {}, 0
  for i = 1, #names do weights[i] = #names - i + 1; total = total + weights[i] end
  local function pickPlayer()
    local r = rng() * total
    local acc = 0
    for i = 1, #names do
      acc = acc + weights[i]
      if r < acc then return names[i] end
    end
    return names[#names]
  end
  local out = {}
  for i = 1, count do out[i] = makeDeath(i, pickPlayer(), rng) end
  return out
end

-- Give every name in `names` a deaths count in [minC, maxC] (inclusive) and emit
-- that many counted deaths. Yields a full roster where everyone is on the board
-- with varied, tie-rich counts. Deterministic given a fixed rng.
function D.SyntheticDeathsVaried(names, minC, maxC, rng)
  rng = rng or math.random
  local span = maxC - minC + 1
  local out, seq = {}, 0
  for _, player in ipairs(names) do
    local c = minC + math.floor(rng() * span)
    if c > maxC then c = maxC end
    for _ = 1, c do
      seq = seq + 1
      out[#out + 1] = makeDeath(seq, player, rng, true)
    end
  end
  return out
end

-- ----- glue: dev gate, guild names, load/clear -----
function D.IsDev()
  local name = UnitName and UnitName("player") or nil
  local tag = nil
  if BNGetInfo then local _, bt = BNGetInfo(); tag = bt end
  return ns.Summary.CanBroadcast(false, false, name, tag)
end

-- Real guild member names (short form). Falls back to canned names if not guilded
-- or the roster hasn't loaded yet.
function D.GuildNames()
  local names = {}
  if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
  elseif GuildRoster then GuildRoster() end
  local n = (GetNumGuildMembers and GetNumGuildMembers()) or 0
  for i = 1, n do
    local full = GetGuildRosterInfo and GetGuildRosterInfo(i)
    if full then names[#names + 1] = full:match("^[^-]+") or full end
  end
  if #names == 0 then
    names = CANNED
  end
  return names
end

-- Exactly `n` unique demo names: real guild names first, padded with canned ones.
function D.DemoNames(n)
  local names, seen = {}, {}
  for _, nm in ipairs(D.GuildNames()) do
    if not seen[nm] and #names < n then names[#names + 1] = nm; seen[nm] = true end
  end
  for _, nm in ipairs(CANNED) do
    if not seen[nm] and #names < n then names[#names + 1] = nm; seen[nm] = true end
  end
  return names
end

D.raidId = DEMO_RAID

function D.Load()
  if not (D.IsDev() or D._forcePreview) then ns.Print("Mock data is dev-only.") return end
  D.store = ns.DB.NewStore()
  -- 25 raiders, each with 1-6 deaths: a full board with plenty of ties.
  local names = D.DemoNames(25)
  local deaths = D.SyntheticDeathsVaried(names, 1, 6)
  for _, dth in ipairs(deaths) do ns.DB.RecordDeath(D.store, DEMO_RAID, dth) end
  local raid = D.store.raids[DEMO_RAID]
  if raid then
    raid.zone = (GetRealZoneText and GetRealZoneText()) or "Demo Raid"
    raid.startTime = 0
  end
  -- opt every mock raider into the anti-prize so the pot/settlement is visible
  if ns.AntiPrize then for _, nm in ipairs(names) do ns.AntiPrize.optedIn[nm] = true end end
  -- seed a few mock betting records so the Book's winners/losers board has data
  local recs = { { 5, 1, 45 }, { 4, 2, 22 }, { 3, 2, 8 }, { 2, 3, -12 }, { 1, 4, -25 }, { 0, 4, -40 } }
  for i, rec in ipairs(recs) do
    local nm = names[i]
    if nm then for _ = 1, rec[1] do ns.DB.RecordBetResult(D.store, nm, true, 0) end
      for _ = 1, rec[2] do ns.DB.RecordBetResult(D.store, nm, false, 0) end
      D.store.bets[nm].net = rec[3] end
  end
  -- seed a session ledger + computed settlement so the Book's settlement panel demos
  if ns.Book then
    ns.Book.rt = ns.Book.rt or { history = {} }
    ns.Book.rt.ledger = {
      { seq = 1, boss = "Hydross the Unstable", line = 2.5, lockTime = 1, endTime = 9,
        ouReveals = { [names[1]] = "over", [names[2]] = "under", [names[3]] = "over" },
        ouOutcome = "over", ouStake = 50000, ouCount = 4,
        fbReveals = { [names[1]] = names[4], [names[2]] = names[5] },
        fbOutcome = names[4], fbStake = 50000 },
    }
    if ns.Settlement and ns.Settlement.Compute then ns.Settlement.Compute() end
  end
  D.active = true
  ns.Log("info", "mock data loaded: " .. #deaths .. " deaths")
  ns.Print("Mock data loaded (" .. #deaths .. " deaths, " .. #names .. " names). '/agnb mock off' to clear.")
  if ns.UI then ns.UI.Refresh() end
end

-- Public sample-data path for the first-run tour. Same isolated store as Load(),
-- but without the dev gate so any new user can preview a populated window.
function D.LoadPreview()
  local was = D._forcePreview; D._forcePreview = true
  D.Load()
  D._forcePreview = was
end

function D.Clear()
  D.active = false
  if ns.Book and ns.Book.RestoreSimConfig then ns.Book.RestoreSimConfig() end
  if ns.AntiPrize then ns.AntiPrize.ResetToSelf() end
  ns.Print("Mock data cleared.")
  if ns.UI then ns.UI.Refresh() end
end
