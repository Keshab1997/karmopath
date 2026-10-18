# Batch 7 — reviewed A/B helpers and native foundation

## Current state

Keshab requested the earlier **two-worker + Captain** split, received A/B's pushed branches, and then explicitly authorized all reviewed work to be pushed to `main`. The later three-worker proposal is retained as historical design material, not an executable dispatch. Do not launch duplicate work from its starters/briefs.

This publishes the reviewed helpers and Captain foundation, **not a completed production native runtime or release**. `lib/main.dart` still selects the foundation or isolated web demo. There is no approved real production feed, Android device-delivery evidence, APK/AAB or release in this batch.

## Reviewed inputs and delivered code

| Stream | Immutable input | Delivered implementation |
|---|---|---|
| A | `85dca4c1c7b7aec9a4becd5493128d6268cec899`, `agent/A/b7-os-reconcile-20261018` | `ReminderApplier.reconcile` in existing `lib/data/reminders/reminder_apply.dart`, new focused regression file and A7 report |
| B | `d1a79a2e810188b095d45c6156ccd376e2823af7`, `agent/B/b7-notification-copy-20261018` | Pure explicit-language `ReminderNotificationContent` builder, exact approved Bengali/English body and stable variants, focused tests and B7 report |
| Captain | local foundation `c66b15e`, reconciled with published main `00e3b29` | `lib/app/notifications/**`, native storage/factory/session and lifecycle/language hooks under `lib/app/runtime/**`, targeted app tests; uses the existing published icon/channel constants |

A/B both branched from `80adedcae21629c5c6928f30f7852f6640539ec4`. Captain reviewed actual full diffs, scope, secrets and tests before local squashes (`d949ea5`, `07864fc`) and fixed one test-only wildcard lint (`691e9be`). The current published main's native contracts/tests, package/lock pins and Android prerequisites were preserved rather than overwritten with the older foundation snapshot.

Full gate/publication evidence and precise limitations: [CAPTAIN_BATCH_7.md](reports/CAPTAIN_BATCH_7.md). Historical local phase/review reports are retained as historical snapshots, not current push restrictions. Delivered worker reports also describe their original pre-push snapshot.

## What is deliberately still blocked

1. Implement the REAL required runtime binding between A's reconciler, B's content/variant, concrete notification platform and session listeners. The factory requires this callback; it does not default to fake success.
2. Finish namespace/full-identity/foreign-ID collision handling, safe notification tap navigation, operational retry/status composition, and startup/resume repair. The retained shared ports are design/API references, not a claim that the alternative `DefaultReminderSynchronizer` / `AndroidNativeNotifications` / C factory outputs exist.
3. Plugin pending requests are a persisted backend registry, not an independent AlarmManager audit. Reboot/force-stop/startup divergence and previously scheduled overdue requests need explicit hardening and real-device verification. Unit tests cannot establish delivery or OEM reliability.
4. Keshab must explicitly approve a real public HTTPS feed URL before native entrypoint activation. No guessed URL, fake live jobs, publication, ads/payment, signing, Play release or CI dispatch is authorized by the code-push approval.

The isolated web demo, manual-only workflows, secrets/settings and release boundaries remain unchanged. No local Flutter build, Gradle or CI was run.

## Historical plans — do not execute

- Delivered two-worker brief snapshots: `docs/briefs/archive/AGENT_A_BATCH_7_TWO_WORKER.md`, `docs/briefs/archive/AGENT_B_BATCH_7_TWO_WORKER.md`.
- Later proposed three-worker dispatch: `docs/DISPATCH_BATCH_7.md`, `docs/START_BATCH_7_BN.md`, `docs/briefs/AGENT_[ABC]_BATCH_7.md`.
- Retained shared native ports/reference: `docs/BATCH_7_CONTRACTS.md`, `lib/contracts/native_reminders.dart` and contract tests.

No worker is currently assigned a new task. Future work starts only with a fresh Captain brief and current immutable base; preserve all existing work and branches.
