# Volume

Personal productivity tracker for macOS. Plan tasks with a time estimate, log the
actual time when you finish, and beat last week's focused minutes.

Native SwiftUI app — no server, no browser, no cloud. Data lives in a single
SQLite file at `~/Library/Application Support/Volume/volume.db`.

## Views

- **Today** — quick-add a task with an estimate (`45m`, `1h30`, `1:30`, `90` all work).
  Hit **Done** on a task and it asks how long it actually took. Green badge = within
  estimate, red = over. Also: **Log past work** (retroactive tasks) and **Log call**.
- **Week** — focused minutes this week vs last week, pace vs the same point last
  week, tasks done, estimation accuracy (median actual/estimate), best day, call
  time and its % of logged time, and a per-day bar chart overlaying both weeks.
- **History** — every past day grouped by week, with per-day detail.

Calls are tracked but **excluded** from the focused-minutes score — the goal is to
watch that share shrink. Weeks run Monday–Sunday. Right-click any row to delete it.

## Quick add

**⇧⌘Space** anywhere pops a one-line capture widget: type `task name 30m`
(trailing time = estimate), Enter adds it to Up next, Esc dismisses,
**Tab opens the full app**. Works while Volume runs, even with its window closed.

## Calendar sync

Meetings are logged automatically as calls: the app reads macOS Calendar
(EventKit) at launch and every 15 minutes — no network calls of its own, no
OAuth. Requirements: grant Calendar access on first launch, and have your
Google account in System Settings → Internet Accounts with Calendars enabled.
Rules: ended events with 2+ attendees, not declined, 5m–8h, last 14 days.
Calendar-sourced entries are reconciled on every sync (edits/deletions on the
calendar propagate); manually logged calls are never touched — so don't log
calendar meetings by hand or they'll double-count.

## Build

```
./build-app.sh
```

Produces `build/Volume.app` (ad-hoc signed). Copy it to /Applications or launch in
place. Requires macOS 14+ and the Xcode Command Line Tools — no full Xcode needed.
