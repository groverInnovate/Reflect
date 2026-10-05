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

## Verification and limits

33 core tests pass through the portable runner using the same XCTest fixtures.
Swift 6 type checking passes for the UI, app entry point, collectors, and launch-at-login
against a temporary persistence interface. The actual native dashboard was launched
with sample data and visually inspected; app-filter selection was observed working.
The UI automation service could not scroll the preview reliably, so that interaction
has not been fully verified.

The production SwiftData build remains blocked by absent full Xcode/SwiftData macros.
Existing-store migration and real permission/timing checks remain required. Sampling,
idle heuristics, and foreground-only observation put practical bounds on accuracy.
