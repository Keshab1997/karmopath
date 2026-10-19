# Agent operating rules

<!-- flutter-builder:agent-pack:start v1.15.0 -->
## Rule #1 — CI is manual; preflight is your check

This repository runs CI **only when the human dispatches it** (Actions → *Flutter
CI* → Run workflow). Nothing runs on a push. So:

- Work lands on `main` **directly** — no feature branch, no pull request.
- Do **not** wait for a run after pushing. Nothing started; waiting only wastes
  time.
- `tool/preflight.py` is your only automatic check. Run it before every push —
  it is seconds, not minutes, and catches the mistakes that would otherwise
  surface in the next manual CI run.
- **Dart edits are checked on purpose, not by reflex.** Most changes have a
  matching test file: run the one that covers your edit
  (`flutter test test/<name>_test.dart`), not the whole suite. `flutter analyze`
  and the full `flutter test` are for diffs that touch a shared surface, for
  work that feels risky, or for when the human asks — repeating the full pair
  after every small edit is the fastest way to make the loop feel like a chore.
  Everything else (Markdown, YAML, scripts, docs) still ships on preflight
  alone. See *Checking Dart for real* below.
- **When CI does run, it is the source of truth** — read its result before
  calling a batch done. But it runs when the human says so, not on your push.

```bash
python3 tool/preflight.py     # before every push: dead code / unused params / unused imports
python3 tool/agent_loop.py -m "fix(scope): what changed"   # preflight + commit + push, one call
```

### What a check costs

| Check | Cost | When it is the right check |
|---|---|---|
| `python3 tool/preflight.py` | ~1 s | every change, before every push |
| `flutter test test/<file>_test.dart` (via flutter-bootstrap) | 40 s once per session, then seconds | the Dart change that file covers |
| `flutter analyze` or the full `flutter test` | ~20 s / 1–3 min | shared surfaces, risky diffs, or when the human asks |
| `python3 tool/see_screen.py` | one CI run | before and after a UI change |
| The human's CI run | the human's attention + a runner | once per finished batch — never per edit |

Pick the cheapest check that actually covers the change. Building the whole app
to answer a question `flutter analyze` can answer is the most common way to turn
a two-minute task into a twenty-minute one.

### Checking Dart for real (flutter-bootstrap)

