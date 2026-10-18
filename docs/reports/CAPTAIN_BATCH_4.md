# Captain Batch 4 review — A, B and C integrated

## Reviewed immutable inputs

- A: `1ade1180b93905fe5db3838019bc1e9464083e5a` (code/test commit `66fcb09`).
- B: `9e348f9957e8ef43cadc7422a897be056c1b6b76`.
- C: `3a01784e216b22ba2a4779503e597a53d686282c`. Initially absent from remote; subsequently pushed by C, fetched and independently reviewed. Integrated with the captain corrections and gates below. The original A/B-only Python count below predates C4.

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

## C review and captain corrections

C's exact pushed SHA was fetched and its four-file scope verified. The CLI is offline/read-only, reuses the existing validator, rejects missing IDs and backwards editorial timestamps, preserves existing publication timestamps, and requires fresh review for content edits. No uploader or publication action was introduced.

Added four test methods covering null-valued extension additions/removals, nested JSON boolean-versus-number type changes, equivalent exact-deadline timestamp spellings and genuine submicrosecond deadline changes. Before the fix, the new cases produced four failure reports (including both null subcases): missing fields were conflated with null, Python equality conflated true with 1, and application_end_at compared as raw text. After the fix:

- Presence changes are content changes, including null-valued extensions.
- Canonical JSON comparison preserves value/type differences while ignoring object-key order.
- Nullable application_end_at compares exact parsed UTC instants, retaining submicrosecond precision; equivalent fractional spellings no longer demand a spurious review, while real deadline changes still do.
- admin/README.md records these comparison semantics. No validator acceptance policy, schema, feed data or frozen fixture was changed.

## Final combined gates including C

- `python3 -m unittest discover -s tests/feed`: **41 passed** (37 worker baseline plus four captain test methods).
- Existing Node behavior/UI suite: **17 passed**; JavaScript syntax checks passed.
- `flutter test`: **340 passed**, independently rerun with C changes present.
- `flutter analyze`: **No issues found** (Flutter 3.47.7 / Dart 3.13.5).
- Real Chromium **156.0.8078.4** smoke: **PASS** for import/edit/review/export and Python validation, corrupt storage recovery, unsafe content/URL checks, and 320px + 1280px layouts without horizontal overflow. Browser requests outside the local test origin were blocked. Test-only Playwright and extracted system libraries lived outside the repository under /home/user; no production dependency was added. Firefox and physical devices were not tested.
- Structural preflight and `git diff --check`: **PASS**.

All Batch 4 worker work is now integrated; no worker handoff remains blocked. Native factory/activation, actual notification integration, approved production feed and release safeguards remain pending captain work. No build, CI workflow, release, preview deployment, notification delivery or feed publication was triggered.
