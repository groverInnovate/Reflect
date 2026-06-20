Paste this whole document as your first message to Codex, or save it as `AGENTS.md` in
the repo root so it persists across sessions. Everything below is the spec. Build it.

This is an experimental, personal vibe-coding project. **Hard constraint: $0 spend,
no paid Apple Developer Program enrollment.** Everything here is scoped to what a
free Apple ID ("Personal Team" signing in Xcode) can actually do. Where Apple gates a
feature behind the paid program, it's either replaced with a free alternative or
explicitly cut — see Section 4.

---

## 0. Operating Instructions for You, the Agent

- **Autonomy level: high.** Mohit (the human) wants to review working software, not
  answer design questions. Make the call on anything not explicitly marked
  "ASK HUMAN" below. Default to the simplest thing that works.
- **Keep a `DECISIONS.md`** in the repo root. Every time you make a non-trivial
  architectural or product call — including the results of any capability probe in
  Phase 0 — append a 2-3 line entry: what you decided, why, what the alternative was.
  This is how Mohit catches up between sessions and how *you* catch up across
  sessions, since you won't remember this conversation next time.
- **Keep a `PROGRESS.md`** with a checklist mirroring the phases in Section 7. Update
  it at the end of every session so a fresh Codex session can resume without
  re-reading the whole history.
- **Commit often, in small units.** One logical change per commit. Write commit
  messages that explain *why*, not just *what*.
- **Only stop and ask the human** when you hit something in the "What You Must Do
  Manually" list (Section 11) — those genuinely require a human with an Apple ID,
  Xcode GUI, or a physical device in hand. Everything else: decide, document, move on.
- **Definition of done for any phase**: it builds, it runs on a real device (not just
  simulator, where that matters), and the acceptance criteria in Section 7 are met.
  Don't mark a phase done because the code compiles — Apple's permission system
  fails silently in ways that only show up on-device.

---

## 1. What We're Building

A personal, local-first system that answers two questions every evening:

1. **"What did I actually do today?"** — an automatically generated timeline
   ("Life Replay") built from Mac activity (and, optionally, iPhone signals — see
   Section 4), with no manual logging required for the core experience.
2. **"When did I lose focus, and what pulled me away?"** — a rule-based Focus Drift
   Detector that flags the moments a deep-work session broke down, without machine
   learning, just thresholds on activity signals.

Example of what a finished day should look like in the app:

```
Today — June 19

09:30  Lecture (Mechanical Eng.)              ▓▓▓▓▓▓▓▓ 1h30m   [manual / calendar]
11:15  Coding — lean-sim / hive               ▓▓▓▓▓▓▓▓▓▓▓▓ 2h05m
   ⚠ Drift detected 12:40–12:48 — 9 tab switches in 8 min,
     opened Twitter, X, Instagram during active VS Code session
13:00  Lunch (idle period)
14:10  Coding — Moonglass consensus client    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ 2h50m
20:30  Reading / Twitter

Focus Score: 78/100
Best deep-work block: 14:10–16:55 (zero drift events)
Worst block: 12:40–12:48 (drift, see above)
```

Note this version leans entirely on what the Mac can see — no health/sleep/workout
data is assumed by default, since that depends on a capability that may not be
available for free (Section 4.3). If it turns out to be available on Mohit's
account, it's a bonus layered on top, not a dependency.

The product is the combination of the two views, not either alone. A replay without
drift detection is just an activity log. Drift detection without the replay is just
a number with no story. Together: "here's what happened, and here's exactly where
it went sideways" — that's the part worth opening every day for.

---

## 2. Context on the Builder

Mohit is a strong systems/Rust/Solidity engineer (Ethereum Protocol Fellowship,
multiple ZK and consensus-client projects) but this is his first serious Swift/Apple
project. Write idiomatic, modern Swift (Swift 6 concurrency where it matters:
`@Observable`, structured concurrency, actors for the background collectors — not
Combine, not completion-handler-era patterns). Comment *why*, not *what*, the way
you would for a competent engineer who's new to a specific platform, not new to
engineering. Don't over-abstract; this is a single-user personal tool, not a
framework for the App Store.

