# Historical delivered two-worker Batch 7 brief — A

> COMPLETED HANDOFF / DO NOT EXECUTE. This is the original instruction snapshot for provenance, not a current assignment. Its local-only/publication hold was later superseded by Keshab's explicit main-push approval. See ../../BATCH_7.md and ../../reports/CAPTAIN_BATCH_7.md for current state. Preserve existing work; do not start this branch again.

---

# You are agent A. Batch 7 — LOCAL ONLY; no public push approval.

Use your own existing workspace when available; keep its saved GitHub login.
Do the task below on your local worker branch, run the targeted gate, commit locally and STOP. Keshab explicitly withheld public-push approval. Never push any branch, open a PR/issue, upload code elsewhere or publish a workaround. Captain must convey new explicit owner approval before a later branch push. Do not ask Keshab task questions; report ambiguity/blockers to Captain. Browser pairing approval is needed only if your own login cannot be restored.

## 0. GitHub access — check first, pair only if asked to

```bash
DST=/home/user/agent-bootstrap
[ -f "$DST/gh_app.py" ] || git clone https://github.com/Keshab1997/agent-bootstrap "$DST"
python3 "$DST/gh_app.py" connect     # if it says ALREADY CONNECTED: nothing to do
```

connect tries saved access/refresh first. A transient error means retry, not a
new approval. Only if it prints a code, show *"Open https://github.com/login/device
and enter XXXX-XXXX"* and wait for approval. Never ask for a token. If the turn
ends, use `python3 "$DST/device_pair.py" poll 60` — connect already saved the same
code. No `start` step and no new code while this one is valid.

## 1. Your task

**Batch 7 approved split:** existing ownership unchanged; captain retains all shared surfaces. Read `AGENTS.md`, `docs/BATCH_7.md` and existing reminder modules before editing. This brief supersedes only the historical Batch 7 no-worker sentence; it grants NO protected-path exception.

**Frozen implementation base:** `80adedcae21629c5c6928f30f7852f6640539ec4`. Later captain dispatch-only commits are intentionally not required in your branch. This standalone brief supersedes the historical no-worker sentence in the frozen base. The updated dispatch/briefs are LOCAL to Captain and have NOT been pushed; do not expect to fetch them from GitHub. Do not continue, merge or cherry-pick an earlier batch branch. If a same-named branch exists, inspect its actual diff before resuming; unrelated/unpushed work is not yours to discard.

**Goal (one sentence, testable):** Reconcile the existing durable reminder ledger against an injected OS-pending-ID query without importing a notification plugin, preserving stable IDs, crash recovery and the existing applier queue.

**Repository:** `Keshab1997/karmopath`  ·  **Branch:** `agent/A/b7-os-reconcile-20261018`  (branch only — never `main`)

```bash
cd /home/user
[ -d karmopath ] || GIT_TERMINAL_PROMPT=0 git -c credential.helper='!f(){ echo username=x-access-token; echo "password=$(cat /home/user/agent-bootstrap/secrets/gh_token.txt)"; }; f' clone https://github.com/Keshab1997/karmopath.git /home/user/karmopath
cd /home/user/karmopath
git config core.fileMode false
git config user.name "Keshab Sarkar"
git config user.email "Keshab1997@users.noreply.github.com"
git config credential.helper '!f(){ echo username=x-access-token; echo "password=$(cat /home/user/agent-bootstrap/secrets/gh_token.txt)"; }; f'
git fetch origin
BASE=80adedcae21629c5c6928f30f7852f6640539ec4
BRANCH=agent/A/b7-os-reconcile-20261018
[ -z "$(git status --porcelain)" ] || { echo "STOP: preserve existing local changes"; exit 1; }
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git checkout "$BRANCH"             # inspect and resume only this same task
elif git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  git checkout --track -b "$BRANCH" "origin/$BRANCH"
else
  git checkout -b "$BRANCH" "$BASE"
fi
git merge-base --is-ancestor "$BASE" HEAD || { echo "STOP: wrong task/base"; exit 1; }
git log --oneline "$BASE"..HEAD
```

