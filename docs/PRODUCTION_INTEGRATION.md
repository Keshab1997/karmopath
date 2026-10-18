# Captain production composition — status
Implemented under lib/app/runtime (captain-owned): AppRuntime dependency container, ProductionBootstrap retryable startup, ProductionShell navigation, live ID-based detail lookup and FeedConfiguration HTTPS syntax validation. No worker-owned source was changed.

## Implemented and tested
- Four bilingual bottom destinations using existing feature constructors; detail routes resolve against current repository state, so corrections update an already-open detail and removed IDs show unavailable rather than stale fabricated data.
- Detail stale-information banner when repository reports offline/error.
- Stored language is restored through injected readLanguage; changes are serialized through persistLanguage. A write failure says it was not saved; runtime close waits for pending writes and is idempotent.
- Startup dependency/settings failure is visible and retryable. Partially initialized runtime is closed; runtime returned after unmount is closed too.
- Initial refresh does not block rendering cache hydration. Refresh exceptions outside the repository contract are shown safely.
- Feed URL must be explicitly supplied as HTTPS without embedded credentials/fragment; no URL or production content is guessed. This is syntax validation, not proof that a host is trusted/public or content official.

Historical composition evidence: 8 new runtime tests; then-full Flutter suite 140 PASS; analyze clean; structural preflight PASS. Native plugins, web bundle, actual language persistence/storage, notification delivery and live feed were NOT exercised. No build, CI, release or publication performed.

## Activation remains pending
This composition is NOT yet selected by main.dart. Native entrypoint remains foundation; web design preview remains separate and labeled. Do not call this a launched production app.

After A adapters are reviewed, captain supplies a factory returning initialized AppRuntime: repository, preferences, AppActions, language read/write and close callbacks. That factory must clean up partial failures, own the http.Client, initialize LocalUserPreferences, and release repository/preferences/client in a finally-safe close path. FeedConfiguration requires an owner-approved endpoint; no private token in URL/app. Language key reserved: karmopath.language.v1 with values bn/en. Actual platform actions/notification scheduling are still pending; never return a fake permission grant.

Captain then wires the native entrypoint, tests persistent storage, external links, CORS, offline recovery and real-device notification behavior. A's new platform adapters are in lib/data/platform per current contract; no duplicate adapters were created in this captain batch.

## Release blockers unchanged
C admin review/publication workflow, actual human-reviewed notices, final art/visual review, support/correction/legal URLs, privacy/Data safety/consent, test AdMob and app-ads.txt, SDK/account/testers/signing/store submission. No secrets or legal acceptance invented.

## Batch 7 dispatch update — 2026-10-18
The owner requested parallel workers. [A7/B7/C7](DISPATCH_BATCH_7.md) now cover
reconciliation, the Android notification boundary and an independent native
runtime factory. Captain still owns lib/app/**, main, dependency/platform files,
lifecycle/tap navigation and final integration. Ports/prerequisites are frozen at
`bffcfb473d14f66bf47b85be96558497cc387dc4`; workers have not been started by Captain.
Current foundation evidence is [here](reports/CAPTAIN_BATCH_7_DISPATCH.md), not the
historical count above. No native factory/adapter/coordinator implementation has
yet been reviewed/integrated, and this update does not activate production.
