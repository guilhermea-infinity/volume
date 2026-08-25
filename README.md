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

## Build

```
./build-app.sh
```

Produces `build/Volume.app` (ad-hoc signed). Copy it to /Applications or launch in
place. Requires macOS 14+ and the Xcode Command Line Tools — no full Xcode needed.
