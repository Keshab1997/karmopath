# Agent A — Batch 7 reminder reconciliation

> **HISTORICAL PROPOSAL — DO NOT START THIS TASK.** The delivered two-worker A/B handoff and Captain foundation are tracked in `docs/BATCH_7.md` and `docs/reports/CAPTAIN_BATCH_7.md`. This alternative three-worker plan is retained for audit only. Existing work must be preserved; future work needs a fresh Captain brief.

One task, one branch, then stop. Read origin/main's AGENTS.md,
[common dispatch](../DISPATCH_BATCH_7.md), [frozen contract](../BATCH_7_CONTRACTS.md)
and this brief before branching. Reuse your own sandbox/session; do not restart
completed Batch 6 work. Common setup includes auth/SDK and stop rules.

**Repository:** https://github.com/Keshab1997/karmopath.git
**Base:** `bffcfb473d14f66bf47b85be96558497cc387dc4`
**Branch:** `agent/A/reminder-reconcile-v1`

```sh
cd /home/user/karmopath
git switch --create agent/A/reminder-reconcile-v1 bffcfb473d14f66bf47b85be96558497cc387dc4
```

**ONLY writes:** `lib/data/reminders/reminder_synchronizer.dart`,
`test/data/reminders/reminder_synchronizer_test.dart`, `docs/reports/A7.md`.
All existing planner/diff/ledger/applier code is read-only. No lib/app, contracts,
dependencies/lock, Android/iOS, main, workflows, generated files, root docs/assets,
other workers' namespaces, admin/feed, versions, settings or secret changes.

## Goal / interface

Implement `DefaultReminderSynchronizer({required PreferencesStore store,
required NativeNotifications notifications, required DateTime Function() nowUtc})`
implementing `ReminderSynchronizer` in the exact output file above. Use the frozen
ports and copy/variant literals. Existing `reminder_plan.dart`,
`reminder_state_store.dart`, `reminder_apply.dart` and their tests are the base,
not a request to rewrite them. No B/C imports, plugins, real network or UI.

Reconcile backend-reported pending entries against the durable ledger before
calling the existing applier. Handle missing/mismatched/reservation-only records,
managed orphans, explicit deselection, permission denial and language variants.
Full identity match, stable monotonic IDs, cancel-before-replace, confirmed effects
before ledger writes, honest partial failures, fresh-clock future-only scheduling.
Null feed is unavailable, not empty. Unknown namespaces/foreign IDs are never
cancelled/overwritten. Counter inconsistency/corruption fails closed; never erase
OS evidence that would permit an ID to be reused on retry. Never prompt or change
intent preferences. Serialize requests; close drains without cancelling schedules.

## Acceptance tests (deterministic injected clock/storage/platform)

Cover matched unchanged records/no redundant writes; missing pending; wrong
identity; reservation-only crash window; stale managed orphan; unknown namespace;
foreign reservation AND prospective-allocation collision; orphan ID >= counter
remains evidence on repeated retries; corrupt/read-failing ledger; pending/permission
query failure; denied versus unavailable; null feed versus verified empty feed;
explicit deselection with no feed; failed cancel/schedule/ledger write and retry;
independent-job partial failure; bn/en reapply; elapsed due while queued;
concurrency, idempotent repeated sync, exhausted IDs, drain/closed behavior.
Fakes belong in tests. No delivery claim from registry reconciliation.

## Check / handoff

With the verified SDK PATH/PUB_CACHE from common setup:
```sh
python3 tool/preflight.py && flutter test test/data/reminders --reporter expanded
```
Do not run full tests/analyze/build/CI. Missing SDK = NOT RUN/blocked.
Stage only implementation/tests, then **read the actual staged diff**:
```sh
set -e
test "$(git branch --show-current)" = 'agent/A/reminder-reconcile-v1'
git add -- 'lib/data/reminders/reminder_synchronizer.dart' 'test/data/reminders/reminder_synchronizer_test.dart'
git diff --cached --check
git diff --cached
```
After ownership/secret review, commit with `feat(reminders): reconcile native pending reminders safely`. Record that
real code SHA in the five-line `docs/reports/A7.md` (AGENTS.md format), then
stage/review that report separately:
```sh
git add -- 'docs/reports/A7.md'
git diff --cached --check
git diff --cached
```
After report review:
```sh
set -e
test "$(git branch --show-current)" = 'agent/A/reminder-reconcile-v1'
git commit -m "docs(batch7): record A verification"
git push -u origin agent/A/reminder-reconcile-v1
git rev-parse HEAD
git ls-remote --heads origin agent/A/reminder-reconcile-v1
```
Final chat: same five-line report with the actual pushed SHA/branch. No main
push/merge, force push, release, publication or CI. Shared-interface blocker?
Report it to Captain; do not expand ownership or ask for credentials.
