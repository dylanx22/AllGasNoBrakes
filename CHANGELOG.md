# Changelog

All notable changes to **All Gas No Brakes: Death Tracker** are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-06-18

First public CurseForge release. Built for Burning Crusade Classic (2.5.5).

### Added
- MRT-style tabbed Settings (Tracking / Chat / Overlays / Gold & The Book /
  Advanced) replacing the single scrolling options list, with inline "?" help
  tooltips on every setting.
- In-window **Help** page (feature guide) and a **first-run welcome** with an
  "explore with sample data" preview and a 3-item quick-setup.
- **Delegated AGNB admin**: a raid leader/assist can appoint a non-leader to run
  the Book, anti-prize, and settlement without granting WoW assist.
- **Crowned-skull minimap icon** (and addon-list icon) drawn from the project
  logo, replacing the placeholder ability texture.

### Changed
- Renamed the "The Show" section to **Overlays** throughout the UI.
- Empty list views now show a short explanatory hint instead of blank rows.

### Fixed
- Minimap button now opens on the first click instead of needing two.
- Settings now reflect changes (such as opt-in) without a reload, and the
  first-run quick-setup applies its choices immediately.

### Removed
- Cleared the hardcoded developer BattleTag from the shipped code.

## [0.2.0] - 2026-06-18

The "Showtime / The Book / History" release.

### Added
- **Wipe banner** ("ALL GAS, NO BRAKES") on a full wipe, with four styles
  (gold / redline / hazard / frost) and an optional sound.
- **End-of-Raid screen** (podium + Lowlights Reel) that auto-opens after a
  final-boss kill, with a one-click post-to-chat.
- **Report types**: `/agnb report <tonight|alltime|lowlights|ledger>` now route
  to the matching builder (the argument was previously ignored).
- **The Book (wagering)** — opt-in Over/Under on pull deaths, a First Blood pool,
  and a commit-reveal Death Draft, with tamper-resistant bet locking and a
  reconciled gold settlement (ledger + pre-filled mail; addons cannot move gold).
- **Raid History** browser with drill-down (raid -> night -> killcam) bucketed by
  instance lockout, plus a **Killcam** popup from any Death Log row.
- **Export**: a selectable Discord-ready text block and a screenshot scorecard.
- **Insights**: Per-Boss breakdown and a Pull Timeline view.
- **Achievements / earned death titles**, milestone and streak callouts.
- **White-label branding** — set a raid/group name to override the guild name in
  the window title, reports, and banner.
- **Single-window UI**: a sectioned sidebar (Leaderboards / Overlays / The Book /
  Insights / History / Actions) with Settings and Post Report embedded in-window.
- Empty-state hints on every list view so a first-run window explains itself.

### Changed
- Minimap icon now uses the valid brand texture (it previously rendered black on
  the Anniversary client).
- Admin settlement lines show the remaining amount owed so they reconcile with
  the outstanding header.

## [0.1.0]

- Initial death tracking: killing-blow attribution, environmental deaths, pull
  lifecycle, wipe-cascade forgiveness, Tonight / All-Time / Abilities leaderboards,
  raid-wide sync, snark announcements, report-to-chat, and the anti-prize ledger.
