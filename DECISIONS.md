# Decisions

## 2026-06-20 - Root Swift package with requested folders

Decided to make the repo a root Swift package while preserving `LifeReplayCore/` and `LifeReplay-Mac/` as target folders. This makes `swift test` and `swift run LifeReplayMac` available immediately; the alternative was hand-authoring an Xcode project first, which would slow down core engine verification.

## 2026-06-20 - Mac-first MVP remains the build path

Confirmed the spec's architecture and started with the Mac-only core product. Screen Time and CloudKit stay cut because they conflict with the $0/free-signing constraint; the alternative was to scaffold optional iOS sync early, which would add permission and signing churn before the useful core exists.

## 2026-06-20 - HealthKit probe deferred to Xcode/device step

Documented the HealthKit probe as pending because it requires Xcode signing with Mohit's Personal Team and a physical iPhone. The alternative was to infer from documentation, but the spec explicitly calls for an empirical probe.

## 2026-06-20 - Collector starts in-memory before SwiftData wiring

Implemented the first macOS collector as an in-memory menu bar flow that records app switches and idle transitions into callbacks. This proves the AppKit/CoreGraphics path compiles before adding storage; the alternative was to introduce SwiftData persistence and collector permissions in the same change.

## 2026-06-20 - Native text dashboard before designed SwiftUI dashboard

Added a simple AppKit dashboard backed by SwiftData that shows today's score, timeline, and raw events. This gives a verifiable Phase 1 inspection surface immediately; the alternative was to wait for the fuller Phase 3 SwiftUI dashboard before making captured data visible.
