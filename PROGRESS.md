# Progress

## Current scope — 5 October 2026

Mac-only workday time analysis. The older companion/health and narrative phases are
cancelled, as are coaching, reminder, intervention, sleep-repair, and score interfaces.
Historical implementation notes remain available in git history and DECISIONS.md.

## Phase checklist

- [ ] Phase 0 — Mac project and local persistence setup
  - [x] Mac/Core package layout, local SwiftData implementation, stable bundle script
  - [x] Mac-only target and updated agent/product documentation
  - [x] Legacy SwiftData entity names preserved, CloudKit explicitly disabled
  - [ ] Production build and store initialization verified with full Xcode
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
  - [x] 33 core regression tests pass through the portable XCTest-fixture runner
- [ ] Phase 3 — Native dashboard
  - [x] Time totals, hourly chart, ranked apps/sites, timeline
  - [x] Date navigation, category editor, search/filter, exact-seconds CSV
  - [x] Simple menu bar, tracking toggle, idle setting, launch-at-login
  - [x] Swift 6 type checking against a temporary store interface
  - [x] Actual SwiftUI sample-data window launched and visually inspected
  - [x] App filtering observed working in the preview
  - [ ] Production dashboard interaction, full-day scrolling, dark/minimum-width checks
- [ ] Phase 4 — Production acceptance
  - [ ] Full production SwiftData build and launch
  - [ ] Existing-store migration verified
  - [ ] Browser/Accessibility permissions verified on the running production app
  - [ ] Timed session, pause/resume, sleep/wake, midnight and historical-report checks
  - [ ] Mohit's real-day accuracy/usefulness judgment

## Verification details

- `scripts/test-core.sh`: 33 fixtures pass; XCTest itself is absent in the installed
  Command Line Tools, so the same fixture bodies run through the portable adapter.
- UI/app/collector Swift 6 type checking passes against a temporary store stub.
  This does not verify production persistence.
- A temporary native preview with explicitly labeled sample data launched and was
  visually reviewed. No sample data is included in the shipping target.
- UI automation's scroll call returned `noWindowsAvailable`; filtered selection was
  confirmed through the updated accessibility tree, but scrolling is still unchecked.
- `scripts/build-mac-app.sh`: stops clearly because full Xcode is absent. Earlier
  compile attempts confirm the missing `SwiftDataMacros` compiler plugin.
- Both shell scripts pass `bash -n`; core and UI checks are independent of paid services.

## Resume here

Select a full Xcode installation, run the two scripts in README.md, then perform the
acceptance checks above. Do not count the sample-data preview as a verified live tracker.
