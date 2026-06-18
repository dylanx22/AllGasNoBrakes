# All Gas No Brakes: Death Tracker

A World of Warcraft: TBC Classic (Anniversary) addon that tracks raid deaths with
session and all-time leaderboards, optional raid-wide sync, and a configurable
layer of comedy -- snarky announcements, earned death titles, a post-raid
"Lowlights Reel", and a gold "anti-prize" ledger.

## Install
Easiest: install from CurseForge (the packaged download is a single ready-to-drop
`AllGasNoBrakes` folder), or use the CurseForge app.

From source (this repo keeps the addon files at the root for packaging):
1. Download/clone this repo.
2. Make a folder named `AllGasNoBrakes` in your client's AddOns folder, e.g.
   `World of Warcraft/_anniversary_/Interface/AddOns/AllGasNoBrakes/` (TBC
   Anniversary) or under `_classic_/Interface/AddOns/`.
3. Copy the addon files into it: every `*.lua`, `AllGasNoBrakes.toc`, and the
   `Media/` folder. The repo-only folders (`tests/`, `docs/`, `images/`) aren't needed.
4. Restart the game or `/reload`. Enable "Load out of date AddOns" if prompted.

## Commands
- `/agnb` or `/deaths` -- toggle the window
- `/agnb report <tonight|alltime|lowlights|ledger>` -- post a report to your channel
- `/agnb summary` -- open the end-of-raid screen
- `/agnb ledger` -- post the anti-prize settlement
- `/agnb invite` -- (leader/assist) prompt everyone in the group to join the pot
- `/agnb book [open|draft|join|lock]` -- wagering: open it with no arg for the panel;
  `open` a per-pull Over/Under + First Blood round, `draft`/`join`/`lock` the Death
  Draft (needs "Enable wagering" in Settings)
- `/agnb void` -- remove the most recent pull's deaths
- `/agnb config` -- open options (also the **Settings** button in the window)
- `/agnb debug` -- open the copyable debug log (`debug clear`, `debug level <off|error|info|debug>`)

## Options
The options panel (Settings button or `/agnb config`) covers the death/sound/sync
toggles plus **report channel** (self/say/party/raid/guild), **report depth**
(top 3/5/10/everyone), **announce channel**, and a **raid / group name** override
(blank uses your guild name). The panel scrolls and covers every feature
(tracking, announcements, reports, wipe banner, ledger, advanced).

## Notes
- Works solo from your combat log; auto-syncs with raiders who also run it.
- Wipe-cascade deaths (after >50% of the raid is dead) are forgiven by default.
- The gold anti-prize is a **ledger only** -- WoW addons cannot move gold -- and is
  **opt-in**: you only owe the pot if you join it (Settings > "Join the anti-prize
  gold pot"). Tracking and leaderboards still include everyone; only the gold
  obligation is opt-in.
- The window title, reports, and wipe-banner stat line use your **guild name** by
  default; set a Brand name in options to override (handy for pug weeks).
- The wipe banner has four styles (gold/redline/hazard/frost) and shows on a full
  wipe. The end-of-raid screen auto-opens after a final boss kill.

## Development
Unit tests run under standalone Lua (no WoW required):

    lua tests/run.lua

(On a machine where `lua` is not on PATH, use the full path to your Lua 5.x binary.)
