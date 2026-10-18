# Batch 8 — native reminder safety components

**Captain-issued brief set, prepared 2026-10-18.** The three assignments are ready to hand to workers; no worker has been started and no worker branch has been created. This workspace copy is not yet published.

## Frozen base and branches

All three independent worker workspaces must start at this exact immutable code base:

`68808ee41485138c6a22db3ee012d60c7f644175`

| Worker | Unique branch | Brief | Exclusive write scope |
|---|---|---|---|
| A | `agent/A/b8-native-sync-20261018` | `docs/briefs/AGENT_A_BATCH_8.md` | `lib/data/reminders/reminder_apply.dart`, `lib/data/reminders/native_reminder_sync.dart`, `test/data/reminders/reminder_reconcile_test.dart`, `test/data/reminders/native_reminder_sync_test.dart` |
| B | `agent/B/b8-payload-codec-20261018` | `docs/briefs/AGENT_B_BATCH_8.md` | `lib/data/reminders/native_reminder_payload.dart`, `test/data/reminders/native_reminder_payload_test.dart` |
| C | `agent/C/b8-tap-intent-20261018` | `docs/briefs/AGENT_C_BATCH_8.md` | `lib/features/common/reminder_tap_intent.dart`, `test/features/reminder_tap_intent_test.dart` |

The briefs are delivered separately from the frozen code base; workers should read their brief from the Captain's handoff or current `main`, then create their named branch from the exact SHA above. Do not rebase, reset, or cherry-pick another worker's branch. Work in separate workspaces.

## Why these three tasks

Batch 7 delivered the pending-aware ledger/applier, bilingual notification copy, plugin/runtime foundations, and safe failure composition. The app still lacks a real, identity-aware synchronizer binding and production tap route. Batch 8 builds three independent pieces without entering Captain-owned app composition or Android files:

- **A — synchronization:** connect the existing `ReminderSynchronizer` contract to the ledger/applier and make reconciliation compare complete pending identities, not only numeric IDs.
- **B — payload codec:** add strict, pure serialization for the existing namespaced `NativeReminderIdentity` contract.
- **C — tap intent queue:** safely retain a validated cold-start/foreground job tap until navigation is ready, then consume it once.

No worker may claim that plugin pending records prove a live OS alarm or delivery. This batch does not activate the native runtime.

## Frozen shared boundaries

- `lib/contracts/native_reminders.dart` is read-only and is the source of truth for `NativeNotifications`, `NativeReminderIdentity`, `NativePendingReminder`, `ReminderSynchronizer`, `ReminderSyncInput`, `ReminderSyncReport`, and the namespace/variant literals.
- No worker edits `lib/app/**`, `lib/contracts/**`, `lib/design_system/**`, `android/**`, `ios/**`, `lib/main.dart`, `pubspec.yaml`, `pubspec.lock`, `.github/workflows/**`, `tool/preflight.py`, `test/contracts/**`, `test/fixtures/**`, version numbers, or generated files.
- No dependency additions. Do not import another worker's new output; all branches are independent. Do not silently expand a file list. If a required change falls outside it, stop and ask the Captain.
- Do not request permission during synchronization, invent feed data, cancel foreign notifications, or convert backend acceptance into a delivery claim.

## Worker loop and checks

1. Confirm the branch starts at the frozen SHA and read the brief completely.
2. Edit only the listed paths. Preserve existing work; do not run archived Batch 1–7 starters/briefs.
3. Run only the listed focused test file(s), plus `python3 tool/preflight.py` before pushing the worker branch. If Flutter is unavailable, report **NOT RUN**, never PASS. No full test suite, analyze, build, Gradle, CI dispatch, CI wait, release, or `see_screen.py`.
4. Push only the worker's named branch. Do not merge, tag, release, change settings, or push `main`.
5. Hand off the exact branch SHA and exactly five lines:

```text
Batch 8: <agent> ready (<sha7>) / blocked — <reason>
Changed: <owned paths and outcome>
Evidence: <commands, actual results, limitations>
Not touched: <shared surfaces / excluded work>
Next: <Captain integration needs or none>
```

## Captain-only integration and remaining gates

After reviewing the three complete diffs and focused evidence, the Captain owns all integration under `lib/app/**` and Android: adapt the real plugin boundary to the frozen contract and B's codec; construct the real synchronizer/session binding; wire C's tap queue into the production navigator; provide the real external-launch callback; and do the shared-surface review. Real permission/revoke, cold-start tap, reboot/package-replacement, force-stop, timezone, offline/missing-feed, and notification-delivery checks still require an owner-authorized Android device. Production activation remains blocked until Keshab approves a real HTTPS feed URL and the native gates pass. No feed publication, CI dispatch, signing, Play release, or deployment is authorized by this brief.