If the branch already exists, inspect and resume it instead of resetting it.
Never discard uncommitted or unpushed work. Use the saved session in this worker
workspace; do not copy another agent's credentials. Fresh workspaces may still
need first approval. Captain cannot fetch an unpushed local commit: integration is intentionally waiting for separate public-push approval. No file transfer or alternate publication is authorized.

**Files you own (only these):**

- `lib/data/reminders/reminder_apply.dart`
- `test/data/reminders/reminder_reconcile_test.dart` (new)
- `docs/reports/A7.md` (new; actual behavior/gates/limits, not fabricated evidence)

**DO NOT TOUCH** (they belong to the captain or to another worker):

- `pubspec.yaml`, `pubspec.lock`, any version bump, any dependency addition
- `.github/workflows/**`, anything under `android/` and `ios/`
- `AGENTS.md` managed block, `tool/**`, `secrets/**`
- any file another worker owns in this batch — assumed, not negotiable
- `lib/main.dart`, `lib/app/**`, `lib/contracts/**`, `lib/design_system/**`
- `test/app/**`, `test/contracts/**`, `test/fixtures/**`, shared test helpers
- generated files (`*.g.dart` included), `assets/**`, root/captain docs, all other reports
- ALL files not in your exact allowed list, even if `AGENTS.md` gives your role a broader area
- **`main` itself. You never push, merge or rebase `main`.**

**Interface (exact names/strings the captain froze — use these verbatim):**

Add this public method to the existing `ReminderApplier`, with these exact names:

```dart
Future<ReminderApplyResult> reconcile(
  ReminderPlan desiredPlan,
  ReminderPlatform platform,
  String payloadVariant, {
  required Future<Set<int>> Function() readPendingPlatformIds,
});
```

Do not change the signatures/behavior of `ReminderPlatform`, `apply`, `applyDiff`, public result types or the state schema/key. `payloadVariant` is opaque: captain supplies it; never import feature-layer code.

Required behavior:
- Share the existing applier queue with `apply`/`applyDiff`. Query/copy the pending-ID set inside that queue, after earlier operations settle. Never call an enqueued public apply from inside the queue and deadlock it; reuse/factor private implementation instead.
- Validate blank variant/duplicate desired jobs and load the ledger before effects. A failed pending query is an error to the caller, NOT an empty list. Query/load/validation failure causes no platform cancel/schedule and no ledger writes; the next queued call can still run.
- Matching desired entry + matching applied metadata/variant + ID present in OS: no-op, no writes.
- Desired applied entry missing from OS: repair under the SAME reservation/ID, with idempotent cancel-before-schedule. Never record success just because the ledger previously said applied.
- Changed content/deadline/variant: normal same-ID replacement. Removed/ineligible desired work: cancel the known applied ID, even if the OS list is already missing it, then clear applied metadata only after success.
- Crash-window case: a registry reservation has `applied == null` but its ID IS pending. Cancel that known ID before any new scheduling for the job; if undesired, cancel it without scheduling. Do not synthesize fake applied metadata just to enable cancellation. Successful cancellation of a reservation-only orphan is included in `cancelledJobIds`; the store's record call can legitimately be a no-op.
- A bare reservation with no OS pending ID and no desired entry is untouched. IDs absent from the durable registry are untouched, even if present in OS. Never `cancelAll`, guess a job from an ID, reallocate an existing reservation or recycle IDs.
- ALL cancellations, including crash-window orphans, precede ALL schedules. Keep deterministic existing ordering. Failed cancel OR failed cancellation-record write blocks same-job scheduling in this call, not unrelated jobs. Platform/storage failures remain per-job `ReminderApplyFailure`s; only real operation+record successes enter result success lists. Preserve the unavoidable OS/ledger crash window honestly.
- Reuse the existing store methods; no new key/schema, permissions, network, plugin, filesystem I/O, real clock, catch-up alert or intent mutation. Desired eligibility is the planner/captain's concern.

