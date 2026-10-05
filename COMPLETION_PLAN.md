# Remaining acceptance work

The app is Mac-only. Debug and Release production builds now pass with Xcode 27.
Native XCTest, existing-store preservation, live collection/pause/resume, historical
report interactions, dark appearance, and production CSV accounting are verified.
See PRODUCTION_VERIFICATION.md for the exact checks.

1. Approve Accessibility and verify captured window/project titles.
2. Check minimum-width layout, category editing/save, and tracking settings/save.
3. Complete a CSV export through the macOS save dialog; the underlying exporter passed,
   but UI automation could not reliably complete this dialog interaction.
4. Check real idle, sleep/lock/wake, a live midnight crossing, and a timed work session.
5. Compare the full-day report with memory and confirm it helps plan the next day.

Do not restore companion devices, HealthKit, AI, reminders, coaching, or weekly scores.
No paid signing membership, external service, iPhone, or Apple Watch is needed.
