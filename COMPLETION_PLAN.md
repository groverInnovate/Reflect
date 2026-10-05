# Remaining acceptance work

The app is now Mac-only. The old companion, HealthKit, AI, reminder, mentor, and
weekly-score plans are cancelled. Do not treat them as backlog.

1. Install/select full Xcode so SwiftData macros can compile the production target.
2. Run `scripts/test-core.sh` under Xcode's toolchain, then `scripts/build-mac-app.sh`.
3. Verify an existing SwiftData store upgrades without losing raw activity/categories.
4. Grant Automation for used browsers and Accessibility if window titles are desired.
5. Track a timed work session, idle, sleep/wake, pause/resume, and a midnight boundary.
6. Compare exported seconds to the session and confirm the report is useful for planning.
7. Check the dashboard at minimum width, in dark mode, and with a full day's timeline.

No paid program, physical iPhone, Apple Watch, capability probe, or external service
is required for any of this work. OS permission approvals and the real-day judgment
remain human-owned checks.
