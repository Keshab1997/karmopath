# Agent operating rules
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
The runtime factory still requires a real reviewed reminder-session binding and external-launch callback; the native entrypoint is NOT activated. Complete namespace/identity/conflict handling and startup/reboot/force-stop hardening before activation. Plugin pending records are not independent proof of live OS alarms or delivery. Keep web demo isolated. Production activation requires the owner's explicit real feed URL approval plus the integration/device gates; a request to push code is not release/deployment/feed approval.

## Verification
Run `python3 tool/preflight.py` and the focused Flutter test command in the NEW brief. Workers never run a full suite/analyze/build/gradlew/CI as a shortcut. If SDK unavailable report NOT RUN, never PASS. Method-channel/fake tests are not real-device permission, reboot or delivery evidence. Captain handles shared-surface analysis/integration checks. No local Flutter build/Gradle or CI dispatch/wait under these instructions.

## Report exactly five lines
Batch 7: <agent> ready (<sha7>) / blocked — <reason>
Changed: <owned paths and outcome>
Evidence: <commands, actual results, limitations>
Not touched: <shared surfaces / excluded work>
Next: <captain integration needs or none>
