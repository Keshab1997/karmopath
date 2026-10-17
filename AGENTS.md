# Agent operating rules
Captain owns main; maximum three workers; each works on its named branch in an independent sandbox. Never merge, tag, release, trigger CI, change repository settings, or touch secrets. Never work in /tmp. Never copy credentials between agents. Use your own GitHub pairing only if necessary; reuse valid pairing.

## Captain-owned / DO NOT TOUCH
pubspec.yaml, pubspec.lock, .github/workflows/**, AGENTS.md, android/**, ios/**, lib/main.dart, lib/app/**, lib/contracts/**, lib/design_system/**, tool/preflight.py, test/contracts/**, test/fixtures/**, generated files including *.g.dart, version numbers, root docs and assets/**.

## Exclusive worker ownership
A: lib/data/**, test/data/**, docs/reports/A.md
B: lib/features/**, test/features/**, docs/reports/B.md
C: admin/**, tools/feed/**, tests/feed/**, docs/reports/C.md
No overlapping ownership. Workers may read all files. No dependency additions; request captain integration instead. No stub success, fake production data or credentials committed.

## Verification
Run repository's actual `python3 tool/preflight.py` once available. For Dart edits run only relevant test file(s); never flutter build apk/aab/web or gradlew. If SDK unavailable report NOT RUN, not PASS. No fabricated gates. Captain handles shared-surface integration and broader analysis/tests.

## Report exactly five lines
Batch 1: <agent> ready (<sha7>) / blocked — <reason>
Changed: <owned paths and outcome>
Evidence: <commands, actual results, limitations>
Not touched: <shared surfaces / excluded work>
Next: <integration needs or none>
