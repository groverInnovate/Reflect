# Life Replay — agent instructions

## Current product scope (Mohit's instruction, 5 October 2026)

Build a completely Mac-only productivity app. Its purpose is to show users where
workday time went so they can analyze it and improve their schedule. Prior specs
about an evening mentor, AI narratives, iPhone, Apple Watch, HealthKit, local-device
sync, place tracking, scores, reminders, and intervention notifications are superseded.
Do not reintroduce them. Budget remains $0; no cloud, paid APIs, telemetry, or backend.

## Product

A menu bar collector and one native dashboard, macOS 14+. Show active time, editable
work/other/distraction categories, ranked app/site time, hourly activity, searchable
timeline, date navigation, and CSV export. Keep settings short. Focus-break evidence
may be shown as secondary detail. Never claim to measure intent or every visible pane.

## Accounting

- Frontmost app activation is event-driven; active browser domains and idle are polled
  every 5 seconds. Heartbeats every 15 seconds prove continued observation.
- Persist actual observations locally in SwiftData. No fetch caps on daily events.
- Pause/quit end attribution immediately. Idle/sleep are separate from active time.
- A delayed timer is missing evidence, not proof of sleep. Never repair gaps by guessing.
- App attribution expires after 30 seconds without fresh evidence in the Mac app.
- Clip reports at day boundaries; retain the original expiry of carry-over observations.
- Sum seconds before display rounding. Merge only contiguous intervals for the same surface.
- A captured domain takes priority over title keywords. Match hosts at domain boundaries.
- Keep existing SwiftData entities readable. The old HealthSnapshot entity is retained
  only to preserve the schema, with no collection or product UI.

## Engineering and workflow

Use Swift 6, SwiftUI/AppKit, Observation, and os.Logger. Keep core logic independent of
AppKit/SwiftData. No Combine, paid dependencies, force unwraps of optional platform data,
or elaborate abstractions. Permission/storage failures must have an in-app explanation.

Keep DECISIONS.md updated with 2–3-line architectural/product decisions and PROGRESS.md
with completed work, actual verification, and remaining work. Make small local commits.
Proceed autonomously; ask only for human-owned OS permissions/toolchain setup or real-day
accuracy checks. Don't mark the product done from compilation alone.

## Phases

0. Mac project and local persistence setup.
1. Accurate Mac collection and permission states.
2. Tested seconds-based time accounting and optional focus-break evidence.
3. Simple native workday dashboard and editable categories.
4. Production build, existing-store migration, permissions, and real-session acceptance.

Run `scripts/test-core.sh`. With Xcode this uses XCTest; on Command Line Tools it executes
those same fixtures through the portable assertion runner. Run `scripts/build-mac-app.sh`
for the real app. The latter requires full Xcode's SwiftData macro plugin. Never package a
stale binary or treat a sample-data UI preview as production verification.
