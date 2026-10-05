# Production verification — 5 October 2026

## Passed

- Xcode 27.0 (27A266a) is selected; the SwiftData compiler plugin is available.
- All 33 core fixtures pass under native XCTest, with zero failures.
- Debug and optimized Release targets compile. The release bundle is signed ad hoc
  and passes strict code-signature verification; no paid signing membership is used.
- The actual production dashboard launches and collects into the existing local store.
- A pre-launch SQLite backup was taken. All existing activity, category, session,
  drift, and replay rows were preserved. The only settings migration was adding the
  previously absent observation-gap field with its expected default of 120; the
  current Mac reporting policy still explicitly uses 30 seconds.
- Historical date selection, activity filtering, and timeline scrolling work on real
  stored events. The native dark appearance was visually inspected.
- Pausing saves `trackingStopped`; the database count remains unchanged during the
  pause. There are zero events between that stop and the subsequent resume marker.
- Resuming records fresh activity. Live app switches, browser-domain observations,
  and heartbeats were confirmed in the actual store.
- A temporary verification executable compiled the production SwiftData models and
  store code, opened the existing store, and exported a historical report. CSV row
  counts, nonnegative durations, exact duration totals, active totals, ordering, and
  nonoverlap all passed validation.
- App relaunch after rebuilding the release bundle preserved tracking/data access.

## Fixes during verification

- Bundle builds now default to Release; `LIFEREPLAY_BUILD_CONFIGURATION=debug` remains
  available for development builds. Compilation must succeed before replacing a bundle.
- CSV export presents its save panel asynchronously and retains the selected report
  date, so choosing a destination does not hold the calling main-actor method open.

## Still requires acceptance

- Accessibility approval and actual window/project-title capture. The production app
  currently shows its missing-permission state; the user was asked to enable it.
- End-to-end save-panel interaction: the UI automation service repeatedly reported
  changed-window/timeouts during this step. The actual exporter passed the store
  integration check, but the complete save-dialog interaction was not verified.
- Minimum-width layout and the category/settings edit-and-save interactions.
- Real idle and sleep/lock/wake behavior, a live midnight boundary, and a timed work
  session/full-day accuracy judgment. Synthetic accounting tests cover these interval
  rules; they do not replace physical OS-session acceptance.

## Private artifacts

Database snapshots, the CSV, and the temporary harness live under `.build/verification/`,
which is ignored by Git. No raw activity, exported CSV, snapshots, or screenshots are
included in the GitHub push. Build and XCTest logs were kept locally under `/tmp`.
