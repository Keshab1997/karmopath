# Agent A — Batch 8 Android reminder verification plan

**Captain-issued follow-up draft.** Branch: `agent/A/b8-device-verification-plan-20261018`  
**Immutable base:** `dcadb0e9b5ed304b91056770c6b094591ed52122` (current `main`)  
**Do not start until given this brief in your independent workspace.**

## Goal

Create a practical, owner-run Android device verification matrix for the native reminder gates that remain after Batch 8. The app does not yet have an approved production feed or activated native runtime, and you have no device evidence to claim. This assignment is a **test plan only**, not a test execution report.

## Exact write allowlist — no other files

- `docs/ANDROID_REMINDER_DEVICE_TEST_PLAN.md` — new manual procedure and evidence template.

Do not edit existing docs, app/runtime code, contracts, Android files, test code, dependencies, workflows, assets, or settings.

## Frozen document format

The new document must contain:

1. A prominent status: **PLAN ONLY — DEVICE TESTS NOT RUN**.
2. Preconditions/blockers, including Captain integration of the reviewed runtime/backend/tap work, an owner-approved HTTPS test feed, a Captain-provided installable build, and an owner-authorized Android device. If a prerequisite is absent, tests are **BLOCKED**, not PASS.
3. A table with exactly these columns: `Case`, `Gate`, `Setup`, `Steps`, `Expected observation`, `Evidence to record`, `Result`.
4. A concise evidence template recording app commit/build SHA, device make/model, Android version/API, permission/channel state, timezone, feed availability, test timestamp, observed result, and redaction notes.
5. Explicit limitations: plugin pending records are not independent proof of an AlarmManager alarm; API acceptance is not a delivery receipt; `inexactAllowWhileIdle` may be delayed; OEM behavior varies; a successful fake/widget test is not device evidence.

## Required test cases

Cover at minimum:

- Fresh install/first launch and app resume do not show a permission prompt; only explicit user action may prompt.
- Permission denied, permission status unavailable, permission revoked in Settings, and explicit re-enable; intent and backend state must be described truthfully.
- Verified feed unavailable/null versus a successfully loaded empty feed; no destructive cleanup based merely on a missing feed.
- Schedule and cancel a selected open recruitment reminder; check its full job identity, language/copy variant, timezone handling, and per-ID behavior without promising exact delivery time.
- Language change replaces stale copy without duplicate reminders.
- Foreground and cold-start notification taps resolve only a valid job ID; unavailable jobs show the app's safe unavailable state, never an arbitrary URL.
- App restart, phone reboot, package replacement/update, force-stop, and subsequent relaunch/resume; separately record what was observed versus what the plugin registry reports.
- Timezone change and offline/missing-feed resume; no late-opt-in catch-up alert.
- Actual notification appearance, if the owner can wait for the one-shot schedule; record observed time and device conditions, never treat the scheduled request alone as delivery proof.

Do not invent a feed URL, add a shorter production reminder interval, enable exact alarms, change app code, or perform any of these device tests yourself. Keep each case reproducible and separate expected behavior from evidence actually collected. Leave every `Result` as `NOT RUN` in the plan template; do not fabricate PASS results.

## Focused verification

This is Markdown-only:

```bash
python3 tool/preflight.py
```

No Flutter setup/test, analyze, build, Gradle, CI dispatch/wait, device test, feed publication, release, or deployment.

## Handoff

Push only `agent/A/b8-device-verification-plan-20261018`, then report the exact branch SHA with the five-line Batch 8 format. The Captain owns integration and all actual device-gate evidence.
