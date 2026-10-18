# Captain Batch 4 review — A and B integrated; C pending handoff

## Reviewed immutable inputs

- A: `1ade1180b93905fe5db3838019bc1e9464083e5a` (code/test commit `66fcb09`).
- B: `9e348f9957e8ef43cadc7422a897be056c1b6b76`.
- C: owner relayed local HEAD `3a01784e216b22ba2a4779503e597a53d686282c`, but `agent/C/feed-diff-v1` was absent from the remote when checked. **C code has not been received, reviewed, tested or integrated.** Its reported 37 Python tests are worker evidence only. The 20 Python tests below belong to the existing main validator, not C4.

## A acceptance and integration boundary

Pure 24-hour reminder planning and full-ID reconciliation reviewed; no plugins, permission or scheduling side effects. Data tests independently rerun: **150 passed**. Reconciliation preserves the prior content fingerprint and cancels before replacing; no platform hash IDs introduced.

Captain integration must persist successful OS operations, not blindly mark the entire desired plan as applied if any cancellation/scheduling/storage operation fails. Previous-applied-plan recovery, stable platform IDs, OS state checks, time advancement, restart and permission reconciliation remain unimplemented. The semantic planner fingerprints both titles but does not accept the active UI language: if the platform creates a single-language alert, its persisted payload fingerprint must also include the selected language/copy version. Changing locale must trigger payload reconciliation even when this pure plan is unchanged. A plan is not evidence of delivery.

## B captain corrections

1. Added `captain_action_concurrency_test.dart`: a notice launch followed by a source launch with out-of-order completion showed that one `_pendingLink` string lost the other pending button's state. Regression **failed before / passed after**. Pending state is now a set per URL; completion clears only its own URL. Existing guard still suppresses duplicate launches.
2. Added a genuinely synchronous launcher implementation that throws before returning any Future. The guard catches it. The worker's `FakeActions.openExternal` is async, so its `openThrowsSync` label alone was not proof of a pre-Future throw.
3. Corrected the deferred-permission/unmount test's misleading name/comment and added the missing assertion: the controller **does persist** the user's intent after unmount; only widget callbacks are suppressed. Disposal does not cancel a controller request. No shared cancellation contract was added. This supersedes the original B4 report table row claiming it writes nothing.
4. Full integration initially exposed an old Bengali denial-wording assertion in captain-owned `test/app/preview_app_test.dart`. Updated it to the actual denial message and additionally asserted the UI remains off, preserving the original permission-denied behavior rather than removing coverage.

## Independently executed gates, after corrections

- `flutter test test/data`: **150 passed**.
- `flutter test test/features`: **164 passed**.
- `flutter test`: **340 passed**.
- `flutter analyze`: **No issues found**.
- Python existing validator suite: **20 passed**.
- Existing Node admin behavior/UI suite: **17 passed**.
- Structural preflight and `git diff --check`: **PASS**.

Flutter 3.47.7 / Dart 3.13.5. Real browser smoke was not rerun for this A/B-only change; admin remains untouched. No physical-device/plugin, notification delivery, build, workflow, release or feed publication was run. Preview deployment was not changed.

## C handoff needed

C should push its own branch using its own authorized pairing, or send a Git bundle containing its local commits based on `7d2e503`. Do not copy a token or re-pair the captain for another worker. Once received, captain reviews compare.py and its tests and runs the combined Python suite before integration. Native factory/activation, actual notification integration, approved production feed and release safeguards remain separate pending captain work.
