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

## 2026-06-20 - Persist replay snapshots explicitly

Added manual daily replay generation that saves timeline JSON, focus score, and fallback narrative into `DailyReplay`. The dashboard can still render live data, but saved snapshots give Mohit a stable end-of-day artifact; the alternative was to keep replay purely derived until the UI was more polished.

## 2026-06-20 - Permission UI must show OS state, not assumptions

Updated the menu/dashboard to refresh Accessibility and Notification status from macOS instead of relying on startup-time assumptions. Browser Automation remains prompt-driven because macOS only asks when AppleScript targets a browser; polling the frontmost browser makes that prompt more reliable during real use.

## 2026-06-20 - Stabilize local app code identity for TCC

The script-built app was ad-hoc signed with a generated hash identifier, so macOS Accessibility could approve one build while the next build looked like a different app. The bundle script now signs with `com.mohitgrover.LifeReplayMac`; the old TCC entry may need to be removed/regranted once.

## 2026-06-20 - Foundation Models as optional narrative layer

Added Foundation Models summarization only behind `macOS 26` availability and runtime model availability checks. If the framework, hardware, Apple Intelligence setting, or generation call is unavailable, `DailyReplay` keeps using the deterministic fallback summary.

## 2026-06-20 - Persist tunable drift thresholds

Added `FocusSettings` in SwiftData and a small settings window so drift thresholds can be tuned from real feedback. The alternative was to leave constants hardcoded until later, but Phase 2 acceptance depends on calibrating against Mohit's actual work patterns.

## 2026-06-20 - Show idle as replay blocks

Idle start/end events now generate neutral "Idle period" timeline blocks. This makes away-from-keyboard periods visible in the daily story; the alternative was to leave idle only in the raw event log, which made replay summaries under-explain breaks.

## 2026-06-20 - Subtract idle overlap from focus sessions

The focus engine now computes idle overlap per session before scoring. Without this, a long VS Code session could incorrectly count as productive time while Mohit was away from the keyboard.

## 2026-06-23 - Add an explicit daily insight report

Raw timeline blocks were not enough for the product promise, so replay generation now produces a journal-oriented `DailyInsightReport` with productive time, study-like time, distracting/wasted time, idle time, top pulls, and plain observations. The alternative was to keep improving the timeline display, but Mohit needs interpreted end-of-day insight, not just telemetry.

## 2026-06-24 - Roll back unstable dashboard work

Rolled back the native Today dashboard, enriched-label pass, tomorrow target, and follow-up crash-fix commits to restore the last known stable text dashboard state. The alternative was to keep patching forward, but repeated crash reports showed we needed a stable checkpoint before rebuilding the product surface.

## 2026-06-24 - Improve insights inside stable text dashboard

Kept the working text-tab dashboard and improved only the pure replay insight model plus text rendering. Added coding-like time, deep-work time, fragmented productive time, top productive threads, and a next action; the alternative was another UI rebuild, which is too risky until the stable dashboard has more real usage.

## 2026-06-24 - Professionalize dashboard around daily learning

Reduced the visible dashboard to Daily Review, Activity Timeline, and Focus Breaks so it teaches what happened instead of exposing debug surfaces. Added a ranked activity breakdown and explicit drift-alert status; the alternative was a redesigned native/card dashboard, but the stable AppKit text dashboard is the safer base after recent crashes.

## 2026-06-24 - Treat Mac sleep as idle time

Added macOS sleep/wake observers that write idle start/end events around lid-close or system sleep. This prevents the previous frontmost app from appearing to run through sleep; the alternative was to infer sleep from long timestamp gaps, which would be less reliable and harder to explain.

## 2026-06-24 - Polish dashboard visually without changing its architecture

Styled the stable AppKit dashboard with richer typography, calmer report backgrounds, and color-coded productivity/distraction cues. The alternative was a larger custom card UI, but the recent crash history makes an incremental rich-text design safer while still improving readability.

## 2026-06-24 - Add real-time focus protection before daily drift review

Added a pure `FocusProtectionEngine` that fires when a distracting app/domain follows a sustained productive block, then wired it to immediate local notifications with a 10-minute cooldown. The alternative was waiting for end-of-day drift analysis only, but the product needs to interrupt distractions while they are happening.
