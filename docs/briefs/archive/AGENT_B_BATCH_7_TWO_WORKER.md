# Historical delivered two-worker Batch 7 brief — B

> COMPLETED HANDOFF / DO NOT EXECUTE. This is the original instruction snapshot for provenance, not a current assignment. Its local-only/publication hold was later superseded by Keshab's explicit main-push approval. See ../../BATCH_7.md and ../../reports/CAPTAIN_BATCH_7.md for current state. Preserve existing work; do not start this branch again.

---

# You are agent B. Batch 7 — LOCAL ONLY; no public push approval.

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

**Goal (one sentence, testable):** Provide pure, deterministic Bengali/English reminder-notification content and stable language/copy variants for captain-owned native scheduling, without changing any screen or platform behavior.

**Repository:** `Keshab1997/karmopath`  ·  **Branch:** `agent/B/b7-notification-copy-20261018`  (branch only — never `main`)

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
BRANCH=agent/B/b7-notification-copy-20261018
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

- `lib/features/common/reminder_notification_content.dart` (new)
- `lib/features/common/strings.dart` (add only the required copy; no unrelated reformat)
- `test/features/reminder_notification_content_test.dart` (new)
- `docs/reports/B7.md` (new; actual behavior/gates/limits, not fabricated evidence)

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

Create `lib/features/common/reminder_notification_content.dart` with exactly this API:

```dart
class ReminderNotificationContent {
  const ReminderNotificationContent({
    required this.title,
    required this.body,
    required this.payload,
    required this.payloadVariant,
  });
  final String title;
  final String body;
  final String payload;
  final String payloadVariant;
}

String reminderNotificationVariant(AppLang language);

ReminderNotificationContent buildReminderNotificationContent({
  required Job job,
  required AppLang language,
});
```

Import existing `Job`, `AppLang` and `K`/`KText`; do not invent a competing language or job model.

Freeze these values/semantics:
- `reminderNotificationVariant(AppLang.bn)` is exactly `bn@reminder-v1`; English is exactly `en@reminder-v1`. The DTO uses that same helper; no hashes, dates, job IDs or randomness in the variant.
- `title` is `job.titleBn` for Bengali and `job.titleEn` for English, VERBATIM. Do not truncate, normalize or mutate feed titles; contract-validated jobs already provide both.
- Add exactly `K.reminderNotificationBody = KText('আবেদনের শেষ সময় ও মূল বিজ্ঞপ্তি দেখে নিন।', 'Check the application deadline and the original notice.');` in `strings.dart`; `body` is this copy in the requested language.
- `payload` is the FULL `job.id` verbatim, not a URL, generated number, shortened ID or invented route. Captain handles notification taps later.
- Pure synchronous content building only. No clock or date formatting: don't display an invented midnight for inclusive date-only deadlines, assert a 24-hour countdown, promise scheduled/delivered/missed alerts or imply government affiliation.
- No eligibility/permission/storage/scheduling decisions, listeners, global language mutation, data-layer import, plugin, new dependency or network. No changes to settings screens, reminder_controller or existing intent subtitles.

Focused tests in the ONE new test file: exact title/body/payload/variant in both languages; variant helper/DTO agreement; Bengali punctuation and full long valid job ID preserved; repeat calls deterministic and input unchanged; selecting explicit language does not depend on/mutate global `appLanguage`; no invented time/countdown or scheduling/delivery-success copy. Existing feature fakes can be imported read-only; do not change shared fixtures or older tests.

A independently implements data reconciliation and does not import your helper. Captain listens for language/copy changes, passes your variant to the applier, and invokes this builder from the concrete notification adapter. Do NOT implement those captain-owned triggers or plugin wiring.

## 2. Your one check — then LOCAL commit and STOP

Use your existing compatible Flutter SDK; never change `pubspec` constraints to fit an old SDK. The previous captain reported Flutter 3.47.7 / Dart 3.13.5 (historical, not verified in this dispatch). If Flutter is missing, bootstrap it using the companion installer, then rerun only the check below:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Keshab1997/flutter-bootstrap/main/setup.sh) --quiet --json
```

A failed/unavailable SDK is NOT RUN/BLOCKED, not PASS; preserve your work and report it without inventing evidence. No owner keys, payment or copied credentials are needed for an SDK.

Write your allowed A7/B7 report with the actual behavior, gate outcome and limits before staging. No self-referential final commit SHA is needed inside that report file.

Run exactly this, and only this:

```bash
python3 tool/preflight.py && flutter test test/features/reminder_notification_content_test.dart
```

If it fails: fix **your** change until it passes. Never run the full test
battery, `flutter analyze`, `flutter build`, `gradlew`, or CI — those are the
captain's call, and waiting on them is the one thing this setup is designed to
avoid.

Stage only your allowed files and review the staged diff, then commit LOCALLY (NO PUSH):

```bash
git add -- 'lib/features/common/reminder_notification_content.dart' 'lib/features/common/strings.dart' 'test/features/reminder_notification_content_test.dart' 'docs/reports/B7.md'
git diff --cached --check
git diff --cached
git commit -m "feat(reminders): add bilingual native notification content helper"
# STOP HERE. No public branch push is authorized.
```

Commit message style: `type(scope): what changed` — `fix(home): …`,
`feat(settings): …`, `docs: …`. One concern per commit. If your work needs a
second commit, make it; do not squash history you do not own.

## 3. Report — exactly five lines, as required by AGENTS.md

```text
Batch 7: B LOCAL READY (<final sha7>) / blocked — <reason>; NOT PUSHED; branch agent/B/b7-notification-copy-20261018
Changed: <owned paths and one-sentence outcome>
Evidence: python3 tool/preflight.py && flutter test test/features/reminder_notification_content_test.dart -> <actual result/count or NOT RUN>
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
