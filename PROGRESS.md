# Progress

## Current scope — 5 October 2026

Mac-only workday time analysis. The older companion/health and narrative phases are
cancelled, as are coaching, reminder, intervention, sleep-repair, and score interfaces.
Historical implementation notes remain available in git history and DECISIONS.md.

## Phase checklist

- [x] Phase 0 — Mac project and local persistence setup
  - [x] Mac/Core package layout, local SwiftData implementation, stable bundle script
  - [x] Mac-only target and updated agent/product documentation
  - [x] Legacy SwiftData entity names preserved, CloudKit explicitly disabled
  - [x] Production build and store initialization verified with full Xcode
- [ ] Phase 1 — Accurate collection
  - [x] App activation, five-second idle/domain polling, 15-second heartbeats
  - [x] Explicit pause/quit boundaries, fresh context on idle recovery
  - [x] Sleep/display/session observers; require fresh input after sleep
  - [x] Browser-return domain capture; bounded AppleScript timeout and error retry
  - [x] Accessibility/Automation and storage failures shown in the UI
  - [ ] Real-session app/domain/idle/sleep/lock verification
- [x] Phase 2 — Seconds-based accounting
  - [x] Seconds retained through aggregation; no eight-activity truncation
  - [x] Deterministic same-instant event ordering; future events excluded
  - [x] App attribution expires after 30 seconds in Mac reporting
  - [x] Unknown gaps remain unknown; no gap-filling timeline merges
  - [x] Hourly buckets, midnight carry/clipping, secondary focus-break evidence
  - [x] 33 core regression tests pass under native XCTest (portable runner also supported)
- [ ] Phase 3 — Native dashboard
  - [x] Time totals, hourly chart, ranked apps/sites, timeline
  - [x] Date navigation, category editor, search/filter, exact-seconds CSV
  - [x] Simple menu bar, tracking toggle, idle setting, launch-at-login
  - [x] Swift 6 type checking against a temporary store interface
  - [x] Actual SwiftUI sample-data window launched and visually inspected
  - [x] App filtering observed working in the preview
  - [x] Production historical date/filter/scroll interactions and dark appearance
  - [ ] Minimum-width, category/settings save, and full export-dialog interactions
- [ ] Phase 4 — Production acceptance
  - [x] Full production SwiftData build and launch (Debug and Release)
  - [x] Existing-store migration verified against a pre-launch backup
  - [ ] Browser/Accessibility permissions verified on the running production app
  - [ ] Timed session, pause/resume, sleep/wake, midnight and historical-report checks
  - [ ] Mohit's real-day accuracy/usefulness judgment

## Verification details — updated after Xcode installation

- Xcode 27.0 is selected. All 33 core fixtures pass under native XCTest.
- Production Debug and Release builds compile; the optimized ad-hoc-signed app launches.
- Existing database rows were preserved; the expected observation-gap default was
  added during migration. A private pre-launch backup was retained.
- Live app/domain/heartbeat observations and a pause/resume boundary were verified
  in the actual store. Historical date selection, filtering, scrolling, and dark UI work.
- The production store/export code passed a real-store CSV integration check.
- Export now opens its save dialog asynchronously. Complete dialog interaction still
  needs a manual check because the UI automation service reported repeated timeouts.
- The bundle script now defaults to Release and supports an explicit debug override.
- See PRODUCTION_VERIFICATION.md for evidence, limits, and remaining acceptance.

## Resume here

Approve Accessibility for window titles, then verify minimum-width/category/settings/export
interactions, idle/sleep/lock/wake, a live midnight boundary, and real-day usefulness.
The toolchain/build blocker is resolved. Tracking is left enabled in the production app.
