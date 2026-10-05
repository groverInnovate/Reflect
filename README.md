# Life Replay

A private Mac productivity app that shows where your workday went. Use it to compare
days, spot distractions, and decide how to arrange your next work session.

The dashboard shows active time, work/other/distraction totals, hourly activity,
ranked apps and websites, and a searchable timeline. Click an activity to filter
the timeline. Choose an earlier date to review that day. Categories are editable;
CSV export includes exact interval durations in seconds.

There is no iPhone or Apple Watch companion, health integration, cloud sync, AI
summary, productivity score, coaching system, or notification schedule. Data stays
in the local SwiftData store. No account, subscription, or external service is used.

## Build and run

Requires macOS 14+, full Xcode with a Swift 6 toolchain, and no paid developer membership.
Select Xcode in **Xcode → Settings → Locations → Command Line Tools** first.
Command Line Tools alone lacks the SwiftData compiler plugin needed by this app.

```sh
./scripts/test-core.sh
./scripts/build-mac-app.sh
open .build/LifeReplayMac.app
```

The script builds an optimized Release executable before packaging it, then signs the local bundle
ad hoc. It reports a toolchain error rather than bundling an old executable. Keep
this app at a stable path when granting permissions. Optional launch-at-login is
under Tracking Settings; macOS may ask for approval in Login Items.

## Tracking

App switches are recorded when macOS reports them. Browser tab domains are sampled
every five seconds for Safari, Chrome, Brave, Edge, and Vivaldi. Allow Automation
when macOS asks. Without it, app time still works and the dashboard explains how
to enable website capture. Accessibility adds window/project titles and is optional.

Active time ends at the configured idle threshold, initially 90 seconds without
keyboard or mouse input. Change this under Tracking Settings if reading or calls
are being excluded too early. Sleep and inactive sessions are away time. Pausing or
quitting ends app attribution immediately. Heartbeats every 15 seconds support a
continuous session; if fresh evidence stops, attribution expires after 30 seconds.
Missing observations are displayed as **Not tracked**, never charged to the last app.

Totals accumulate seconds, then display whole minutes (or `<1m` for short time).
Browser changes can be off by approximately one polling interval; this is foreground
Mac activity, not a measurement of thought, background work, or every split-screen pane.
Work/other/distraction labels describe your category rules, so adjust them for your use.

Reports are computed from raw events, including past dates. There is no replay-generation
step. Editing categories updates historical reports. Existing database entity names are
preserved; an unused legacy health entity remains solely for store compatibility.

## Verification

`LifeReplayCore` has a separate package so its tests can run without building the app.
The tests are XCTest fixtures. When the selected toolchain lacks XCTest, `test-core.sh`
compiles the same fixtures with a minimal assertion adapter; it never falls back to
hide compilation errors when XCTest is present.

Before calling the app finished, build it with full Xcode and verify on the Mac:

1. Track a known 20-minute work session with several app and browser switches.
2. Leave the Mac idle, sleep/wake it, pause/resume tracking, then inspect the timeline.
3. Check that active totals exclude away and paused time; compare exact seconds in CSV.
4. Edit a website's category and verify current and historical reports update.
5. Open an existing store, restart the app, and check the midnight/day boundaries.

Production builds, existing-store preservation, live pause/resume and collection, and CSV
accounting have been verified. Remaining OS-session and permission checks are listed in
PRODUCTION_VERIFICATION.md and PROGRESS.md.
