# Captain integration review — batches 2 and 3

Reviewed worker heads: A `4b3b24a`, B `b98e84b`, C `a2a38f6243ff95cc4e9fbf8b77df9eb231363835`.
Full worker changes were integrated as separate squash commits, not just the batch-3 deltas.

## Captain corrections

- A: Added a regression for injected HTTP `send` throwing `TimeoutException` synchronously. It failed with an uninitialized send future; changed the future to nullable and guarded late-response cleanup. Caller still owns the client. Data suite: **104 passed**.
- B: Added a regression advancing an injected wall clock between timer callbacks, then introducing a nearer deadline. It failed because rebuilds used the last timer snapshot. Reads and watch scheduling now refresh the clock without notifying during build. Feature suite: **130 passed**.
- C: Reran Python and Node tests and the real isolated Chromium smoke. Chromium initially could not launch because sandbox system libraries were missing; after extracting test-only libraries under `/home/user`, the smoke passed. No production dependency was added.

## Combined verification

- `flutter test`: **260 passed**.
- `flutter analyze`: **No issues found**.
- `python3 tool/preflight.py`: **PASS** (structural only).
- `git diff --check`: **PASS**.
- Python validator tests: **20 passed**.
- Node admin behavior/UI tests: **17 passed**.
- Chromium **156.0.8078.4**: import/edit/review/export and Python validation, corrupt-storage backup/recovery, unsafe HTML/URL handling, and **320px + 1280px** layouts passed. No horizontal overflow detected. Browser requests outside the local test origin were blocked. Firefox and physical devices were not tested.

## Remaining boundaries

This is integration approval, not production/release approval. Native runtime activation, concrete composition/resource ownership, external actions, real notification scheduling/reconciliation and device tests, and a real human-reviewed public feed remain pending. The admin exports local candidates only; it does not publish. Existing demo deployment was not changed. No workflow, build, release, notification delivery or job publication was triggered by this review.
