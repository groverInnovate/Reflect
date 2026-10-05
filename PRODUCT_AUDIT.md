# Product and usability audit — 5 October 2026

## Purpose

Show what the user spent Mac workday time on, with enough clarity and accuracy to
change their schedule. Evidence and usable time breakdowns take priority over advice.

## Changes

- Replaced long prose reports and three report tabs with one native SwiftUI dashboard.
- Put active time, category totals, hourly activity, and ranked apps/sites first.
- Added date navigation, activity filtering, timeline search, and exact-seconds CSV export.
- Replaced pipe-delimited category text editing with fields and category menus.
- Reduced the menu bar menu to open, pause/resume, and quit; put two settings in the dashboard.
- Removed notification interventions/reminders, AI narratives, sleep-gap repair, debug
  windows, replay generation/backfill, heuristic score UI, and companion-device scope.
- Replaced per-event full-day analysis and SwiftData session rewrites with report-on-demand.

## Accuracy issues addressed

- Explicit stop boundaries prevent pause/quit accruing app time.
- Idle recovery captures a fresh app immediately; it cannot resurrect the pre-idle app.
- Wake/background maintenance waits for actual input before resuming active capture.
- Timer gaps become untracked evidence, rather than invented sleep.
- Returning to a browser re-captures its unchanged domain.
- Domains match exact hosts or subdomains; title keywords cannot override a captured host.
- Same-instant domain/app observations resolve deterministically to the domain.
- Totals sum seconds, including repeated sub-minute visits and all activities.
- Timeline merging cannot fill gaps; future events cannot stretch the report past its end.
- Reports carry supported state across midnight and clip intervals to the requested day.
- The build script now actually builds before packaging, preventing stale binaries.

## Verification and limits — updated after Xcode installation

All 33 core fixtures pass under native XCTest. Production Debug and Release targets
build with Xcode 27; the optimized signed app launches against the existing store.
A pre-launch backup comparison confirmed the old activity/categories/sessions/drifts/
replays were retained; migration added only the expected missing settings default.
Historical reports, filtering, timeline scrolling, and native dark appearance were
inspected. Live app/domain/heartbeat observations and pause/resume boundaries were
checked in the database. The production CSV exporter passed an actual-store accounting
check. Export presentation was changed to an asynchronous save dialog.

Accessibility/window-title approval, idle/sleep/lock/wake, minimum-width and edit/save
interactions, complete CSV dialog interaction, a real midnight crossing, and human
full-day accuracy judgment remain open. See PRODUCTION_VERIFICATION.md. Sampling,
idle heuristics, and foreground-only observation still bound practical accuracy.
