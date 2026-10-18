# Batch 7 — parallel dispatch (A/B/C)

> **HISTORICAL PROPOSAL — DO NOT START THIS TASK.** The delivered two-worker A/B handoff and Captain foundation are tracked in `docs/BATCH_7.md` and `docs/reports/CAPTAIN_BATCH_7.md`. This alternative three-worker plan is retained for audit only. Existing work must be preserved; future work needs a fresh Captain brief.

**Status: dispatch ready; workers have NOT been started by Captain.** The owner
starts up to three independent worker chats using [these starters](START_BATCH_7_BN.md).
This replaces the old captain-only Batch 7 assignment. Batch 6 is already
integrated; do not repeat historical work.

Repository: https://github.com/Keshab1997/karmopath.git

**Immutable code base for ALL workers:**
`bffcfb473d14f66bf47b85be96558497cc387dc4`

The following main commit adds only dispatch documentation. Read the current
AGENTS.md, this dispatch and your brief from origin/main **before** checking out
the code base. After checkout, retrieve the brief using `git show
origin/main:docs/briefs/AGENT_A_BATCH_7.md` (B/C use their corresponding filename).
Do not merge main just to obtain the newer brief. The frozen source/API/spec,
lockfile and platform prerequisites already exist at the code-base SHA.

| Worker | One output | Branch | Exclusive writes |
|---|---|---|---|
| A | Pure reconciliation coordinator | `agent/A/reminder-reconcile-v1` | `lib/data/reminders/reminder_synchronizer.dart`, `test/data/reminders/reminder_synchronizer_test.dart`, `docs/reports/A7.md` |
| B | Android notification adapter | `agent/B/android-reminders-v1` | `lib/platform/notifications/**`, `test/platform/notifications/**`, `docs/reports/B7.md` |
| C | Injectable native runtime factory | `agent/C/native-runtime-v1` | `lib/native/runtime/**`, `test/native/runtime/**`, `docs/reports/C7.md` |

[Brief A](briefs/AGENT_A_BATCH_7.md) · [Brief B](briefs/AGENT_B_BATCH_7.md) ·
[Brief C](briefs/AGENT_C_BATCH_7.md) · [Frozen contract](BATCH_7_CONTRACTS.md)

These are explicit Batch 7 exceptions to historical B=features/C=admin ownership.
All other files are read-only. A cannot modify the existing planner/ledger/applier.
No worker imports the other workers' new implementations; implement against
`lib/contracts/native_reminders.dart` and test-only fakes. No waiting for each other.

