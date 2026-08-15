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

## 2026-06-24 - Use window titles for study/research classification

Expanded category matching to include window titles alongside domains, bundle IDs, and app names, then seeded more docs/course/research defaults. The alternative was relying only on app/domain, which misses common study cases like lecture PDFs opened in Preview.

## 2026-06-24 - Put review regeneration inside the dashboard

Added a native dashboard refresh button that regenerates today's replay and shows the updated time. The alternative was keeping generation only in the menu bar, but the review action belongs next to the report the user is reading.

## 2026-06-25 - Infer sleep from collector suspension gaps

Added a fallback for cases where macOS sleep/wake notifications are missed: if the collector's idle timer resumes after a long gap, it records the missing interval as idle/away. Also changed replay generation to cut idle intervals out of active session blocks, preventing Code or any other app from visually counting through sleep.

## 2026-06-25 - Surface suspicious tracking data in the dashboard

Added data-quality warnings for suspiciously long uninterrupted active blocks or long days with no idle. The alternative was silently showing questionable numbers; the dashboard should teach Mohit when a number may be wrong as well as what the number is.

## 2026-06-25 - Add manual sleep-gap repair

Added a repair engine and dashboard/menu actions that infer idle intervals across long unmarked event gaps, then regenerate today's replay. The alternative was asking Mohit to ignore bad historical days, but a personal journal needs a way to correct obvious capture failures.

## 2026-06-25 - Schedule an end-of-day review reminder

Added a repeating local notification at 9:30 PM so Life Replay nudges Mohit to review the day. The alternative was manual dashboard checking only, but the product goal is an evening journal habit, so the app should initiate that loop.

## 2026-06-25 - Make repair guidance visible in the review

Added a clearer "Today's Numbers" section and explicit repair guidance under accuracy warnings. The alternative was leaving repair discoverability to the menu, but warnings should point directly to the corrective action.

## 2026-06-25 - Auto-generate evening reviews while the app is running

Added an app-side timer that generates today's replay once per day after 9:30 PM and sends a ready notification with the focus score. The scheduled notification remains a fallback nudge; the timer makes the journal artifact exist before Mohit opens the dashboard.

## 2026-06-25 - Add calibration suggestions to the daily review

Added report-level suggestions for category tuning, repair, and missing distraction/study detection. The alternative was relying on Mohit to infer why numbers felt wrong, but the app should point to likely fixes after 1-2 days of use.

## 2026-06-28 - Build replay from observed event intervals

Changed replay timeline generation to allocate time from actual app/domain event intervals instead of broad focus sessions. This fixes cases where one neutral browser domain, like ChatGPT, swallowed time spent on another tab, like Rust Book; the alternative was more category tuning, but the underlying time allocation was too coarse.

## 2026-06-28 - Poll browser tabs more frequently

Reduced the collector timer from 15 seconds to 5 seconds so active-tab changes are detected closer to when they happen. The collector still only writes browser events when the domain changes, so this improves accuracy without storing duplicate rows every poll.

## 2026-06-29 - Treat AI writing tools and HackMD as productive work

Added Claude, ChatGPT, and HackMD to productive defaults, and made browser window titles contribute display names when domain capture misses. Existing installs now receive missing default rules on launch; the alternative was asking Mohit to hand-edit categories for common work tools.

## 2026-06-29 - Compact noisy sub-minute timeline rows

Grouped rapid sub-minute switches of the same category into mixed activity rows for dashboard readability. The raw events remain available in exports, but the review timeline should communicate work blocks instead of pages of 0-minute toggles.

## 2026-06-30 - Count AI assistance inside nearby study workflows

Changed study/research accounting so Claude/ChatGPT blocks count as study support when adjacent to study/notes tools such as HackMD. The alternative was counting only the frontmost surface, but split-screen workflows use multiple visible tools for one task.

## 2026-06-30 - Show active observed time separately from idle

Changed the dashboard headline from total tracked time to active observed time plus idle/away. The alternative made repaired overnight idle dominate the headline and made the useful work session harder to judge.

## 2026-07-07 - Add a completion plan before final polish

Created `COMPLETION_PLAN.md` to anchor the winding-down work around the daily review product promise, free-tier Apple constraints, and a final acceptance checklist. The alternative was to keep adding features opportunistically, but completion needs a visible product/technical bar.

## 2026-07-07 - Surface tracking trust in the dashboard

Added a Tracking Health section to Daily Review that checks event density, browser-domain capture, window-title coverage, idle markers, neutral share, and notifications. The alternative was to keep diagnostics in exports/status windows, but the user should know whether today's numbers are trustworthy before judging the day.

## 2026-07-07 - Turn neutral time into category fixes

Added Category Fix Candidates to the Daily Review so neutral app/domain time produces concrete rule patterns to review. The alternative was a vague "edit categories" hint, but accuracy improves fastest when the app points at the exact unlabeled surfaces.

## 2026-08-15 - Bound time attribution with active heartbeats

Added a `.heartbeat` activity signal and a configurable two-minute maximum observation gap. State-change events alone cannot prove that the last app remained active, so stale gaps are now explicitly unobserved and excluded from scoring. The alternative was to keep assigning missing time to the last surface, which made the journal confidently wrong after collector failures or sleep.

## 2026-08-15 - Keep SwiftData at the Mac persistence boundary

Moved SwiftData `@Model` records into the Mac target and kept `LifeReplayCore` as pure Foundation types plus engines, while preserving the existing SwiftData entity names for store continuity. The alternative was to leave persistence macros in the core package, which prevented the accounting logic from being compiled and tested independently with the available command-line toolchain.

## 2026-08-15 - Prefer exact observed category transitions over session hysteresis

Focus sessions now represent contiguous observed category intervals; idle and unobserved intervals split them, and heartbeat signals do not count as switches. The existing minimum-session setting remains exposed for compatibility, but timeline/task attribution is exact rather than waiting 90 seconds to decide whether a real transition “counts.” The alternative would have made short but real distractions disappear from the replay.

## 2026-08-15 - Normalize same-timestamp app and browser signals

Drift and historical baseline calculations collapse an app activation plus browser-domain capture at the same timestamp into one transition, preferring the domain for classification. The alternative double-counted a single browser switch and made drift severity and personal baselines depend on collector implementation details.

## 2026-08-15 - Repair only genuinely long missing gaps

Raised automatic sleep/away repair from 30 minutes to two hours and relabeled inserted intervals as inferred away/sleep. A missing event is not proof of sleep, so the product should leave ordinary gaps unassigned and let the user correct only obvious overnight/lid-close gaps. The alternative risked erasing real deep work.

## 2026-08-15 - Treat uncertainty as a first-class mentor output

Added observed, idle, and unobserved timeline kinds plus Daily Review accuracy notes, Tracking Health actions, and category-fix candidates. The alternative was a single productivity score with no way to tell whether a good day reflected real focus or incomplete capture.

## 2026-08-15 - Record the current verification boundary

Core source changes were checked by inspection and a standalone synthetic smoke harness, but this environment currently has Command Line Tools without a matching Xcode toolchain, so SwiftData macro expansion, full Swift Testing, and the signed AppKit bundle cannot be rebuilt here. Native dashboard launch was attempted and failed in AppKit/LaunchServices before the app reached its UI; physical-device and permission checks remain manual acceptance work.
