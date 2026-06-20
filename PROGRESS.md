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
  - [ ] Accessibility and browser-domain permission flows implemented
  - [x] Menu bar controls show running state and event count
  - [ ] Collector events persisted to SwiftData
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
- Next best step: add SwiftData storage for collected events, then implement raw event inspection/dashboard UI.
