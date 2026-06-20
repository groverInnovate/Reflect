# Progress

## Phase Checklist

- [ ] Phase 0 - Project setup + capability probe
  - [x] Repo documentation created: `AGENTS.md`, `DECISIONS.md`, `PROGRESS.md`
  - [x] Swift package scaffolded with `LifeReplayCore` and `LifeReplayMac` targets
  - [ ] Xcode workspace/project configured for free Personal Team signing
  - [ ] Empty macOS menu bar app builds and launches on-device
  - [ ] HealthKit probe run on physical iPhone and result documented
- [ ] Phase 1 - Mac activity collector
  - [x] Frontmost app activation events captured in the menu bar process
  - [x] Idle start/end events captured in the menu bar process
  - [x] Accessibility permission prompt/settings link implemented
  - [x] Browser-domain capture implemented for Safari and Chrome-family browsers
  - [x] Accessibility window-title capture implemented
  - [x] Menu bar controls show running state and event count
  - [x] Collector events persisted to SwiftData
  - [x] Basic raw event inspection window implemented
  - [ ] Real coding-session verification completed by Mohit
- [ ] Phase 2 - Focus Drift Engine
  - [x] Initial rule-based drift engine implemented in `LifeReplayCore`
  - [x] Synthetic XCTest coverage added
  - [ ] Live Mac event stream wired into persistence
  - [ ] Drift notifications implemented
- [ ] Phase 3 - Daily Replay generation + Mac dashboard UI
  - [x] Initial timeline clustering implemented in `LifeReplayCore`
  - [ ] Dashboard timeline UI implemented
  - [ ] End-of-day real usage check completed
- [ ] Phase 4 - On-device narrative summary
  - [x] Deterministic fallback summary implemented
  - [ ] Foundation Models path implemented behind availability checks
- [ ] Phase 5 - Optional iPhone companion
  - [ ] Not started
- [ ] Phase 6 - Further stretch
  - [ ] Not started

## Latest Session Notes

- Created the persistent repo instructions file from the pasted spec.
- Added the first testable core implementation for categories, drift detection, scoring, timeline clustering, and fallback summaries.
- Added an initial macOS menu bar collector for frontmost app switches and idle transitions.
- `swift test` passes with 5 Swift Testing tests.
- Added SwiftData persistence and a basic native dashboard/raw event window.
- `swift test` passes with 5 Swift Testing tests; `swift run LifeReplayMac` launches in a smoke test.
- Added Accessibility permission menu actions and AppleScript browser-domain capture.
- `swift test` passes with 5 Swift Testing tests; `swift run LifeReplayMac` launches in a smoke test.
- Added optional window title capture through Accessibility and showed titles in the raw event dashboard.
- `swift test` passes with 5 Swift Testing tests; `swift run LifeReplayMac` launches in a smoke test after the schema change.
- Added a permissions/status section to the dashboard.
- `swift test` passes with 5 Swift Testing tests.
- Next best step: run a real Phase 1 session check with Mohit approving macOS prompts, then start Phase 2 live drift notifications.
