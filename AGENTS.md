# Agent operating rules
Captain owns main; maximum three workers. Workers push their named branches in independent workspaces; only Captain reviews/integrates/pushes main. Workers never merge, tag, release, trigger CI, change repository settings, or copy/expose credentials. Never work in /tmp. Reuse your own valid GitHub pairing. No file-transfer handoff: push a branch, then report.

## Captain-owned / DO NOT TOUCH
pubspec.yaml, pubspec.lock, .github/workflows/**, AGENTS.md, android/**, ios/**, lib/main.dart, lib/app/**, lib/contracts/**, lib/design_system/**, tool/preflight.py, test/contracts/**, test/fixtures/**, generated files including *.g.dart, version numbers, root docs and assets/**. Workers may read these but must not edit them. No dependency additions.

## Active dispatch: Batch 7
The owner requested parallel implementation on 2026-10-18. This supersedes the earlier captain-only **assignment** in docs/BATCH_7.md, not the shared-surface or release restrictions. Read docs/DISPATCH_BATCH_7.md, docs/BATCH_7_CONTRACTS.md and your Batch 7 brief from origin/main before checking out its frozen code base. Do not execute historical Batch 1–6 briefs.

Batch 7 exclusive writes (no overlap):
- A: lib/data/reminders/reminder_synchronizer.dart; test/data/reminders/reminder_synchronizer_test.dart; docs/reports/A7.md.
- B: lib/platform/notifications/**; test/platform/notifications/**; docs/reports/B7.md.
- C: lib/native/runtime/**; test/native/runtime/**; docs/reports/C7.md.
Everything else is read-only for these workers, including existing data/features/admin implementations. This narrow Batch 7 map overrides the historical A=data, B=features, C=admin area map only for this batch. Request captain help for a missing interface or an out-of-scope fix; do not silently expand ownership.

Workers implement independently against lib/contracts/native_reminders.dart. No worker imports another worker's not-yet-merged implementation. Captain later connects A/B/C in lib/app/** and owns native entrypoint/lifecycle/tap navigation. Production activation still requires an explicitly approved feed URL; no guessed URL or fake live data.

## Verification
Run python3 tool/preflight.py and the focused Flutter tests listed in your brief. No full test suite/analyze for workers, no flutter build apk/aab/web or gradlew, no CI dispatch/wait. If SDK unavailable report NOT RUN, never PASS. Method-channel/fake tests are not real-device permission, reboot or delivery evidence. Captain handles shared-surface checks, integration and the owner-approved device/build gates.

## Report exactly five lines
Batch 7: <agent> ready (<sha7>) / blocked — <reason>
Changed: <owned paths and outcome>
Evidence: <commands, actual results, limitations>
Not touched: <shared surfaces / excluded work>
Next: <captain integration needs or none>
