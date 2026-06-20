# Life Replay

Life Replay is a local-first macOS focus journal that reconstructs what happened during a day and flags moments where a productive session drifted into distraction.

The MVP is intentionally Mac-only and free-signing friendly: no CloudKit, no Screen Time APIs, no backend, and no paid Apple Developer Program dependency.

## Current Shape

- `LifeReplayCore/` contains pure models and engines that can be tested with synthetic fixtures.
- `LifeReplay-Mac/` contains the macOS menu bar app target.
- `AGENTS.md` is the project spec and operating manual.
- `DECISIONS.md` and `PROGRESS.md` are the handoff trail for future sessions.

## Local Commands

```sh
swift test
swift run LifeReplayMac
```