Write focused deterministic tests in the ONE new test file: matching no-op/write count; OS-missing repair/stable ID; applied-but-removed cancellation; reservation-only orphan present/desired and present/undesired; unregistered OS IDs untouched; stale variant and changed entry; query failure with no writes/effects + recovery; cancel/platform-record failures preventing unsafe replacement; schedule-record failure + later recovery; global cancel-before-schedule ordering; concurrent reconcile/apply serialization including query timing. Use existing `test/data/fakes.dart` read-only or local fakes; don't edit shared fixtures/tests. Preserve all pre-existing apply semantics; captain runs the older regression file.

This helper is NOT a concrete plugin or proof of reboot/delivery. Captain owns permissions, plugin pending queries, boot wiring and event triggers.

## 2. Your one check — then LOCAL commit and STOP

Use your existing compatible Flutter SDK; never change `pubspec` constraints to fit an old SDK. The previous captain reported Flutter 3.47.7 / Dart 3.13.5 (historical, not verified in this dispatch). If Flutter is missing, bootstrap it using the companion installer, then rerun only the check below:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Keshab1997/flutter-bootstrap/main/setup.sh) --quiet --json
```

A failed/unavailable SDK is NOT RUN/BLOCKED, not PASS; preserve your work and report it without inventing evidence. No owner keys, payment or copied credentials are needed for an SDK.

Write your allowed A7/B7 report with the actual behavior, gate outcome and limits before staging. No self-referential final commit SHA is needed inside that report file.

Run exactly this, and only this:

```bash
python3 tool/preflight.py && flutter test test/data/reminders/reminder_reconcile_test.dart
```

If it fails: fix **your** change until it passes. Never run the full test
battery, `flutter analyze`, `flutter build`, `gradlew`, or CI — those are the
captain's call, and waiting on them is the one thing this setup is designed to
avoid.

Stage only your allowed files and review the staged diff, then commit LOCALLY (NO PUSH):

```bash
git add -- 'lib/data/reminders/reminder_apply.dart' 'test/data/reminders/reminder_reconcile_test.dart' 'docs/reports/A7.md'
git diff --cached --check
git diff --cached
git commit -m "feat(reminders): reconcile ledger with pending platform notifications"
# STOP HERE. No public branch push is authorized.
```

Commit message style: `type(scope): what changed` — `fix(home): …`,
`feat(settings): …`, `docs: …`. One concern per commit. If your work needs a
second commit, make it; do not squash history you do not own.

## 3. Report — exactly five lines, as required by AGENTS.md

```text
Batch 7: A LOCAL READY (<final sha7>) / blocked — <reason>; NOT PUSHED; branch agent/A/b7-os-reconcile-20261018
Changed: <owned paths and one-sentence outcome>
Evidence: python3 tool/preflight.py && flutter test test/data/reminders/reminder_reconcile_test.dart -> <actual result/count or NOT RUN>
Not touched: <protected/shared surfaces, other workers, production activation>
Next: await explicit owner approval before public push; Captain cannot fetch this local commit yet
```

Only local work and this short status report are authorized for now. The normal branch-push handoff and Captain's diff review/integration resume only after separate owner approval. Never claim the code is remotely available or integration is complete.

## 4. Stop rules

NO PUBLIC PUSH or alternate upload. No workflow dispatch, builds/Gradle, tags/releases, deployment/feed publication, paid service, secrets/settings changes or branch deletion. Native production activation remains owner-gated.

Stop and report (do **not** improvise) when: the task needs a file you do not
own, the change grows past the goal above, the interface seems wrong, the check
fails for a reason that is not your change, or you would need a decision from
Keshab. A stopped worker with a clear report is useful; a wandering worker
pushing a surprise diff is not.
