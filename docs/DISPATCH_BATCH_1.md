# Batch 1 — ready for three parallel agents
Common immutable code foundation: `f184482e4b74216c5ab91b0fd45f3f6d180a3d76`.
Repository: https://github.com/Keshab1997/karmopath.git (public).
SDK verified by captain: Flutter 3.47.7 / Dart 3.13.5.
Evidence: flutter analyze clean; flutter test 16 passed; structural preflight passed. Android build/signing/runtime not tested; local Java compatibility warning remains. No CI/build/release dispatched.

## Keshab: paste one starter into each independent agent session

### Agent A
```text
Work as Karmopath worker A. Clone https://github.com/Keshab1997/karmopath.git under /home/user. Read AGENTS.md, docs/DISPATCH_BATCH_1.md and docs/briefs/AGENT_A.md from origin/main before editing. Create branch agent/A/data-v1 from foundation f184482e4b74216c5ab91b0fd45f3f6d180a3d76. Follow that brief and contracts exactly. Your only write paths: lib/data/**, test/data/**, docs/reports/A.md. Do not modify main/shared files/dependencies/workflows/secrets. Run preflight and relevant tests, commit and push only your branch. Never trigger CI/build/release. Return the five-line report. Pair GitHub only if your own session is not already connected; never copy another agent's tokens.
```

### Agent B
```text
Work as Karmopath worker B. Clone https://github.com/Keshab1997/karmopath.git under /home/user. Read AGENTS.md, docs/DISPATCH_BATCH_1.md and docs/briefs/AGENT_B.md from origin/main before editing. Create branch agent/B/screens-v1 from foundation f184482e4b74216c5ab91b0fd45f3f6d180a3d76. Follow that brief and contracts exactly; approved design is docs/design/karmopath-home-v2.png. Your only write paths: lib/features/**, test/features/**, docs/reports/B.md. Do not modify main/shared files/dependencies/workflows/secrets. Run preflight and relevant widget tests, commit and push only your branch. Never trigger CI/build/release. Return the five-line report. Pair GitHub only if your own session is not already connected; never copy another agent's tokens.
```

### Agent C
```text
Work as Karmopath worker C. Clone https://github.com/Keshab1997/karmopath.git under /home/user. Read AGENTS.md, docs/DISPATCH_BATCH_1.md and docs/briefs/AGENT_C.md from origin/main before editing. Create branch agent/C/admin-v1 from foundation f184482e4b74216c5ab91b0fd45f3f6d180a3d76. Follow that brief and contracts exactly. Your only write paths: admin/**, tools/feed/**, tests/feed/**, docs/reports/C.md. Build local manual-post admin and validator; no publishing endpoint or browser GitHub token. Do not modify main/shared files/dependencies/workflows/secrets. Run preflight and Python unit tests, commit and push only your branch. Never trigger CI/build/release. Return the five-line report. Pair GitHub only if your own session is not already connected; never copy another agent's tokens.
```

## Setup and handoff
Read latest dispatch instructions before checking out the immutable foundation; documentation-only dispatch commit is intentionally separate. If the SHA cannot be fetched, stop and ask captain; never substitute an older docs-only base. Each worker uses its own authentication. Git identity: Keshab Sarkar / Keshab1997@users.noreply.github.com; core.fileMode=false. No production credentials required.

`flutter pub get` may be needed before relevant tests; don't commit unexpected pubspec/lock changes. If Flutter unavailable, record exact limitation and don't claim tests passed. The preflight is a structural check only.

Captain reviews full branch diffs, then integrates C/A/B. No worker merges or changes app routes. Final assembly, HTTP/disk adapters, reminder scheduling, ads and release remain captain-owned. Workers can start simultaneously because contracts exist; no worker imports another worker's concrete implementation.
