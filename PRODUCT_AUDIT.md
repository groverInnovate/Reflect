# Product audit

## The product promise

Life Replay is not a screen-time dashboard. It is a private evening mentor:

> Tell me what I actually did, distinguish work from rest and distraction, show me
> where attention broke, tell me how trustworthy the evidence is, and give me one
> practical improvement for tomorrow.

That promise requires honest accounting before it requires clever insights. A
beautiful summary built on guessed time is worse than a plain summary that admits
what it does not know.

## Problems found in the original implementation

| Problem | Why it made the product untrustworthy | Direction of the fix |
| --- | --- | --- |
| The daily event query stopped at 2,000 rows | A five-second collector can produce more than 17,000 rows in a day, so the end of a long day silently disappeared | Removed the fetch limit for daily analysis |
| Time was allocated from one state-change event to the next | A stale “last app” could absorb sleep, a crashed collector, or hours of missing evidence | Added active heartbeats and a maximum observation gap |
| Sleep was inferred from almost any long gap | A missed signal during a real work block could be mislabeled as sleep | Only very long gaps are repairable, and they are shown as inferred away/sleep |
| Idle was mixed into productive sessions | “Idle seconds” were easy to double-count or subtract inconsistently | Idle intervals now split the timeline and are excluded from active scoring |
| App activation and browser capture could count as two switches | One action could inflate drift severity and the user’s baseline | Same-timestamp switch signals are normalized to one transition |
| The baseline was always the default | Drift became generic instead of personal after enough history existed | Use the median same-hour rate after seven distinct days of history |
| Productive category was treated as a task | VS Code, Terminal, and a research browser could become one vague session | Timeline surfaces remain distinct; sessions are used for category-level scoring |
| The dashboard reported numbers without a confidence contract | The user could not tell whether a good score meant a good day or missing data | Daily Review now separates observed, idle/away, and not-assigned time and shows Tracking Health |
| Neutral time produced only a generic warning | The fastest path to better accuracy was hidden behind settings | The review names the top neutral app/domain patterns to classify |
| Multitasking was implied to be measurable per pane | macOS frontmost/app and sampled browser APIs cannot independently measure every visible split-screen pane | The UI and README say which surface was observed and which context is inferred |

## Current accounting contract

For each day, the replay uses three distinct evidence classes:

- **Observed:** a recent app, browser-domain, or heartbeat signal supports assigning
  the interval to a visible surface.
- **Idle / away:** macOS input inactivity or an explicit sleep/wake interval says the
  user was not actively interacting with the Mac.
- **Not assigned:** the collector had no fresh evidence. This time is never charged
  to the last app and is excluded from the focus score.

Productive, study, coding, distraction, and neutral totals are calculated only from
observed intervals. This is deliberately conservative: the app may under-report a
day when collection is unhealthy, but it must not manufacture productivity or
waste.

## What the mentor says today

The Daily Review is organized around five questions:

1. What happened? — ranked observed activity and a readable timeline.
2. What mattered? — productive, study/research, coding/tooling, and deep-work time.
3. Where did attention break? — drift events and named triggers.
4. Can I trust this? — Tracking Health, permission state, signal density, idle gaps,
   browser capture, and unassigned time.
5. What should change tomorrow? — one next action plus concrete category fixes when
   the app does not know what a neutral surface means.

The deterministic summary is the baseline. On-device Foundation Models are an
optional wording layer only; the product remains useful without Apple Intelligence,
network access, an API key, or a paid developer account.

## Known limits that are product decisions, not bugs

- The Mac collector observes the frontmost app and sampled active browser domain.
  It cannot truthfully allocate independent time to every pane in split-screen.
- Window titles improve context but do not prove the user was reading or thinking.
  They are evidence for labels, not a claim about mental state.
- A browser tab can change between polls. The collector reduces the interval to five
  seconds and emits heartbeats, but the exact instant of a change remains bounded by
  the sampling interval.
- A day with substantial unassigned time is not ready for judgment. The correct user
  action is to fix collection or permissions, not to interpret the score harder.
- No rule-based system can infer intent perfectly. User-editable categories and the
  category-fix suggestions are part of the learning loop for this personal tool.

## Acceptance bar for future changes

Do not call a change complete unless it preserves these invariants:

1. A long silent gap is never silently attributed to the preceding app.
2. Idle/sleep never increases productive, study, coding, or distraction minutes.
3. Heartbeats keep a real uninterrupted session continuous without inflating switch
   counts or drift severity.
4. The dashboard exposes uncertainty before interpreting the score.
5. A real 90-minute coding or study session, followed by an intentional distraction,
   produces a timeline and drift story that matches memory closely enough to trust.
