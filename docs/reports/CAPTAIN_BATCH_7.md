# Captain Batch 7 — reviewed code/docs publication, native activation still blocked

## Authority and scope

On 2026-10-18 Keshab explicitly requested that all reviewed work be pushed to `main`. This lifts the earlier local-only/public-push hold for this Batch 7 code/docs payload, not for production feed/native activation, deployment, CI, tags/releases, settings/secrets or paid services.

The candidate preserves the fetched published main base `00e3b29ab44a20f517c0fdb2e071068edb13e4af` and its preceding native-port/Android prerequisites. Captain uses reviewed squash commits and a normal fast-forward main push; no force-push, reset, branch deletion or tag/release is part of this publication. The final remote SHA is verified after push and reported in chat; this file does not invent its own future commit ID.

## Immutable reviewed inputs

| Stream | Original input | Captain integration |
|---|---|---|
| A | `85dca4c1c7b7aec9a4becd5493128d6268cec899`, `agent/A/b7-os-reconcile-20261018`, frozen base `80adedc` | Actual three-file diff reviewed; squash `d949ea5`; one subsequent test-only wildcard lint fix in `691e9be` |
| B | `d1a79a2e810188b095d45c6156ccd376e2823af7`, `agent/B/b7-notification-copy-20261018`, same frozen base | Actual four-file diff reviewed; squash `07864fc` |
| Captain | Previously reviewed/tested local foundation `c66b15e` | App/runtime/notification sources and app tests selected explicitly; only app/test adaptation is using the already-published icon/channel constants instead of the older icon/channel-name literals |

A/B implementation, reports and tests were reviewed, not accepted on report assertions alone. Allowed-path, credential-literal and diff checks passed. No worker dependency/version/workflow/platform or shared-fixture edits were accepted. Their reports retain the original pre-push local snapshot wording; remote branch heads above were actually fetched and verified during review.

The later proposed three-worker dispatch is not the delivered two-worker handoff. Its native ports/tests, dependency/lock pins and Android icon/keep/receiver/desugaring prerequisites remain unchanged. Its alternative output class/path names are NOT falsely marked implemented, and no C implementation is claimed. Historical starters/briefs now say not to execute them. The actual delivered two-worker brief snapshots are archived for provenance. Future work requires a new Captain brief/current immutable base, not duplicate old assignments.

## Published implementation boundary

- A extends the existing applier with queued pending-aware reconciliation: stable-ID repair, known crash-window orphan cancellation, deterministic cancel-before-schedule, per-operation storage/failure handling and unknown pending allocation collision protection. Existing `apply`/`applyDiff` signatures/behavior and storage schema/keys remain intact.
- B adds pure explicit-language notification content, exact approved Bengali/English body, full feed titles/job IDs and `bn@reminder-v1` / `en@reminder-v1` variants. No global-language mutation, permission/storage/scheduling effect or invented timestamp.
- Captain provides an Android-only pinned-plugin driver, concrete permission-safe `ReminderPlatform`, single-flight explicit permission actions, storage/language adapter, finally-safe acquired-resource runtime factory and queued feed/intent/language/resume session orchestration. Close preserves durable OS schedules, attempts all cleanup and retains primary initialization failures.
- Runtime/shell hooks are backward-compatible; visible language updates the session even if persistence fails, resume observers detach on disposal, and real preferences/repository reach the existing settings summary. An unloaded feed never becomes an authoritative empty desired plan.
- `reminderAndroidIcon`, `reminderAndroidChannelId` and `reminderAndroidChannelName` are reused from the existing shared contract. The old extra `ic_stat_reminder` resource/keep file and older package/platform snapshots were deliberately NOT copied over main's newer prerequisites.
- `lib/main.dart` is unchanged. **The real required reconciliation/content/session binding and external launcher composition remain pending; there is no fake-success default.** The app is not activated as a production native runtime by this push.

## Actual final combined gates

Shared/risky full Flutter tests and analysis were announced before running. On the combined reviewed A/B + current-main prerequisites + adapted Captain foundation:

| Gate | Actual result |
|---|---|
| `flutter test --reporter expanded` | **552 passed**: 471 existing main/foundation-port tests + 17 A + 8 B + 56 Captain app tests |
| `flutter analyze` | **No issues found** |
| `python3 tool/preflight.py` | **PASS**, structural only |
| App-focused `flutter test test/app` | **66 passed**, including 56 new Captain tests and 10 existing app/preview regressions |
| Diff/scope/credential checks | **PASS** |
| Existing Android permission/receiver/icon/keep XML checks | **PASS**, structural only, not native compilation/device evidence |
| Preserved-main check | Entrypoint, native contracts/tests, packages/lock, Android, workflows, assets/design-system unchanged from fetched main |

Actual SDK: Flutter 3.47.7 / Dart 3.13.5. The current 552-test combined result supersedes the separate earlier 496-/508-test phase snapshots; those counts must not be summed. The final report/status documentation is not a claim of another code test run.

NOT RUN: Flutter build/Gradle, Android device permission/reboot/force-stop/delivery tests, web build, CI dispatch/wait, deployment, release. Python feed/Node admin suites were not rerun for this Flutter/docs-only integration; their older evidence is historical, not a new claim.

## Remaining native/release work — not hidden by a successful code push

1. Supply the REAL required runtime session binding connecting A's reconciler, B's content/variant and the concrete notification platform. Complete operational failure/retry/status composition and a real external launcher. Do not replace the mandatory callback with an empty successful session.
2. Implement namespace/full-identity validation, safe cold/foreground job-ID tap navigation and foreign/reserved-ID conflict protection using the retained metadata ports. B's content payload is a full job ID; any native namespace/identity envelope belongs to the Captain adapter.
3. Plugin pending requests are persisted registry entries, not independent proof of live AlarmManager alarms. A matching ledger/plugin ID set cannot prove alarm survival after force-stop/reboot. Finish safe startup/resume repair and verify previously scheduled overdue behavior; the no-late-opt-in catch-up rule does not promise exact Android delivery.
4. Verify denial/reenable, boot/package replacement/force-stop/cold start, timezone, offline/missing feed and actual notification behavior on Android. Mocked method-channel/widget tests do not establish these results or OEM reliability.
5. Obtain Keshab's explicit real public HTTPS feed URL approval before native entrypoint activation, also contingent on the integration/hardening gates above. No guessed/live demo feed, feed publication, ads/payment/signing, Play submission or legal acceptance is authorized by the main-push request.

Web demo remains isolated, all workflows remain manual-only, secrets/settings and release boundaries remain untouched. Worker branches and the original local foundation/review branches are retained; no unrelated work is discarded.
