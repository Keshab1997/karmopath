# Captain Batch 7 — independent native foundation, LOCAL ONLY

> Historical local-phase snapshot. Keshab subsequently authorized the reviewed code to be pushed to main. The publication/integration status and remaining gates are in [CAPTAIN_BATCH_7.md](CAPTAIN_BATCH_7.md); the earlier hold and icon choice below are not current instructions.

## Status / authority

Keshab approved the existing-ownership A/B + Captain split, then explicitly selected **chat briefs only, no public push**. He reports A and B are working in their own workspaces. No worker code has been retrieved or reviewed; no worker completion is claimed.

Captain branch: `captain/b7-native-wiring-20261018`, on the local dispatch commits (`c67c696`, `825fb3b`), based on immutable remote code `80adedcae21629c5c6928f30f7852f6640539ec4`. Remote/local `main` have not been changed by Captain. All new implementation is local and not merged/pushed. No public upload/PR or file-transfer workaround is authorized.

This is **not Batch 7 completion**, a production-ready native entrypoint, a release check, or evidence of Android delivery/reboot behavior.

## Independent captain implementation

- Pin `flutter_local_notifications: 22.3.2` and `timezone: 0.11.2`, after checking actual published metadata/source and resolving with Flutter 3.47.7 / Dart 3.13.5. No existing app version/dependency was upgraded. New transitive packages are resolver output in the lockfile.
- `lib/app/notifications/native_notification_driver.dart`: Android-only plugin boundary, single-flight/retryable initialization, separate non-prompting permission query versus explicit permission request, pending-ID query with errors preserved, scoped cancellation, UTC one-shot **inexactAllowWhileIdle** scheduling. Null/unknown permission never becomes success. Closing a runtime does not cancel durable OS schedules.
- `local_reminder_platform.dart`: concrete `ReminderPlatform`, stable-ID validation, real permission gating with no startup prompt, future-time recheck after async query, exact-job payload validation, error propagation. No catch-up is created from an already-past desired due instant. It accepts a content callback rather than importing B's as-yet-unavailable file.
- `native_app_actions.dart`: explicit user-action permission flow, single-flight prompt shared across simultaneous requests, grant recheck, late-result rejection after runtime closes, validated HTTPS external-launch callback. A real external launcher is required; there is no default fake-success implementation.
- `lib/app/runtime/native_storage.dart`: existing SharedPreferences adapters plus one captain-owned `karmopath.language.v1` string key; absent language defaults to Bengali, unknown/read-failed language fails honestly, no clear/remove of settings or reminders.
- `native_runtime_factory.dart`: composes HTTP transport/repository, preferences, ledger, exactly one applier, notification driver and a REQUIRED real reminder-session binding. Each acquired resource is registered before the next await; partial failures unwind in reverse order, attempt every release and preserve the original initialization error. Close is idempotent and drains the session before closing dependencies. No guessed feed URL, demo jobs or no-op reminder binding.
- `native_reminder_session.dart`: one queued callback path for validated-feed, reminder-intent, visible-language and resume triggers; fresh planner/clock evaluation, preserved per-operation failures, listener cleanup/drain. **No feed is not an empty feed**: an unloaded/failed first fetch cannot erase pending reminders. The actual A/B reconciliation/content closure remains required/incomplete until their code is available.
- `app_runtime.dart` / `production_shell.dart`: optional backward-compatible session hooks; visible-language change reaches the session even if language persistence fails; lifecycle resume observer is removed on dispose; real preferences/repository now reach the existing settings summary. Web preview composition and `lib/main.dart` are unchanged.
- Android manifest: Internet, notification and boot permissions; documented scoped schedule/boot receivers for boot/package-replace actions. No exact-alarm, full-screen, policy-access or other elevated permission. Desugaring `2.1.4`, white drawable notification icon and resource-shrinker keep file. Existing Java 17 / AGP 9.1.0 / Flutter compileSdk 36 / minSdk 24 are retained. These are source/structural checks, not native compilation evidence.

## Gates

The shared/risky analyzer/full-test run was announced to Keshab before running. No build, Gradle or CI was run.

| Gate | Result |
|---|---|
| `python3 tool/preflight.py` | PASS — structural only |
| Targeted new captain tests | 56 tests added across app/notification/storage/factory/session/lifecycle boundaries |
| `flutter test` | 508 passed (452 pre-existing + 56 captain tests); does NOT include A/B's unpublished changes |
| `flutter analyze` | No issues found |
| `git diff --check` | PASS |
| XML/permission/receiver/icon/keep/desugaring structural checks | PASS; not an Android build/device test |
| A/B integration/diff review | NOT RUN — no approved branch-push handoff |
| Android build/device permission/reboot/force-stop/delivery checks | NOT RUN |
| Web build / Python feed / Node admin suites | NOT RUN for this Dart/Android-only phase; no claim beyond existing Flutter preview tests |

## Still blocking real native integration / activation

1. Obtain separate explicit public-push approval before any branch handoff or Captain push. Only then fetch A/B branches, review their actual diff/scope/secrets and run the relevant gates. Do not copy work or credentials between sandboxes as a workaround.
2. Implement the real required binding from `ReminderSessionDependencies` to `NativeReminderSession`, B's explicit-language content/variant helper, the concrete platform and A's pending-aware `reconcile`. Never replace missing A/B code with a no-op or claim it was reviewed.
3. **OS versus plugin cache is a substantive remaining hardening issue:** this plugin's native `pendingNotificationRequests()` reads its persisted request cache. Cached IDs alone do not prove live AlarmManager alarms survived force-stop/reboot. The final startup binding must safely repair/reapply when necessary; a matching ledger/cache ID set is not sufficient evidence. Do not declare reconciliation complete from mocked pending IDs.
4. The standard plugin boot receiver reschedules persisted requests. Its native source does not filter an overdue one-shot before rescheduling. Confirm/guard the intended handling of previously scheduled but overdue requests; do not confuse the frozen **no late-opt-in catch-up** rule with a guarantee that Android inexact delivery is never delayed. Reboot/package-replace/force-stop and foreground startup repair must be verified together before activation. No delivery or reboot success is claimed here.
5. Expose operational failure/retry state appropriately in the final native composition without changing truthful stored-intent subtitles into scheduling/delivery promises. Bind a real external launcher. Review language/copy replacement behavior against A's actual result semantics.
6. Keshab must explicitly approve a real public feed URL. Native `lib/main.dart` activation stays OFF, also pending the integration/hardening gates above. Do not guess/host/publish a feed, enable ads or advance release/policy/tester checks without the required owner inputs/approvals.

## Verified references (2026-10-18)

- Plugin version/requirements/Android setup: https://pub.dev/packages/flutter_local_notifications/versions/22.3.2
- Exact package metadata/archive: https://pub.dev/api/packages/flutter_local_notifications/versions/22.3.2
- Timezone metadata/archive: https://pub.dev/api/packages/timezone/versions/0.11.2
- Boot and pending-cache behavior inspected in the published plugin archive: `android/src/main/java/com/dexterous/flutterlocalnotifications/FlutterLocalNotificationsPlugin.java` and `ScheduledNotificationBootReceiver.java`.
- Installed SDK was SHA-verified by the bootstrap against the official Flutter release manifest. Actual `flutter --version`: Flutter 3.47.7 / Dart 3.13.5.

No secrets/settings/workflows, feature/data ownership, native entrypoint, feed publication, Pages/deployment, tags/releases or public branches were changed/pushed by Captain.
