# Batch 8 follow-up — platform adapter and visible retry status

**Captain-issued follow-up brief set, prepared 2026-10-18.** B's codec and C's tap-intent queue are complete, reviewed, and tested. These new assignments use each worker's own reviewed output as its frozen base. Drafts are local; no follow-up branch has been created.

## Assignments and immutable bases

| Worker | Frozen base | New branch | Brief | Exclusive write scope |
|---|---|---|---|---|
| B | `00d9662de63847671a21cc888eeb2c9508205de7` (B's codec handoff) | `agent/B/b8-android-native-notifications-20261018` | `docs/briefs/AGENT_B_BATCH_8_PLATFORM.md` | `lib/platform/notifications/android_native_notifications.dart`, `test/platform/notifications/android_native_notifications_test.dart` |
| C | `6de52013ca3574087d4a9c2c1e363a053f426090` (C's tap-queue handoff) | `agent/C/b8-reminder-status-ui-20261018` | `docs/briefs/AGENT_C_BATCH_8_STATUS_UI.md` | `lib/features/common/strings.dart`, `lib/features/common/reminder_sync_status.dart`, `test/features/reminder_sync_status_test.dart` |

These are continuations of B and C's own reviewed work, not cross-worker dependencies. Start each new branch at its exact listed SHA in a separate workspace; read the new brief from the Captain's handoff/current `main`. Do not rebase, reset, or cherry-pick the other worker's output.

## Why there is useful work

- **B:** the frozen `NativeNotifications` port and B's tested payload codec still lack a concrete Android backend. B can implement it outside Captain-owned `lib/app/**` and `android/**`; the Captain will decide how to connect it to the app after review.
- **C:** the runtime already records reminder synchronization failures, but the feature layer lacks a reusable, bilingual, truthful status/retry surface. C can implement that UI component without editing Captain-owned runtime composition.

## Shared constraints

- Existing contracts and channel/namespace literals are read-only. No dependency additions, manifest changes, `lib/app/**`, `android/**`, `lib/main.dart`, or production activation.
- Do not claim that plugin pending records prove a live OS alarm or delivery. No copy may promise that a notification was delivered.
- Workers edit only their allowlist, use independent workspaces, and push only their named branch. No merge, PR, tag, release, CI dispatch/wait, or `main` push.
- Run only the focused test in the corresponding brief plus `python3 tool/preflight.py`. No full suite, analyze, build, Gradle, or device claims. If Flutter is unavailable, say **NOT RUN**.
- Hand off the exact SHA using the five-line Batch 8 report format in `docs/DISPATCH_BATCH_8.md`.

The Captain retains app/runtime integration, shared-surface review, Android/device gates, feed approval, and all production activation decisions.
