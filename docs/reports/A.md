# Worker A report — batch 1

Branch: `agent/A/data-v1`, based on the immutable foundation
`f184482e4b74216c5ab91b0fd45f3f6d180a3d76` (the docs-only dispatch commit
`d0c4b72` is intentionally not the base).
Contracts followed: `docs/CONTRACTS.md` (Dart surface and storage keys),
`docs/briefs/AGENT_A.md`, `AGENTS.md`. No contract signature was changed.

## Scope delivered (lib/data, test/data only)

| File | What it is |
|---|---|
| `lib/data/feed_transport.dart` | `FeedTransport.fetch()` boundary; captain provides the HTTP adapter. |
| `lib/data/feed_cache.dart` | `FeedCache.read()/write(String)` boundary; captain provides the file/prefs adapter. |
| `lib/data/preferences_store.dart` | `PreferencesStore.readStrings/writeStrings` boundary; captain provides the platform adapter. |
| `lib/data/cached_job_repository.dart` | `CachedJobRepository({required this._transport, required this._cache})` implementing `JobRepository`. |
| `lib/data/local_user_preferences.dart` | `LocalUserPreferences({required this._store})` with `initialize()`; keys `karmopath.saved.v1`, `karmopath.reminders.v1`. |
| `test/data/fakes.dart` | Fake transport, cache, preference store, feed builders, state recorder (no `main`, not a test file). |
| `test/data/cached_job_repository_test.dart` | 20 repository tests. |
| `test/data/local_user_preferences_test.dart` | 15 preference tests. |

Note on the constructor syntax: Dart 3.13 accepts private fields as named
initializing formals, so call sites still use the contract spelling
`CachedJobRepository(transport: …, cache: …)` /
`LocalUserPreferences(store: …)`.

## Behaviour implemented

**Refresh pipeline.** State is published as `JobFeedState` only. A refresh
publishes `isLoading: true` immediately, hydrates the saved copy when no feed is
in memory yet (shown as `isOffline: true`), then fetches. The transport payload
is parsed by the frozen `JobFeed.fromJson`/`Job.fromJson` **before** the cache is
touched; only a fully valid document is written back. Success publishes the new
feed with `isOffline: false` and clears `lastError`.

**Preserve last good state.** Any failure — transport error, malformed JSON,
unknown schema, duplicate ids, invalid job — keeps the previous `JobFeed`
instance (identity preserved), keeps the previous cache bytes, and reports
`lastError`. The repository never throws out of `refresh()` for network,
validation or cache problems.

**Concurrency.** `refresh()` is single-flight: callers that arrive while an
attempt is running receive the same `Future`, so one response cannot commit
twice or out of order.

**Cache recovery.** Empty cache → normal path. Unreadable or damaged cache is
treated as "no copy" (never handed to the UI); a later successful refresh
overwrites it. Corrupt cache plus failed network surfaces a damage message
instead of crashing.

**User-safe errors.** `lastError` is one of five fixed prose strings
(`offlineWithCacheMessage`, `offlineNoCacheMessage`,
`invalidFeedWithCacheMessage`, `invalidFeedNoCacheMessage`,
`corruptCacheMessage`, plus `cacheWriteFailedMessage` when fresh data loaded but
could not be saved). No exception text, URL or status code reaches the UI.
`isOffline` means "what you see is not fresh from the network": true while a
saved copy is shown or the network failed, false when the server answered with
unusable data and nothing is shown.

**Preferences.** `initialize()` loads both keys and publishes immutable
`Set<String>` snapshots (mutation throws). A failed load is rethrown rather than
presented as "nothing saved", and is not cached, so a later call retries. Writes
are serialised in call order; the in-memory set changes only after the store
write succeeds, so a storage failure is never shown as a saved job or an armed
reminder, and the caller receives the error. Setters lazily await
`initialize()`, so a write can never drop previously stored ids. Blank ids are
rejected with `ArgumentError`. `dispose()` (not part of the contract interface)
is idempotent.

## Evidence (actual runs, Flutter 3.47.7 / Dart 3.13.5)

```
python3 tool/preflight.py                      -> PASS (structural only)
flutter analyze lib/data test/data             -> No issues found!
flutter test test/data/                        -> 35 tests, All tests passed!
dart format lib/data test/data                 -> 8 files, 0 changed
```

Not run, by policy: full `flutter test`, `flutter analyze` over the whole
repository, `flutter build apk|aab|web`, `gradlew`, any CI dispatch. Android
runtime persistence, notification scheduling and HTTP/disk adapters were not
exercised — none of them exist in this scope.

## Remaining captain integration

1. Implement the three adapters in `lib/app`: HTTP `FeedTransport`, file or
   prefs-backed `FeedCache`, and a `PreferencesStore` adapter.
2. Await `LocalUserPreferences.initialize()` before composing the UI; call
   `repository.refresh()` at startup and on pull-to-refresh.
3. Wire reminder scheduling/cancellation from `reminderJobIds`; permission is
   requested through `AppActions` by B, and preferences only stores intent.
4. Call `dispose()` on both objects when the app scope ends (not part of the
   `JobRepository`/`UserPreferences` interfaces — deliberately concrete).
5. Confirm the feed URL/config and that a failed refresh banner uses
   `lastError`; no further signature changes are needed.

## Five-line report

```
Batch 1: A ready (agent/A/data-v1)
Changed: lib/data/{feed_transport,feed_cache,preferences_store,cached_job_repository,local_user_preferences}.dart — validated cache-first repository with single-flight refresh and truthful preferences; test/data/** covers refresh, corruption, races, persistence
Evidence: preflight PASS; flutter analyze lib/data test/data — no issues; flutter test test/data/ — 35 passed; Android/HTTP/disk adapters not run (out of scope)
Not touched: pubspec.yaml/lock, workflows, AGENTS.md, android/**, ios/**, lib/main.dart, lib/app/**, lib/contracts/**, lib/design_system/**, lib/features/**, tool/**, test/contracts/**, test/fixtures/**, root docs/assets, main
Next: captain supplies HTTP/FeedCache/PreferencesStore adapters, awaits initialize(), schedules reminders and reviews the branch diff
```
