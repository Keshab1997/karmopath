# Captain native integration — current status

## Implemented code (not activated through `main.dart`)

Captain-owned runtime code now composes the injectable `AppRuntime`, retryable `ProductionBootstrap`, `ProductionShell`, validated HTTPS feed configuration, persistent native storage, HTTP repository, Android notification backend, shared reminder ledger, default `NativeReminderSession`, and lifecycle/language hooks. The runtime factory is wired to the reviewed ledger-backed synchronizer; it no longer requires a custom session implementation. This is an integrated native runtime, **not an activated production application**.

- Existing screens and detail routes resolve current repository data; missing IDs show unavailable, stale data has a warning, and no fake live jobs are substituted.
- Language read/write uses `karmopath.language.v1` (bn/en); unknown/unreadable settings fail rather than silently reset. Visible language reaches the session immediately even when serialized persistence fails.
- Partial native initialization registers and releases acquired preferences/ledger, HTTP client, repository, actions, notifications, synchronizer and session in reverse order; cleanup attempts continue after a cleanup error and preserve the primary initialization error. Close is idempotent and waits for language writes/session drain.
- The session serializes synchronization from verified feed, stored intent, language changes, explicit retry and resume. An unloaded or stale offline feed is not treated as an authoritative empty feed. Startup and resume do not prompt for permission.
- The reconciler compares full notification identity, uses the persistent namespace/ID ledger, preflights duplicate/foreign/reserved-ID conflicts, and only reports effects confirmed by the backend/ledger path. Focused tests cover conflict and repair cases. These tests do not prove a live Android alarm or delivery.
- The shell exposes bilingual sync status and explicit retry, and drains validated cold/foreground tap intents only when navigation is ready. A tap is an in-memory intent, not a delivery receipt.
- Notification permission is requested only by an explicit user action. Scheduling is UTC one-shot `inexactAllowWhileIdle`; no exact-alarm permission or shortened production interval is enabled.
- `external_uri_launcher.dart` now uses the real `url_launcher` system handler by default, validates public HTTPS links, and reports false/platform failures. Tests can inject a launcher; the production default is not a fake-success callback.
- Existing Android manifest/boot receiver, notification channel/icon resources, desugaring and dependency pins were retained. Code and fake/widget tests cover startup/resume and tap routing, but not real device behavior.

## Activation and verification still pending

`lib/main.dart` selects the native composition only when the compile-time `KARMOPATH_FEED_URL` is non-empty; empty/default keeps the foundation screen, and the isolated web preview remains separate. The owner-approved non-production Gist fixtures are documented in [`test-feed/README.md`](../test-feed/README.md) and the device plan. These fixtures are not production data. `FeedConfiguration` checks URL syntax only; it does not prove public reachability or source accuracy.

`.github/workflows/manual-build.yml` now has an optional `test_feed_url` input for APK testing and forwards it as `KARMOPATH_FEED_URL`; leave it blank for the foundation screen. AAB builds ignore the test URL. Only use the approved public, credential-free fixture; the URL is embedded in the APK. The owner will dispatch the manual build workflow; signing secrets must remain in GitHub. Release signing configuration reads `android/key.properties`, but no Android Gradle run or signed artifact has verified it. No build or CI dispatch has been performed.

The Android device plan, `docs/ANDROID_REMINDER_DEVICE_TEST_PLAN.md`, remains entirely `NOT RUN`. Owner-run checks are still required for permission/denial/reenable, cold and foreground taps, successful-empty/unavailable feeds, offline behavior, reboot/package replacement, force-stop/relaunch, timezone and actual notification delivery. The boot receiver and startup/resume reconciliation are code paths only; plugin pending records are not proof of live alarms or delivery. The safe overdue-reminder behavior also needs the planned real-device review; no late-opt-in catch-up was added.

## Release blockers remain owner-gated

Human-reviewed source content, final art/visual acceptance, support/correction/legal URLs, privacy/Data safety/consent, test ads/app-ads.txt, account/testers/signing and Play submission remain separate release work. The owner deferred release preparation. Do not invent credentials, legal acceptance, publication or Play approval.
