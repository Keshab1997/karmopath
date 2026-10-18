# Agent C — Batch 7 native runtime factory

> **HISTORICAL PROPOSAL — DO NOT START THIS TASK.** The delivered two-worker A/B handoff and Captain foundation are tracked in `docs/BATCH_7.md` and `docs/reports/CAPTAIN_BATCH_7.md`. This alternative three-worker plan is retained for audit only. Existing work must be preserved; future work needs a fresh Captain brief.

One task, one branch, then stop. Read origin/main's AGENTS.md,
[common dispatch](../DISPATCH_BATCH_7.md), [frozen contract](../BATCH_7_CONTRACTS.md)
and this brief before branching. This explicit Batch 7 assignment replaces your
historical admin/feed scope. Reuse your own sandbox/login; do not redo old admin work.

**Repository:** https://github.com/Keshab1997/karmopath.git
**Base:** `bffcfb473d14f66bf47b85be96558497cc387dc4`
**Branch:** `agent/C/native-runtime-v1`

```sh
cd /home/user/karmopath
git switch --create agent/C/native-runtime-v1 bffcfb473d14f66bf47b85be96558497cc387dc4
```

**ONLY writes:** `lib/native/runtime/**`, `test/native/runtime/**`,
`docs/reports/C7.md`. Existing data/features/admin code is read-only. No lib/app,
contracts, dependencies/lock, Android/iOS, main, workflows, generated files,
root docs/assets, versions, other workers' files, settings or secret changes.

## Goal / exact exports

Implement `lib/native/runtime/native_runtime_factory.dart` with the frozen
`createNativeRuntime`, `ReminderSynchronizerFactory`, `NativeResourcesFactory`,
`NativeRuntimeResources`, `NativeRuntimeSession`, `NativeReminderRuntimeState`,
`NativeReminderPhase` signatures/fields. Read that API section fully; do not invent
alternative entrypoints. Inject NativeNotifications + synchronizer factory—no A/B
implementation imports. Default resources really use existing http/cache/preferences
adapters and url_launcher, with test-only injected alternatives.

Initialize preferences/language safely before returning AppRuntime; missing
language defaults bn, bad/read-failing value is not overwritten. ProductionShell
already owns initial refresh: no duplicate fetch or global lifecycle observer.
Expose onResume, held notification job ID and observable sync state for Captain.
Sync on startup/resume, feed/intent changes and successful persisted-language
changes using fresh snapshots, including null feed. All async failures remain
observable/handled. Denied is permissionRequired; unavailable/unsupported/failures
must not masquerade as ready/granted. No delivered/missed status invention.

AppActions requests notification permission only for user action, returns true
only for actual grant and then syncs; external URL validation/failure remains
honest. Default to launchUrl with LaunchMode.externalApplication; do not use
canLaunchUrl as a browser-discovery preflight (no extra manifest query is needed).
Track preference and language writes, remove listeners, drain accepted
work, close synchronizer before gateway and repository before HTTP; attempt ALL
cleanup even if a step throws. runtime.close() and session.close() share one
idempotent cleanup path without recursive calls. No callbacks/writes after disposal.
On factory retry use fresh owned resources/gateway, not disposed instances from
a failed attempt; default partial construction must also close its own client.
No real network in tests and no guessed production feed or main activation.

## Acceptance tests

Fake ports/resources/clock: initialization order; preference/language/gateway/
synchronizer startup failure and fresh retry; partial cleanup and cleanup-step
failure; no duplicate startup fetch; feed/null-feed/reminder/language/resume sync;
serialization and rapid updates; permission true/false/unknown/throw with no passive
prompt; public HTTPS validation and launcher false/throw; queued cold-start and
foreground job IDs/consume; failed sync observed and next sync usable; close during
in-flight sync/preference/language writes; runtime/session double-close; no late
state callbacks; every owned resource attempted even after an earlier close error.
Exercise default resource/launcher wiring with mocked package boundaries too.

## Check / handoff

With the verified SDK PATH/PUB_CACHE from common setup:
```sh
python3 tool/preflight.py && flutter test test/native/runtime --reporter expanded
```
No full tests/analyze/build/gradlew/CI. Missing SDK = NOT RUN/blocked.
Stage only implementation/tests, then **read the actual staged diff**:
```sh
set -e
test "$(git branch --show-current)" = 'agent/C/native-runtime-v1'
git add -- 'lib/native/runtime' 'test/native/runtime'
git diff --cached --check
git diff --cached
```
After ownership/secret review, commit with `feat(runtime): add retryable native runtime composition`. Record that
real code SHA in the five-line `docs/reports/C7.md` (AGENTS.md format), then
stage/review that report separately:
```sh
git add -- 'docs/reports/C7.md'
git diff --cached --check
git diff --cached
```
After report review:
```sh
set -e
test "$(git branch --show-current)" = 'agent/C/native-runtime-v1'
git commit -m "docs(batch7): record C verification"
git push -u origin agent/C/native-runtime-v1
git rev-parse HEAD
git ls-remote --heads origin agent/C/native-runtime-v1
```
Final chat: same five-line report with actual pushed SHA/branch. No main push,
force push, release, publication or CI. Missing shared API? Report blocked to
Captain rather than editing lib/app or adding a stub backend.