The sandbox starts without a Flutter SDK, and one installed now is gone next
session. `flutter-bootstrap` installs a working SDK in ~40 seconds, with no
credentials and a sha256-verified download:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Keshab1997/flutter-bootstrap/main/setup.sh) --quiet --json
cd <app-dir> && flutter pub get && flutter analyze && flutter test
```

- When you run a Dart check at all, `flutter analyze` is the floor: it catches
  exactly what preflight cannot, in ~20 seconds. Worth it for a diff that
  reaches a shared surface, or one you cannot clear by reading it.
- A behaviour change with a matching test gets that **one file** run
  (`flutter test test/<name>_test.dart`). The full suite belongs to the human's
  CI run, unless the human asks for it locally.
- CI pins its own Flutter version: a local pass is *indicative*, not final. When
  the two disagree, CI wins — do not "fix" code to satisfy the local version
  without saying so in the commit message.
- Do **not** `flutter build apk` / `flutter build aab` / `flutter build web`
  locally "just to check". That is minutes per run for an artifact only the CI
  workflow needs to produce, and the signing secrets live in CI anyway.
- Re-running that one-liner later in the same session is safe and instant (~0.2 s
  when the SDK is already there).
- Need a GitHub token in this session (to dispatch a run, read logs, push)? The
  companion repo `agent-bootstrap` pairs one with three browser clicks; pushing
  with `git` over HTTPS may already work, in which case skip it.

## The batch loop — many small changes, one push, one CI run

Small edits are cheap; CI runs are not. So batch them instead of running CI per
change:

1. **Edit** the smallest diff that does one thing.
2. **`python3 tool/preflight.py`** — 1 second, no SDK. Fix what it reports.
3. **Commit and push to `main`.** `python3 tool/agent_loop.py -m "…"` does
   preflight, the secret guard, the commit and the push in one call. Repeat for
   each small change; every commit goes straight to `main`.
4. **Do not wait for CI.** Nothing started. Keep working.
5. **When the batch is ready, tell the human** to run CI once (Actions → *Flutter
   CI* → Run workflow). If a run is already in flight, `python3 tool/ci_watch.py`
   prints the conclusion of every workflow plus the interesting lines of the
   failed ones.

Rules of thumb: a CI run per push wastes the most time; push freely, run CI once
per batch. When a red run does arrive, read the log before editing — guessing at
a red build doubles the rounds.

### The same loop as one command

`tool/agent_loop.py` performs preflight, the secret guard, the commit and the
push in a single call:

```bash
python3 tool/agent_loop.py -m "fix(profile): guard a null avatar"
python3 tool/agent_loop.py -m "fix(profile): drop the unused import" --amend
python3 tool/agent_loop.py -m "chore: wip" --no-push     # commit without pushing
python3 tool/agent_loop.py -m "…" --watch                # wait, only if a run is in flight
```

It refuses, before touching the repository, when

- a staged file looks like a credential (`.env`, `*.jks`, `*.keystore`, `*.pem`,
  `key.properties`, `google-services.json`, `secrets/**`, …) — a refusal costs
  one edit, a leaked keystore costs a rotation;
- `preflight.py` reports anything — use `--no-preflight` only when the findings
  are deliberate.

It commits on the current branch (normally `main`) and pushes there; no branch,
no pull request. Exit codes: `0` committed/pushed, `1` the push failed,
`2` refused before changing anything. An `--amend` push uses
`--force-with-lease`, never a bare `--force`.

## Seeing a screen — look, do not guess

You cannot run the app, but you can *see* it. `tool/see_screen.py` asks CI to
build the app for web and photograph the routes you name, waits for the run,
downloads the images and prints their paths. Then open them — with your image
tool, not your imagination:

```bash
python3 tool/see_screen.py --route /settings           # one screen
python3 tool/see_screen.py --route / --route /profile  # several, one build
python3 tool/see_screen.py --route /settings --wait-ms 12000   # slow first frame
```

* **Use it before and after a UI change.** Before: see what the screen looks
  like now. After: see what your change did. A green CI says the code compiles;
  only the picture says the layout is right.
* This is the one thing that does start a run — it dispatches the UI-screenshots
  workflow itself, so use it deliberately, not on every edit.
* The routes are the app's own (`/settings`, `/profile`) — the same names the
  app navigates to. A screen behind a login or several taps cannot be reached
  this way; ask the human for a screenshot of that one instead.
* It is the **web** build: layout, colours and text are faithful; fonts and
  platform widgets differ, and camera/bluetooth/notification plugins render as a
  blank screen. The script says so when the pixels are flat — believe it rather
  than "fixing" the capture.
* `--out` defaults to `.agent-screens/` (git-ignored). The images are throwaway
  artifacts: never commit them, and never use one as a test fixture.
* No token? `gh auth login` once, or pass `--token-file`.

## Four things that cost an hour here (do not do them)

1. **Waiting for CI after a push.** Nothing was queued — see the manual-only
   table below. Waiting is pure loss.
2. **Running a full build to check a Dart edit.** `flutter build apk|aab|web`
   takes minutes and proves nothing `analyze` + `test` did not already prove.
3. **Asking the human for a CI run before preflight is green and the tests you
   chose to run pass.** A red run spends their attention and a runner, and tells
   you what a local check would have.
4. **Guessing at a red build.** Read the failing step's log first (below). A
   guess that misses doubles the rounds, which is the whole cost this file
   exists to avoid.

## What a push costs here

| Situation | What runs |
|---|---|
| Push to a non-Pages branch with app/code/assets/dependency changes | web preview refreshes; CI stays manual |
| Docs/Markdown/release-note/`.github/`-only push | nothing |
| You ask the human to run CI | CI once, for the whole batch |
| `flutter analyze` / `flutter test` (via flutter-bootstrap) | nothing on GitHub — 40 s to install once per session, then seconds to minutes |
| `see_screen.py` | the UI-screenshots workflow, once per call |

If you want a run right now, do **not** retrigger it with an empty commit — use
*Actions → Run workflow* (or ask the human to).

## CI map

| Workflow | Runs when | What it does |
|---|---|---|
| `ci.yml` → shared `flutter-build.yml` | **manual** (`workflow_dispatch`) | `dart format` check → `flutter analyze --fatal-infos` → `flutter test` + coverage |
| `web-preview.yml` | relevant branch push, manual dispatch, branch delete | builds the web app and replaces that branch's `preview/<branch>/` on GitHub Pages |
| `manual-build.yml` | manual dispatch | APK / AAB artifact |
| `publish-release.yml` | manual dispatch | signed build → tag → GitHub Release (+ Play internal if configured) |
| `release.yml` | `v*` tag push | signed AAB artifact for the tag |

The reusable workflows are pinned by tag; bump the pin in one place
(`.github/workflows/*.yml`) and every project picks the change up.

## Reading CI without wasting a turn

```bash
python3 tool/ci_watch.py                       # HEAD commit, waits, prints failures
python3 tool/ci_watch.py --branch main         # newest runs of a branch
python3 tool/ci_watch.py --once                # no waiting: current state only
python3 tool/ci_watch.py --sha <sha>           # a specific commit
python3 tool/ci_watch.py --token-file secrets/gh_token.txt
```

Token order: `--token-file`, then `$GITHUB_TOKEN` / `$GH_TOKEN`, then `gh auth
token`. Never print a token, and never paste one into a log or a commit.

Raw API equivalents, if you need them:

```bash
GET /repos/{owner}/{repo}/actions/runs?head_sha=<sha>     # run list + conclusions
GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs      # failing job and step
GET /repos/{owner}/{repo}/actions/jobs/{job_id}/logs      # plain-text log
```

The log endpoint answers with a **302 to blob storage**; the pre-signed URL
rejects a request that still carries the `Authorization` header
(`InvalidAuthenticationInfo`), so strip it on redirect — `ci_watch.py` does.

## Working rules

- **Small, focused diffs.** One concern per commit; conventional commit
  messages (`fix(profile): …`, `feat(cv): …`, `chore(ci): …`).
- **Push straight to `main`.** No feature branch, no pull request. Batch small
  changes and let the human run CI once at the end.
- **Secrets never enter git:** `google-services.json`, `android/key.properties`,
  `*.jks` / `*.keystore`, `.pem`, tokens. CI receives them from repository
  secrets. Do not add them to the repo to "make CI pass".
- **Respect existing structure:** edit existing files over adding new ones, and
  read the file you are about to change (comments explain *why* the code is the
  way it is — keep that voice).
- **Match the check to the change** — the cost table near the top of this file
  is the map. Cheap checks run every time; CI runs once, at the end.

## Ask the human before

- running CI, when a batch is ready to be checked (they own the run button);
- **tagging a release**, or touching workflows / secrets / repository settings;
- force-pushing over history you do not own, or deleting branches, tags, or
  repository content;
- anything that publishes publicly, spends money, or is irreversible.

## মানুষের জন্য — এই ফাইলটা কী

- **যে যাচাইটা আসলে দরকার, শুধু সেটাই:** ছোট পরিবর্তনে শুধু `preflight.py`
  (~১ সেকেন্ড); Dart বদলালে সংশ্লিষ্ট একটা test ফাইল
  (`flutter test test/<name>_test.dart`) — পুরো `analyze` + `test` শুধু shared
  কিছু বদলালে বা আপনি বললে। প্রতিটা ছোট edit-এর পিছনে পুরো suite চালানো লাগে না।
- **সরাসরি `main`-এ push** — branch নেই, PR নেই। push করলে CI নিজে থেকে চলে না।
- **CI চালানোর বোতাম আপনারই** — একটা batch শেষ হলে একবার চালালেই যথেষ্ট।
- **UI বদলালে ছবি দেখে যাচাই** — `python3 tool/see_screen.py`।
- **agent আগে অনুমতি নেবে** — tag/release, secrets, store metadata, বা যা
  ফিরিয়ে আনা যায় না এমন কিছুর আগে।
- এই ব্লকটা `install-agent-pack.sh` চালালে নিজে থেকেই update হয়; নিচের
  আপনার নিজের notes কখনো মোছা হয় না।

<!-- flutter-builder:agent-pack:end -->

Captain owns main; maximum three workers. Workers use named branches in independent workspaces; only Captain reviews/integrates/pushes main. Workers never merge, tag, release, trigger CI, change repository settings, or copy/expose credentials. Never work in /tmp. Reuse your own valid GitHub pairing. Use branch handoff, never credential/file-transfer workarounds.

## Captain-owned / DO NOT TOUCH
pubspec.yaml, pubspec.lock, .github/workflows/**, AGENTS.md, android/**, ios/**, lib/main.dart, lib/app/**, lib/contracts/**, lib/design_system/**, tool/preflight.py, test/contracts/**, test/fixtures/**, generated files including *.g.dart, version numbers, root docs and assets/**. Workers may read these but must not edit them. No dependency additions. No stub success, fabricated gates, fake production data or committed credentials.

## Batch 7 — reviewed handoff, no active worker assignment
See `docs/BATCH_7.md` and `docs/reports/CAPTAIN_BATCH_7.md` for current implementation/evidence. The delivered handoff used the earlier two-worker + Captain plan, from frozen base `80adedc`:
- A: `agent/A/b7-os-reconcile-20261018` — existing applier reconciliation, its new focused test, A7 report.
- B: `agent/B/b7-notification-copy-20261018` — pure bilingual content helper/copy, its focused test, B7 report.
- Captain: reviewed squashes, native notification/runtime foundation, shared integration, publication after explicit owner approval.

The later proposed three-worker dispatch and its alternative A/B/C namespaces remain archived design material, NOT new executable assignments. Its shared ports/tests, dependency pins and Android prerequisites are retained. No C implementation was supplied/reviewed; do not claim that alternative dispatch is implemented. Do not run any historical Batch 1–7 brief or starter as a fresh task. Original delivered two-worker briefs are archived under `docs/briefs/archive/` for provenance only.

Future work needs a NEW Captain-issued brief with a current immutable base, exact disjoint file list, frozen interface and unique worker branch. Preserve any existing/unpushed work and report it; never reset it to fit a new task. Do not start another worker or duplicate an already reviewed concern without Captain coordination.

## Remaining native gates
Captain has integrated the default ledger-backed reminder session, namespace/full-identity/foreign-ID conflict preflight, validated cold/foreground tap routing, status/retry UI and a real external HTTPS launcher. Focused fake/widget tests cover these code paths but are not Android OS alarm/delivery proof. `lib/main.dart` selects the native runtime only when `KARMOPATH_FEED_URL` is supplied; empty/default stays on the foundation screen. The manual APK workflow now accepts an optional public HTTPS test-feed URL and forwards it as a Dart define; AAB builds ignore it. The owner-approved non-production fixture is documented in `test-feed/README.md`; never guess a URL or include credentials. Production-feed use still requires separate explicit owner approval. Verify fresh-feed startup/resume, offline behavior, reboot/package replacement, force-stop followed by relaunch, timezone changes and overdue reminders on an owner-authorized device before production activation. Plugin pending records are not independent proof of live OS alarms or delivery. Keep the web demo isolated. A request to push code is not production-activation or release approval.

## Verification
Run `python3 tool/preflight.py` and the focused Flutter test command in the NEW brief. Workers never run a full suite/analyze/build/gradlew/CI as a shortcut. If SDK unavailable report NOT RUN, never PASS. Method-channel/fake tests are not real-device permission, reboot or delivery evidence. Captain handles shared-surface analysis/integration checks. No local Flutter build/Gradle or CI dispatch/wait under these instructions.

## Report exactly five lines
Batch 7: <agent> ready (<sha7>) / blocked — <reason>
Changed: <owned paths and outcome>
Evidence: <commands, actual results, limitations>
Not touched: <shared surfaces / excluded work>
Next: <captain integration needs or none>