Captain retains contracts, dependencies/lockfiles, android/ios, lib/app/**,
lib/main.dart, root docs/assets, workflows, generated files, routing, versions
and final composition. User-approved feed URL is still missing; workers must not
activate main, invent a URL, publish content or claim native delivery is proven.

## Common setup — each worker's OWN sandbox/login

These instructions assume independent sandboxes under `/home/user`, not /tmp.
Reuse that worker's existing workspace and saved session. If a sandbox is shared,
stop for separate GH_SECRET_DIR and matching credential-helper setup; never use
Captain's or another worker's credential files.

Reuse/update the bootstrap **code**, not credentials. The required refresh/resume
fix exists in `ff8f79b7e0bcd2517ff0fd34deb3d498ba972ea5`:

```sh
set -e
cd /home/user
[ -f /home/user/agent-bootstrap/gh_app.py ] || git clone https://github.com/Keshab1997/agent-bootstrap.git /home/user/agent-bootstrap
# If the existing helper checkout is dirty, stop; do not reset/stash/delete it.
git -C /home/user/agent-bootstrap status --short
test -z "$(git -C /home/user/agent-bootstrap status --porcelain)" || { echo 'STOP: helper has local work'; exit 1; }
git -C /home/user/agent-bootstrap fetch origin main
git -C /home/user/agent-bootstrap merge --ff-only ff8f79b7e0bcd2517ff0fd34deb3d498ba972ea5
python3 /home/user/agent-bootstrap/gh_app.py connect --show-only
```

If ALREADY CONNECTED, ask nothing and stop auth work. A transient connection error
is not a reason to re-pair. Only if a device code is actually printed, show that
code and https://github.com/login/device; no token/password/TOTP request. Resume
interrupted approval with `python3 /home/user/agent-bootstrap/device_pair.py poll 60`
(or connect again, which resumes). No force rotation and no code sharing.

The helper's standalone-agent prompt says direct-main; **that rule does not apply
to these workers**. Karmopath's captain/worker map and named branches govern.
Only the helper's local code may be fast-forwarded above; never push that helper
repo or merge/rebase/push Karmopath main.

```sh
set -e
cd /home/user
[ -d /home/user/karmopath ] || git clone https://github.com/Keshab1997/karmopath.git /home/user/karmopath
cd /home/user/karmopath
git config core.fileMode false
git config user.name "Keshab Sarkar"
git config user.email "Keshab1997@users.noreply.github.com"
git config credential.helper '!f(){ echo username=x-access-token; echo "password=$(cat /home/user/agent-bootstrap/secrets/gh_token.txt)"; }; f'
git fetch origin
git status --short
git show origin/main:AGENTS.md
```

Require a clean project worktree before the brief's `git switch --create` command.
Never discard existing work. If the assigned branch already exists, inspect it
and resume only if it descends from the frozen base and is your Batch 7 work;
otherwise stop/report. No force-push, reset-hard, old worker cherry-picks or
main merge/rebase. If .git/config was not persisted, restore only the correct
public origin/identity/own helper; do not re-clone over an existing checkout.

## SDK / packages

Use Flutter **3.47.7 / Dart 3.13.5**. If already available, verify its version and
reuse it. Otherwise the reviewed bootstrap commit is
`77083c95d1aab65bdee1bc4d569e00bf1223af99`; use a version-specific transient SDK root:

```sh
set -e
cd /home/user
[ -d /home/user/flutter-bootstrap ] || git clone https://github.com/Keshab1997/flutter-bootstrap.git /home/user/flutter-bootstrap
git -C /home/user/flutter-bootstrap fetch origin main
mkdir -p /home/user/.staging
git -C /home/user/flutter-bootstrap show 77083c95d1aab65bdee1bc4d569e00bf1223af99:setup.sh > /home/user/.staging/karmopath-flutter-setup.sh
# Read the saved script, then run it; checksum verification is built in.
bash /home/user/.staging/karmopath-flutter-setup.sh --version 3.47.7 --root /var/tmp/karmopath-flutter-3.47.7 --no-swap --quiet --json
export PATH=/var/tmp/karmopath-flutter-3.47.7/bin:$PATH PUB_CACHE=/var/tmp/pub-cache
flutter --version
cd /home/user/karmopath
flutter pub get --enforce-lockfile
```

Repeat PATH/PUB_CACHE setup in later shell calls, using the verified SDK root.
Do not upgrade, regenerate native folders, add dependencies or commit generated
files. If the SDK truly cannot run, report NOT RUN and blocked, never PASS.

## One focused gate per worker, then branch push

Each brief supplies one combined preflight + focused-test command. Do not run
full tests/analyze/build/gradlew/CI as a shortcut. Existing pure reminder tests
are included in A's gate because reconciliation reuses that subsystem; B/C test
only their new isolated namespaces. Tests must exercise failures, not stub success.

Commit the checked implementation first, then write the assigned report with
**exactly five lines** using AGENTS.md and that real code commit's SHA. Commit
that report separately: a file cannot honestly contain its own future commit ID.
The final five-line chat report uses the FINAL pushed HEAD/branch, actual test
results and limitations. Never guess a SHA. Review `git diff --name-only bffcfb473d14f66bf47b85be96558497cc387dc4...HEAD`
and the actual diff for ownership/secrets. Stage only the paths in your brief;
never `git add .` / `-A`. Push only your named branch; verify remote SHA with
`git ls-remote --heads origin` for that branch. Do not delete branches.

If an interface is insufficient, a shared fix is required, tests fail outside
your changes or the task exceeds its scope, stop and report blocked to Captain.
No speculative API change, unrelated refactor, invented evidence or extra worker.

## Captain follow-through (not worker work)

Fetch and read each complete diff; check scope/secrets/tests. Review B, A, C one
stream at a time, integrate without cross-worker dependencies, then add captain
composition/lifecycle/tap/status wiring and focused integration regressions.
Run broader gates only when justified by those shared changes; no local build or
CI dispatch. Leave main's native activation gated by an owner-approved public
HTTPS feed and real-device checks. Mocked platform tests do not prove Android
permission UI, reboot restoration, OEM reliability or visible delivery.

Foundation evidence: [CAPTAIN_BATCH_7_DISPATCH.md](reports/CAPTAIN_BATCH_7_DISPATCH.md).
