# Life Replay Completion Plan

This is the winding-down checklist for turning Life Replay from a working prototype
into a dependable personal productivity journal.

## Product North Star

At the end of a day, the user should open the dashboard and immediately understand:

- what the Mac actually observed,
- how much time went into study, coding, neutral work, idle time, and distractions,
- when focus broke,
- whether the numbers are trustworthy,
- what one calibration or protection step would improve tomorrow.

The product should feel like a private daily review, not a raw activity monitor.

## Free-Tier Capability Boundary

Research checked on 2026-07-07 against Apple documentation:

- Apple documents that provisioning-profile capabilities depend on membership. A
  no-cost Apple Developer account exists, but it cannot distribute apps.
- Mac-first tracking remains the best MVP because Accessibility, Automation,
  local notifications, SwiftData, AppleScript, and AppKit do not require a paid
  Apple Developer Program subscription for local signed development.
- CloudKit and iCloud-backed SwiftData remain out of scope for this project
  because sync would add paid/member capability and complexity.
- Family Controls / Screen Time remains out of scope. Even where listed as
  development-capable, it is a managed/sensitive capability and does not fit the
  local-first, zero-spend MVP.
- Foundation Models / Apple Intelligence can stay as an optional narrative layer.
  The app must keep the deterministic fallback because availability varies by OS,
  hardware, region, and Apple Intelligence state.
- Local Wi-Fi sync through MultipeerConnectivity or Network.framework is still the
  only reasonable free sync path if an iPhone companion is ever built.

Primary references:

- https://developer.apple.com/help/account/reference/supported-capabilities-ios
- https://developer.apple.com/help/account/reference/supported-capabilities-macos
- https://developer.apple.com/help/account/reference/provisioning-with-managed-capabilities
- https://developer.apple.com/apple-intelligence/

## Completion Backlog

### P0 - Ship Confidence

- [x] Keep the Mac app stable on the existing AppKit text dashboard architecture.
- [x] Add visible Tracking Health diagnostics to the Daily Review.
- [x] Keep tests and the script-built `.app` passing after every meaningful change.
- [x] Update README so the user can run, verify, export, and calibrate without
      remembering this chat.
- [x] Export enough debug data to diagnose inaccurate days without touching the
      database manually.
- [x] Remove the daily event fetch cap so long days are not silently truncated.
- [x] Bound every active interval with heartbeat evidence and expose unobserved
      time instead of attributing stale gaps to the last app.
- [x] Keep SwiftData at the Mac boundary while preserving the existing entity names
      for local-store continuity.

### P1 - Maximum User Benefit

- [x] Improve the Daily Review copy until it reads like a useful end-of-day journal:
      what happened, what mattered, what was suspicious, and tomorrow's one action.
- [x] Make calibration loops obvious: top neutral items should become suggested
      category edits.
- [ ] Add a final manual QA checklist for one real 90-minute work/study session.
- [x] Make README limitation language honest: Life Replay observes frontmost and
      sampled browser activity; split-screen context is inferred, not magically
      measured per visible pane.

### P2 - Free Stretch Work

- [ ] Optional iPhone companion with Core Motion step snapshots and local Wi-Fi sync.
- [ ] Optional manual tags for Gym, Lecture, Commute, Reading, and Rest.
- [ ] Optional weekly/monthly rollups once daily tracking feels trustworthy.
- [ ] Optional place labels through standard When-In-Use location permission.

## Deliberate Non-Goals

- No paid Apple Developer Program dependency.
- No Screen Time / Family Controls.
- No CloudKit.
- No backend, analytics SDK, Firebase, Supabase, or LLM API.
- No fragile redesign of the dashboard until the current app has survived real use.

## Final Acceptance Test

Run the signed app for a real study/coding block, then verify:

1. The Daily Review names the dominant work correctly.
2. The active observed time roughly matches memory.
3. Idle/sleep time is not counted as active work.
4. Browser domains appear when Brave/Chrome/Safari are used.
5. The Tracking Health section says whether the day is reliable.
6. A distracting app/domain after sustained work triggers a notification if
   notifications are allowed.
7. Exported Markdown and CSV files contain enough context to debug mistakes.

The current development host does not have a full Xcode installation, so the final
signed-app launch, permission prompts, and real 90-minute session are still manual
acceptance checks for Mohit. The core target builds with the repository-local module
cache; the full package test command cannot run here because Swift Testing and
SwiftData macro plugins are missing from the available Command Line Tools image.
