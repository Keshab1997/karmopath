# Captain production composition — current status

## Present implementation

Captain-owned `lib/app/runtime/**` contains the injectable `AppRuntime`, retryable `ProductionBootstrap`, navigation/live ID-based `ProductionShell`, HTTPS syntax-only `FeedConfiguration`, native storage/factory/session and lifecycle/language hooks. `lib/app/notifications/**` contains an Android notification driver, concrete `ReminderPlatform` and explicit user actions. These are reviewed/tested foundation code, **not an activated production native application**.

- Existing screens/detail routes resolve current repository data; removed/missing IDs show unavailable, stale data has a warning, no fake live jobs are substituted.
- Language read/write uses `karmopath.language.v1` (bn/en); unknown/unreadable settings fail rather than silently reset. Visible language reaches the session immediately even when its serialized persistence fails.
- Partial native initialization registers and releases acquired preferences/ledger, HTTP client, repository, actions, driver and session in reverse order; cleanup attempts continue after a cleanup error and preserve the primary initialization error. Close is idempotent and waits for language writes/session drain.
- Session orchestration observes stored intents, verified feed, language and resume; an unloaded feed is not an authoritative empty feed. The actual reconciliation/content closure is REQUIRED, not replaced by a successful no-op.
- Notification queries do not prompt. Only explicit `AppActions.requestReminderPermission()` may request permission; denial/unknown state is never a grant. Scoped cancellation remains possible after denial. Native scheduling validates ID/content/future time, rechecks the clock after an async permission query and uses UTC one-shot `inexactAllowWhileIdle` without exact-alarm permission.
- The already-published icon/channel constants, Android manifest/desugaring/keep resources and dependency/lock pins were retained; the older foundation icon literal was adapted to `ic_stat_karmopath`.
- The factory requires a real external-launch callback; launcher/binding tests use explicit injected fakes only. No default fake-success production launcher is provided.

Current gate evidence and reviewed immutable inputs: [CAPTAIN_BATCH_7.md](reports/CAPTAIN_BATCH_7.md). Historical runtime/dispatch/local-phase counts elsewhere are historical snapshots, not additional current test runs or Android/device proof.

## Activation and final binding remain pending

`lib/main.dart` is unchanged: native still selects the foundation; the labeled isolated web demo remains separate. `FeedConfiguration` validates URL syntax only, not host/public reachability or official accuracy. A real endpoint requires explicit owner approval; never guess one or embed credentials.

The delivered A/B work follows the earlier two-worker plan: A extends the applier's pure reconciliation; B supplies pure notification content. The alternative three-worker output names/paths in archived briefs are NOT claims of implemented classes. The shared native ports/tests remain intact as reference for remaining work.

Before activation Captain must connect the real A/B/platform/session binding, namespace/full-identity/foreign-ID conflict handling, safe cold/foreground tap navigation, operational failure/retry state and a real launcher. Plugin `pendingNotificationRequests()` reads a persisted backend registry; matching IDs do not independently prove live AlarmManager alarms survived reboot/force-stop. Finish a safe startup/resume repair strategy and verify handling of previously scheduled overdue reminders. The frozen rule forbids new late-opt-in catch-up; inexact Android delivery can still be delayed.

Real-device permission/denial/reenable, reboot/package replacement/force-stop/cold start, timezone and actual delivery evidence is still NOT RUN. Flutter/widget/method-channel/fake tests do not replace these checks. No local Flutter build/Gradle, CI dispatch/wait or deployment was performed. Explicit code-push approval is not feed/native activation/release approval.

## Release blockers unchanged

Human-reviewed source content, final art/visual acceptance, support/correction/legal URLs, privacy/Data safety/consent, test ads/app-ads.txt, account/testers/signing/store submission remain separate owner-gated work. Do not invent credentials, legal acceptance, publication or Play approval. Future worker tasks require fresh Captain briefs; historical Batch 7 starters are not active assignments.
