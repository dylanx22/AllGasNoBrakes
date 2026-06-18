# All Gas No Brakes: Death Tracker

**Your raid is going to wipe. This addon makes it funny.**

All Gas No Brakes reads your combat log and turns every death into a leaderboard
and a punchline. It keeps track of who's dying the most, what keeps killing them,
and who drew First Blood (again), then hands you the receipts. If you want it to,
it'll also roast everyone in the process.

It works fine solo, straight off your own combat log. Get a few other raiders
running it and it gets better: their deaths sync over to you automatically, with
nothing to set up.

---

## Features

### 📊 Leaderboards
- **Tonight** and **All-Time** death boards, class-colored, with killing-blow
  attribution (who/what actually landed the finishing hit).
- **Deadliest Abilities** board: the spells and mobs ending the most raiders.
- **Death Log**: every death. Click one for an instant **killcam**.

### 🎬 Overlays
- A full-wipe **"ALL GAS, NO BRAKES" banner** in four styles (gold, redline,
  hazard, frost).
- An **End-of-Raid screen**: a podium plus a "Lowlights Reel" (top feeder,
  deadliest ability, first blood, body count) that auto-opens after the final boss.

### 🎯 The Book (opt-in wagering: a ledger, not real currency)
- **Over/Under** on deaths per pull, a **First Blood** pool, and a commit-reveal
  **Death Draft**. Bets lock at pull start and resolve deterministically from the
  shared death log, so they can't be fudged after the fact.

### 🔎 Insights & History
- **Per-Boss** and **Pull Timeline** breakdowns.
- **Raid History** browser, bucketed by instance lockout, drilling all the way
  down to a per-death killcam.
- **Export** a raid as Discord-ready text or a screenshot scorecard.

### 😈 The comedy layer (all configurable, and nothing hits chat unless you turn it on)
- Snarky death announcements, earned **death titles**, combo-breaker and
  death-streak callouts, and optional death sounds.
- An opt-in gold **"anti-prize" ledger** that tallies who owes the pot per death
  and pre-fills a settlement mail for you. *(WoW addons can't move gold, so this
  is just a tally, and you only owe anything if you actually join the pot.)*

---

## Getting started

1. Install and `/reload`.
2. Click the **minimap skull** (or type `/agnb`) to open the window.
3. Raid. Die. Watch the boards fill in.

Everything is private by default. Nothing gets posted to chat until you turn on an
announcement or pick a report channel in **Settings**.

## Commands
- `/agnb` or `/deaths`: toggle the window
- `/agnb report <tonight|alltime|lowlights|ledger>`: post a report to chat
- `/agnb summary`: open the End-of-Raid screen
- `/agnb book`: open the wagering panel (enable wagering in Settings first)
- `/agnb invite`: (leader/assist) invite the group to the gold pot
- `/agnb void`: remove the most recent pull's deaths
- `/agnb config`: open Settings
- `/agnb debug`: open the copyable debug log

## Notes
- Works on **TBC Classic / Anniversary**.
- **Wipe-cascade forgiveness**: deaths after more than half the raid is already
  down don't count toward shame (configurable).
- **White-label**: set a raid/group name in Settings to override the guild name in
  the window, reports, and banner. Handy for pug weeks.

---

## Feedback & source
Open-source under the **MIT License**. Bug reports and pull requests are welcome
on the linked Source/Issues repo. I read the comments below, so drop a line and
tell me which death was the funniest.
