# Changelog

All notable changes to **All Gas No Brakes: Death Tracker** are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.2.1] - 2026-06-20

### Added
- **Raid Info tab** — see every group member, who's running the addon and which version
  (green = current, yellow = different), each person's role, and who holds the Book admin.
- **Pug exclusion** — tag a raid as a pug (`/agnb pug` or the History view) to keep it in
  Tonight/History but leave it out of your All-Time stats.
- **Auto-rounds** (The Book) — optionally open a new betting round automatically between pulls.
  Off by default (ready-check opening stays the default); toggle it in Settings or with the
  in-window **Auto-rounds** button. Opens are driven off combat ending and only inside raids.
- **One-click opt-in** — when an admin opens betting, non-participants get a single prompt to
  join wagering instead of silently seeing nothing.
- A **Raid Hot Seat** button in the Book admin row (previously slash-only).

### Changed
- **The Book is raids-only** — betting rounds/popups no longer open in 5-man dungeons.
- **One bet per round** — a placed bet locks and can't be changed mid-pull.
- Reworked the Book window for clarity: admin controls grouped at the top, a **YOUR BETS**
  section, a plainer status line, and "who runs the Book" shown top-right.

### Fixed
- Spell names now show correctly instead of a raw spell ID number.
- Falling/lava damage is no longer logged as phantom deaths.
- The death log no longer shows the same death 2–3× (clock-skew-proof dedup by local receipt
  time + killcam reconciliation); a one-time cleanup scrubs old duplicate/phantom rows and
  re-resolves old numeric spell names in saved data.
- UI button errors now surface in the debug log instead of failing silently.
- Hardened settlement and death sync against malformed/missing data: a missing Hot Seat
  outcome no longer mis-pays, broadcast outcomes are validated before overriding the local
  result, the death-receive path is nil-guarded, and settlement timer callbacks are guarded.

## [1.2.0] - 2026-06-19

### Added
- **Raid Hot Seat** (The Book): a whole-raid wager. At raid start the leader opens a
  market (`/agnb book raidhs`) on one randomly-dealt raider — everyone else bets
  Over/Under on that person's total deaths for the night. Pari-mutuel (no house, like
  Over/Under), locks at the first pull, and settles into the end-of-raid Book
  settlement. A popup floats at open for placing the bet; the subject can't bet on
  themselves.
- **Hot Seat** (The Book): a fourth wager. Each pull deals every raider one of a
  few random targets; bet Survives or Dies on whether they make it. Bettors dealt
  the same target who pick opposite sides are matched head-to-head and settled in
  real gold at odds drawn from the target's death history — no house needed, the
  pair funds itself, and the odds set the stake handicap. A between-pulls popup
  shows your target, the odds, your risk/win, and their stats. Unmatched bets are
  refunded ("no match this round").
- **Book Admin report**: a settlement view that lists who pays whom and auto-updates
  as payments are detected, with a per-player bet-by-bet audit.
- **Mid-raid catch-up**: a player who loads in during a raid is whispered the recent
  death log so their leaderboards fill in.
- **Dev round simulator** (Settings → Advanced → Dev, mock data only): "Sim: open
  round" and "Sim: resolve pull" drive a full 25-man round solo — popup, NPC bets,
  and settlement — for testing without a raid. Dev tools are unlocked per-character
  with `/agnb dev on`.

### Changed
- **Death sync is now leader-only** — only the raid leader/assist broadcasts deaths,
  eliminating the burst of duplicate addon traffic during a wipe.
- **Round outcomes are admin-authoritative** — clients adopt the book runner's
  resolved result, fixing "numbers out of sync" on trash pulls.
- **Settlement rounds to whole gold** so no one ever has to trade silver/copper; the
  bet-by-bet audit keeps the exact amounts.
- Combat-log handling no longer allocates per event, reducing stutter in heavy raid
  combat; stored death timelines are pruned across raids to keep saved data small.

### Fixed
- The Hot Seat bet popup showed `0g` risk/win — it now shows the real gold amounts.
- Hot Seat results now appear in the betting window, not only in chat.
- 5-man (party) play no longer drops the local player from the betting roster.
- Bets now **lock once placed** (one per round) — no re-clicking to change your pick,
  and no changing your bet after a death lands mid-pull. Your own bet is also now
  counted correctly in your settlement.

## [1.1.0] - 2026-06-19

### Added
- **Interactive guided tour** (`/agnb tour`): a 13-step walkthrough that drives
  the real window view by view with a highlight ring, covering the boards,
  killcams, insights, overlays, The Book, history/export, reports, and settings.
  Offered on first run and from the Help page.
- **Admin-only "All math" pane** in The Book: the whole raid's bet-by-bet wager
  math in a scrollable view, not just your own lines.

### Changed
- Admin-only Book settings (stakes, draft ante, auto-line window, ready-check
  auto-open, collusion watch) are greyed and locked for non-admins; personal
  settings (bankroll cap, opt-in, buy-in) stay editable for everyone.
- Sample/preview data (used by the tour) now includes killcam timelines, so the
  Death Log killcam is populated when exploring with mock data.

### Fixed
- Settings edit boxes now show their saved value after a reload (a stored raid
  name could appear blank even though it was still in effect).
- Tightened Settings labels so they no longer overlap their input fields.
- The Book's admin row no longer overlaps: the appoint-admin picker sits clear of
  the "All math" button, and the action buttons size to fit narrow windows.
- Closing the window during the guided tour now ends the tour instead of leaving
  the highlight square on screen.

## [1.0.0] - 2026-06-18

First public CurseForge release.

### Added
- MRT-style tabbed Settings (Tracking / Chat / Overlays / Gold & The Book /
  Advanced) replacing the single scrolling options list, with inline "?" help
  tooltips on every setting.
- In-window **Help** page (feature guide) and a **first-run welcome** with an
  "explore with sample data" preview and a 3-item quick-setup.
- **Delegated AGNB admin**: a raid leader/assist can appoint a non-leader to run
  the Book, anti-prize, and settlement without granting WoW assist.

### Changed
- Renamed the "The Show" section to **Overlays** throughout the UI.
- Empty list views now show a short explanatory hint instead of blank rows.

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