---

## 3. Hard Constraints

- **Devices available:** Mohit's iPhone, Apple Watch, and Mac.
- **Budget: $0.** No Apple Developer Program enrollment. Sign everything with a free
  Apple ID ("Personal Team" in Xcode's Signing & Capabilities). No paid APIs, no LLM
  API costs, no backend hosting, no third-party SaaS (no Firebase, no Supabase, no
  analytics SDKs).
- **Free-signing reality check, accept this as normal workflow, not a bug:**
  - Apps signed with a free Personal Team expire roughly every 7 days and need to be
    rebuilt from Xcode (device connected) to keep running. A long-running menu bar
    app on the Mac will need this periodic re-launch from Xcode.
  - Free provisioning supports a small number of registered devices (historically
    capped around 3). iPhone + Mac comfortably fits.
  - No wireless/TestFlight distribution — everything runs via a direct Xcode → device
    connection. That's fine here; this never ships anywhere.
- **Local-first and private by default.** All data lives on-device in SwiftData.
  Since cross-device cloud sync (CloudKit) isn't available for free (Section 4.2),
  there's no network traffic at all in the MVP — genuinely zero external dependency.
- **No always-on server.** Single local app (Mac), optionally a second local app
  (iPhone) syncing over the same Wi-Fi network only — never over the internet.
- **Minimum OS targets: iOS 17 / macOS 14.** Gate anything from the Foundation
  Models framework (Section 9) behind an iOS 26 / macOS 26 + Apple Intelligence
  availability check, with a non-AI fallback.

---

## 4. Critical Feasibility Notes — Read Before Writing Any Code

This is the part that determines whether the MVP ships in two weeks or stalls for a
month fighting Apple's permission system. Internalize this before touching Xcode.
The short version: **build the whole core product as a single Mac app first.**
Everything else is optional bonus layered on afterward.

### 4.1 Screen Time / Family Controls — fully out of scope, not even as a stretch goal

Apple's `FamilyControls` / `DeviceActivity` / `ManagedSettings` stack (the "Screen
Time API") requires the `com.apple.developer.family-controls` entitlement, and
Apple's own developer support has confirmed directly on their forums that this
entitlement **does not exist at all on a free Personal Team** — it's paid-program
only, full stop, even just to enable the capability toggle in Xcode. On top of that,
even with a paid account, the per-app usage data is sandboxed inside a
`DeviceActivityReportExtension` and Apple's engineers have stated outright that it
cannot be exported to your own app's code by design — it can only be displayed in
the extension's own view. Between the paid-account gate and the export restriction,
this isn't worth touching for this project. **Cut it entirely — no iPhone Screen
Time integration in any phase, including stretch goals.**

### 4.2 CloudKit — also paid-gated; use local Wi-Fi sync instead, if you want sync at all

The `iCloud: CloudKit` capability (what SwiftData's built-in "free sync" relies on)
is a paid-Developer-Program capability, listed alongside the other restricted
entitlements that require an active paid membership to enable. **Decision: no
CloudKit, anywhere, in this project.**

If a second device (iPhone) is added later (Phase 5, optional), sync between Mac and
iPhone happens over the **local Wi-Fi network** using `MultipeerConnectivity` or
`Network.framework`/Bonjour — these are ordinary frameworks any signed app can use,
free or paid, no special entitlement, just a one-time "Local Network" permission
prompt and a Bonjour service type declared in `Info.plist`. The tradeoff: both
devices need to be on the same Wi-Fi network at sync time. That's an acceptable
constraint for a personal tool used at home/hostel/lab.

### 4.3 HealthKit — uncertain on free tier. Probe it, don't assume it.

The evidence here is mixed and partly dated. Some official Apple tutorials state
flatly that HealthKit requires an active (paid) developer account; other developers
report it working fine under free Personal Team signing for local on-device runs.
Policy and tooling both shift over time, and this is exactly the kind of thing where
a five-minute empirical check beats confident guessing either way.

**Action for Phase 0:** add the HealthKit capability to the iOS app target in Xcode
with the free Personal Team selected, and try to build to a physical device.
- If it builds and runs cleanly → HealthKit is available on this account. Use it as
  a bonus data source in Phase 5 (heart rate, HRV, sleep, workouts), but never make
  the core product depend on it.
- If Xcode shows a signing error (e.g. "your development team does not support the
  HealthKit capability") or the capability won't add → treat it as unavailable, log
  the finding in `DECISIONS.md`, and skip Watch/Health data entirely. Use
  `CMPedometer` (part of Core Motion, not gated by HealthKit at all) for a free,
  no-entitlement step count instead, if any iPhone-side signal is wanted.

Either way, **this never blocks the core Mac-based product**, which is the whole
point of the architecture below.

### 4.4 Architectural conclusion: the Mac is the entire MVP

`NSWorkspace` (frontmost app), `CGEventSource` (idle detection), the Accessibility
API (window titles), and AppleScript/Apple Events (browser tab domains) are all
available to any signed Mac app with zero Apple review — just a one-time user
consent dialog in System Settings, no developer-portal entitlement involved at all.
None of this is paid-gated. Given that Mohit's actual focus work (coding, ZK
circuits, protocol research) happens almost entirely at the Mac anyway, building the
**entire Focus Drift Detector and Daily Replay product as a single, self-contained
macOS app** isn't a compromise forced by the $0 budget — it's the more useful
architecture for this specific person regardless. Treat the iPhone app (Section 7,
Phase 5) as a genuinely optional bonus, not something the core product waits on.

### 4.5 Foundation Models — still free, unaffected by any of the above

Apple's on-device LLM (Foundation Models framework, iOS 26/macOS 26+) is a plain
system framework available to any signed app, free or paid team — no entitlement
toggle, no developer-portal request, no API key, no cost. It only needs
Apple-Intelligence-capable hardware (iPhone 15 Pro+, M-series Mac) and the right OS
version. Always check `SystemLanguageModel.default.availability` before using it,
and keep a templated, non-AI fallback ready (Section 9.2) so the Daily Replay
narrative works regardless of hardware.

### 4.6 SwiftData, without CloudKit, is simple — no special schema rules needed

Since this project doesn't use CloudKit sync, none of the "every property must be
Optional or have a default value" CloudKit constraints apply. Model the data the
normal, idiomatic way: real types, sensible non-optional fields where a value is
genuinely always present, `Optional` only where a value is genuinely sometimes
absent. This is a meaningful simplification versus a CloudKit-backed design — take
advantage of it.

---

## 5. System Architecture

### 5.1 Repo layout

```
LifeReplay/
├── LifeReplayCore/              ← Swift Package, no AppKit/UIKit imports
│   ├── Models/                  ← SwiftData @Model classes (Section 6)
│   ├── FocusEngine/             ← drift detection + scoring (Section 8) — pure logic
│   ├── ReplayEngine/            ← timeline clustering + summarization (Section 9)
│   └── Tests/                   ← XCTest, runs on synthetic fixtures, no device needed
├── LifeReplay-Mac/               ← THE MVP. Menu bar agent + dashboard window.
│   ├── Collectors/                ← NSWorkspace, idle, Accessibility, AppleScript
│   └── UI/
├── LifeReplay-iOS/                 ← OPTIONAL, Phase 5 only. Build this last, if at all.
│   ├── HealthOrMotionManager/       ← HealthKit if Phase 0 probe says yes, else CMPedometer
│   ├── LocalSync/                    ← MultipeerConnectivity, sends data to the Mac app
│   └── UI/
├── DECISIONS.md
├── PROGRESS.md
└── README.md
```

`LifeReplayCore` is the part an agent can fully build and test without ever touching
a physical device or Apple's permission system — prioritize getting this rock-solid
first, since it's where you can self-verify correctness. `LifeReplay-Mac` alone is a
complete, useful product; everything in `LifeReplay-iOS` is additive.

### 5.2 Data flow

```
Mac collectors (always running, menu bar agent)
   → ActivityEvent rows in a single local SwiftData store (no sync needed)
   → FocusEngine consumes rolling window → FocusSession + DriftEvent rows
   → ReplayEngine clusters the day into timeline blocks
   → optional Foundation Models pass → DailyReplay.narrativeSummary
   → rendered in the Mac app's dashboard window

(Phase 5, optional)
iPhone app → CMPedometer / HealthKit (if available) / manual log entries
   → broadcasts over local Wi-Fi (MultipeerConnectivity) when in range of the Mac
   → Mac app receives and merges into the same local store
```

There is no cloud round-trip anywhere in this system. The Mac is always the source
of truth.

---

## 6. Data Model

Define these in `LifeReplayCore/Models/`. No CloudKit constraints apply (Section 4.6)
— model things the normal way.

```swift
@Model
final class ActivityEvent {
    var timestamp: Date
    var kind: ActivityKind
    var appBundleID: String?
    var appName: String?
    var browserDomain: String?
    var source: String = "mac"   // "mac" today; "iphone" if Phase 5 is ever built

    init(timestamp: Date, kind: ActivityKind, appBundleID: String? = nil,
         appName: String? = nil, browserDomain: String? = nil) {
        self.timestamp = timestamp
        self.kind = kind
        self.appBundleID = appBundleID
        self.appName = appName
        self.browserDomain = browserDomain
    }
}

enum ActivityKind: String, Codable {
    case appActivated, idleStart, idleEnd, browserDomain
}

@Model
final class AppCategory {
    var matchPattern: String      // bundle ID or domain substring
    var displayName: String
    var category: FocusCategory
    var isUserEdited: Bool = false

    init(matchPattern: String, displayName: String, category: FocusCategory) {
        self.matchPattern = matchPattern
        self.displayName = displayName
        self.category = category
    }
}

enum FocusCategory: String, Codable {
    case productive, neutral, distracting
}

@Model
final class FocusSession {
    var start: Date
    var end: Date?
    var category: FocusCategory
    var primaryAppName: String?
    var switchCount: Int = 0
    var idleSeconds: Int = 0

    init(start: Date, category: FocusCategory) {
        self.start = start
        self.category = category
    }
}

@Model
final class DriftEvent {
    var timestamp: Date
    var precedingSessionID: UUID?
    var triggerAppNames: [String] = []
    var switchCountInWindow: Int
    var baselineSwitchRate: Double
    var severity: Double   // 0-1, how far above baseline

    init(timestamp: Date, switchCountInWindow: Int, baselineSwitchRate: Double, severity: Double) {
        self.timestamp = timestamp
        self.switchCountInWindow = switchCountInWindow
        self.baselineSwitchRate = baselineSwitchRate
        self.severity = severity
    }
}

// Optional — only populated if Phase 5 is built AND Phase 0's probe found a
// usable data source (HealthKit or CMPedometer). The whole app must work with
// zero rows in this table.
@Model
final class HealthSnapshot {
    var date: Date
    var avgHeartRate: Double?
    var hrv: Double?
    var steps: Int?
    var sleepHours: Double?
    var workoutSummary: String?
    var sourceFramework: String   // "healthkit" or "coremotion", for debugging

    init(date: Date, sourceFramework: String) {
        self.date = date
        self.sourceFramework = sourceFramework
    }
}

@Model
final class DailyReplay {
    var date: Date
    var timelineBlocksJSON: String   // serialized [TimelineBlock]
    var focusScore: Int
    var narrativeSummary: String?
    var generatedAt: Date
    var usedOnDeviceAI: Bool = false

    init(date: Date, timelineBlocksJSON: String, focusScore: Int) {
        self.date = date
        self.timelineBlocksJSON = timelineBlocksJSON
        self.focusScore = focusScore
        self.generatedAt = Date()
    }
}

struct TimelineBlock: Codable {
    var start: Date
    var end: Date
    var label: String
    var category: FocusCategory
    var detail: String?
}
```

Seed `AppCategory` with sensible defaults on first launch, calibrated to Mohit's
actual toolchain — don't make him configure this from a blank slate:

- **Productive:** Xcode, VS Code, Terminal, iTerm, Cargo/rustc processes, Foundry/
  Hardhat tooling, Noir/nargo, Postman/Bruno, GitHub, Obsidian/Notion (if used for
  notes), localhost domains.
- **Neutral:** Slack, Mail, Calendar, Messages, Zoom.
- **Distracting:** Twitter/X, Instagram, YouTube, Reddit, WhatsApp Web, generic
  entertainment domains.

Make this table user-editable in the UI from day one — a fixed category list a user
can't correct is the fastest way to make a focus tracker feel wrong and get ignored.

---

## 7. Build Phases

Work through these in order. Each phase should be runnable and demoable before
moving to the next. **Phases 0-4 are the entire $0 MVP and require nothing beyond a
free Apple ID.** Phase 5 is genuinely optional.

### Phase 0 — Project setup + capability probe
- Xcode workspace, the package/target layout in 5.1, git initialized, free Personal
  Team signing.
- `DECISIONS.md` and `PROGRESS.md` created.
- Run the HealthKit probe from Section 4.3 and record the result. This determines
  the scope of Phase 5 later — do it now while it's cheap, not when Phase 5 starts.
- **Acceptance:** empty macOS menu bar app builds and launches on-device; the
  HealthKit probe result is documented either way.

### Phase 1 — Mac activity collector
- `NSWorkspace.didActivateApplicationNotification` → `ActivityEvent` rows.
- Idle detection via `CGEventSourceSecondsSinceLastEventType` polled every ~15s
  (no permission required for this specific API).
- Accessibility permission flow (one-time, System Settings deep link) for window
  titles; AppleScript-based browser domain capture for Safari/Chrome (Apple Events
  automation consent, one-time).
- Menu bar UI: running/paused toggle, today's raw event count, "open dashboard."
- **Acceptance:** leave it running for a real coding session; verify every app
  switch and idle period is captured accurately when you check the raw event log.

### Phase 2 — Focus Drift Engine (Core package, fully testable)
- Implement the algorithm in Section 8 against `ActivityEvent` fixtures — write
  this with unit tests *first*, using synthetic event sequences, since this is the
  one part you can fully verify without a human in the loop.
- Wire it to consume live `ActivityEvent`s from Phase 1 and produce real
  `FocusSession` / `DriftEvent` rows.
- Local notification (macOS) when a drift event fires, with a snooze/dismiss.
- **Acceptance:** unit tests green; a real session with intentional distraction
  (open Twitter mid-coding-session) produces a `DriftEvent` within the expected
  window.

### Phase 3 — Daily Replay generation + Mac dashboard UI
- Implement timeline clustering (Section 9.1) — Mac-only signals for now.
- Build the actual timeline UI matching the example in Section 1, in the Mac app's
  dashboard window.
- **Acceptance:** at the end of a real day, open the dashboard and get a timeline
  that matches what Mohit remembers doing, plus a Focus Score that feels
  directionally right to him (subjective check — ask him). **This is the MVP. It
  is a complete, useful product on its own, entirely free, entirely on one device.**

### Phase 4 — On-device narrative summary
- Implement Foundation Models summarization with the deterministic fallback
  (Section 9.2).
- **Acceptance:** the dashboard shows a one-paragraph plain-English recap of the
  day, generated locally, regardless of whether the device supports Apple
  Intelligence.

### Phase 5 — Optional iPhone companion (stretch — do not start until Phase 4 feels good to use daily)
- iPhone app: if Phase 0's probe found HealthKit available, use it for HR/HRV/sleep/
  workouts; otherwise use `CMPedometer` (Core Motion) for step counts only — this
  needs no entitlement at all and works on every free account.
- `MultipeerConnectivity` local-network sync to the Mac app (Section 4.2) — both
  devices on the same Wi-Fi, no internet round-trip.
- A simple manual "tag this block" feature (e.g. "Gym," "Lecture," "Commute") as a
  free, zero-permission alternative to automatic location/place detection, in case
  Mohit wants richer timeline labels without chasing more entitlements.
- **Acceptance:** a Health/Motion snapshot logged on the iPhone shows up in the
  Mac dashboard's timeline the next time both devices are on the same network.

### Phase 6 — Further stretch (genuinely optional, free either way)
- Place-based timeline labels via `CoreLocation` region monitoring against a small
  set of user-defined named places ("Hostel," "Library," "Gym") — standard "When in
  Use" location permission, no special entitlement, works on any account tier.
- Weekly/monthly replay rollups.

(Note: the iPhone Screen Time widget and any watchOS complication that depended on
HealthKit are intentionally **not** on this list — see Sections 4.1 and 4.3.)

---

## 8. Focus Drift Detection Algorithm

Rule-based, zero ML, all thresholds below are starting defaults — expose them as
user-tunable settings once the basic version works, since "what counts as drift"
is genuinely personal.

```
IDLE_THRESHOLD_SECONDS = 90        // no input → considered idle
SESSION_MIN_DURATION   = 90s       // shorter app-runs get merged into noise, not a new session
DRIFT_WINDOW_MINUTES   = 10        // look-ahead window after a sustained productive session
DEFAULT_BASELINE_SWITCHES_PER_HOUR = 12   // used until 7 days of real data exist

baseline_switch_rate(user, hour_of_day):
    if fewer than 7 days of history: return DEFAULT_BASELINE_SWITCHES_PER_HOUR
    else: rolling median of app-switches/hour for this hour-of-day, last 14 days

on new ActivityEvent:
    update current FocusSession (extend, or close + open new one if category changed
    and the new category has persisted >= SESSION_MIN_DURATION)

    if current/just-closed session.category == .productive
       and session.duration >= 5 minutes:
        switches_in_window = count of app-switch events in the following DRIFT_WINDOW_MINUTES
        if switches_in_window >= 2 * baseline_switch_rate(hour)
           and at least one switched-to app/domain is category .distracting:
               create DriftEvent(
                   severity = min(1.0, switches_in_window / (2 * baseline)),
                   triggerAppNames = the distracting apps involved
               )
```

Daily Focus Score (0-100), a starting heuristic — tune against real days, this is
not a scientifically derived formula. The health bonus only applies if Phase 5 was
built and a data source is actually present; otherwise its weight folds back into
the productive-minutes term:

```
If no Health/Motion data available (the default, $0-only build):
    productive_minutes / total_tracked_minutes        × 90   (capped contribution)
    + (1 − drift_events_today / expected_drift_today)  × 10   (clamped to [0,1] before scaling)

If Health/Motion data is available (Phase 5 only):
    productive_minutes / total_tracked_minutes        × 70
    + (1 − drift_events_today / expected_drift_today)  × 20
    + sleep_and_steps_bonus                            × 10   (small bonus if sleep ≥ 7h
                                                                 and step count ≥ personal median)
```

---

## 9. Daily Replay Generation

### 9.1 Timeline clustering
1. Pull the day's `ActivityEvent`s and `FocusSession`s.
2. Merge adjacent blocks of the same category if the gap between them is
   under 3 minutes (avoids a timeline fragmented into dozens of micro-blocks from
   normal tab-switching).
3. If Phase 5 health/motion data exists, overlay workout windows as their own
   blocks, taking priority over whatever the Mac was logging during that time
   (you're away from the desk). If it doesn't exist, skip this step entirely — the
   timeline is built purely from Mac signals and that's a complete product.
4. Output `[TimelineBlock]`, sorted, ready for both the UI and the summarizer.

### 9.2 Narrative summary
Check availability first:

```swift
import FoundationModels

let model = SystemLanguageModel.default
switch model.availability {
case .available:
    // build a LanguageModelSession, use a @Generable struct so the output is
    // structured (e.g. headline + 1-2 sentence summary), not free-text you have
    // to parse. Keep the prompt short: feed it the clustered TimelineBlocks +
    // DriftEvents for the day, ask for a short, factual recap — explicitly
    // instruct it not to be motivational-poster-y, just descriptive.
default:
    // deterministic fallback: a small templated function that turns the
    // longest productive block + total drift events into a one-line sentence.
    // This path must always work, regardless of hardware.
}
```

Keep the fallback genuinely good, not an afterthought — Mohit's actual hardware
availability for Apple Intelligence is unconfirmed, so this path may be the one
that runs every day.

---

## 10. Permissions Checklist

| Permission | Platform | Trigger | Available on free Personal Team? |
|---|---|---|---|
| Accessibility | macOS | window title reading | Yes — one-time user toggle in System Settings, no entitlement |
| Apple Events automation | macOS | AppleScript browser domain reads | Yes — one-time consent dialog, no entitlement |
| Notifications | macOS/iOS | drift alerts | Yes — standard prompt |
| Local Network | iOS/macOS | Phase 5 Mac↔iPhone sync | Yes — standard prompt, no entitlement |
| Core Motion (CMPedometer) | iOS | Phase 5 step counts | Yes — no entitlement at all |
| Location ("When in Use") | iOS | Phase 6 place labels | Yes — standard prompt |
| HealthKit | iOS | Phase 5 HR/HRV/sleep | **Unconfirmed — probe in Phase 0, see Section 4.3** |
| iCloud / CloudKit | iOS/macOS | (not used in this project) | **No — paid program only, see Section 4.2** |
| Family Controls / Screen Time | iOS | (not used in this project) | **No — paid program only, see Section 4.1** |

---

## 11. What You (Mohit) Must Do Manually

The agent cannot do these — they require a human, an Apple ID, or physical hardware:

1. Sign in with your free Apple ID in Xcode (Settings → Accounts) and select your
   Personal Team in each target's Signing & Capabilities tab.
2. Physically connect/trust your iPhone and Mac, and tap through the OS permission
   dialogs (Accessibility, Automation, Notifications, and HealthKit/Location if
   Phase 5 is built) — these require biometric or password confirmation the agent
   cannot provide.
3. Periodically reopen the project in Xcode and rebuild to the device (roughly
   weekly) to refresh the free provisioning profile before it expires — this is
   normal for free signing, not a sign something broke.
4. Be present for the "does this feel right" checks at the end of Phases 1, 2, and 3
   — the algorithm thresholds in Section 8 need a real human's judgment on whether
   a flagged moment was *actually* a distraction.

---

## 12. Engineering Practices

- `LifeReplayCore` gets real XCTest coverage — this is the part you can verify
  without a device, so don't skip it.
- Platform-glue code (collectors, Health/Motion, local sync) can't be meaningfully
  unit tested by an agent; instead, log generously (`os.Logger`, not `print`) so
  issues are diagnosable from console output during the manual on-device checks.
- Fail loud, not silent, especially around permissions: if Accessibility or
  HealthKit access is denied, show the user a clear in-app state explaining what's
  missing and how to fix it, rather than just collecting nothing.
- Avoid force-unwraps on anything that can legitimately be absent (any iPhone-side
  data in particular, since Phase 5 is optional and the app must run correctly with
  zero rows in `HealthSnapshot`).

---

## 13. Definition of Done for the MVP

Not "it compiles." The bar is: **Mohit opens the Mac dashboard at the end of a real
day and it tells him something true and specific about that day that he didn't have
to type in himself**, plus at least one drift event from that day that he looks at
and thinks "yeah, that's exactly when I lost it," not "what is this even flagging."
If the algorithm in Section 8 doesn't pass that gut-check after a few real days,
that's expected — tune the thresholds against real data rather than treating them
as fixed. All of this is achievable at $0, on one device, with a free Apple ID.