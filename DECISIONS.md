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

## 2026-06-20 - AppleScript browser domains before richer browser extensions

Implemented Safari/Chrome-family domain capture with AppleScript on frontmost browser activation. This matches the $0 local-first constraint and uses the standard Automation prompt; the alternative was a browser extension, which would add a separate install/debug surface before the Mac collector is stable.

## 2026-06-20 - Store window titles on activity events

Added an optional `windowTitle` field to `ActivityEvent` and capture it through Accessibility when permission is granted. Keeping it on the raw event preserves debugging context for the dashboard; the alternative was a separate window-title event kind, which would fragment a single app activation across multiple rows.

## 2026-06-20 - Notifications require a real app bundle

Local drift notifications are guarded behind a `.app` bundle check because `UNUserNotificationCenter.current()` crashes when launched as a raw SwiftPM executable from `.build`. `swift run` remains useful for collector/dashboard smoke tests; notification prompts will be verified through the bundled/Xcode app path.

## 2026-06-20 - Add script-built Mac app bundle before Xcode project

Added `scripts/build-mac-app.sh` to wrap the SwiftPM executable in a local `.app` bundle with the needed Info.plist keys. This lets Mohit test menu bar behavior and notification/Automation prompts before we invest in hand-maintaining an Xcode project; the alternative was to make Xcode setup the immediate blocker.

## 2026-06-20 - Plain text category editor first

Added an AppKit category editor using one editable rule per line (`pattern | name | category`). It is less polished than a table editor, but it makes classifications correctable immediately and keeps the MVP moving; the alternative was a custom NSTableView editor with more UI code before real usage feedback.
