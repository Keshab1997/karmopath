# Agent B — Batch 7 Android notification adapter

> **HISTORICAL PROPOSAL — DO NOT START THIS TASK.** The delivered two-worker A/B handoff and Captain foundation are tracked in `docs/BATCH_7.md` and `docs/reports/CAPTAIN_BATCH_7.md`. This alternative three-worker plan is retained for audit only. Existing work must be preserved; future work needs a fresh Captain brief.

One task, one branch, then stop. Read origin/main's AGENTS.md,
[common dispatch](../DISPATCH_BATCH_7.md), [frozen contract](../BATCH_7_CONTRACTS.md)
and this brief before branching. This explicit Batch 7 assignment replaces your
historical features-only scope. Reuse your own sandbox/login; no repeated Batch 6 UI work.

**Repository:** https://github.com/Keshab1997/karmopath.git
**Base:** `bffcfb473d14f66bf47b85be96558497cc387dc4`
**Branch:** `agent/B/android-reminders-v1`

```sh
cd /home/user/karmopath
git switch --create agent/B/android-reminders-v1 bffcfb473d14f66bf47b85be96558497cc387dc4
```

**ONLY writes:** `lib/platform/notifications/**`, `test/platform/notifications/**`,
`docs/reports/B7.md`. All features/data/admin code is read-only. No lib/app,
contracts, dependencies/lock, Android/iOS, main, workflows, generated files,
root docs/assets, versions, other workers' files, settings or secret changes.
Captain already owns/supplies the Android prerequisites, icon/keep rule and pins.

## Goal / interface

Export `AndroidNativeNotifications({DateTime Function()? nowUtc}) implements
NativeNotifications` from
`lib/platform/notifications/android_native_notifications.dart`. Exact port,
namespace/payload/copy/channel policy is in the frozen contract. Default is the
REAL pinned flutter_local_notifications backend; optional test seams remain in
your namespace. No imports from A/C, no ledger/planner/UI work.

Initialize without prompting; retry failure safely. Create the channel, preserve
user channel settings, report denied/unknown/unsupported honestly. Request
permission only via the explicit method, serialize requests, then query actual
status. Use v22.3.2 named APIs; UTC one-shot inexactAllowWhileIdle only. Check
permission and fresh future due before schedule, reject invalid IDs/copy, preserve
plugin failures. Never request exact-alarm/full-screen/DND access or cancelAll.

Implement strict canonical payload encode/decode. Return ALL backend pending IDs,
including foreign/malformed entries; never turn a failed query into an empty list.
Only exact known namespace is managed; unknown/future versions are not ours to
cancel. Forward validated job IDs for foreground and cold-start taps, never URLs;
detach callbacks on dispose without cancelling schedules. Unsupported platforms
must not call Android APIs or report fake success. Plugin pending metadata is
NOT independent proof of AlarmManager state or delivery.

## Acceptance tests

Use injected platform/channel fakes plus a test of the default adapter's real
plugin method-channel mapping. Cover no-prompt initialize/passive queries;
Android enabled/denied/null/channel-disabled and unsupported; serialized explicit
permission request; initialize failure/retry; exact payload round-trip and
malformed/foreign/future namespace; all pending IDs preserved and query failure;
schedule ID/time/copy/payload/UTC/inexact flags; no schedule for past/equal due or
ungranted permission; cancellation error propagation; cold-start/foreground tap
validation; callbacks ignored after dispose; disposal leaves schedules intact.
Do not label mocked tests as real-device permission/reboot/delivery evidence.

## Check / handoff

With the verified SDK PATH/PUB_CACHE from common setup:
```sh
python3 tool/preflight.py && flutter test test/platform/notifications --reporter expanded
```
No full tests/analyze/build/gradlew/CI. Missing SDK = NOT RUN/blocked.
Stage only implementation/tests, then **read the actual staged diff**:
```sh
set -e
test "$(git branch --show-current)" = 'agent/B/android-reminders-v1'
git add -- 'lib/platform/notifications' 'test/platform/notifications'
git diff --cached --check
git diff --cached
```
After ownership/secret review, commit with `feat(notifications): add Android reminder platform adapter`. Record that
real code SHA in the five-line `docs/reports/B7.md` (AGENTS.md format), then
stage/review that report separately:
```sh
git add -- 'docs/reports/B7.md'
git diff --cached --check
git diff --cached
```
After report review:
```sh
set -e
test "$(git branch --show-current)" = 'agent/B/android-reminders-v1'
git commit -m "docs(batch7): record B verification"
git push -u origin agent/B/android-reminders-v1
git rev-parse HEAD
git ls-remote --heads origin agent/B/android-reminders-v1
```
Final chat: same five-line report with actual pushed SHA/branch. No main push,
force push, release, publication or CI. If a shared/platform prerequisite is
missing, report blocked to Captain; never edit its owned file or invent success.
