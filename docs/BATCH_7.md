# Batch 7 — notifications and native integration

## Current decision
On 2026-10-18 the owner requested workers for this batch. This **replaces the
previous captain-only assignment**, not shared-file, security or release rules.
Batch 6 is already integrated at main `80adedc`; do not repeat its applier/UI/admin work.

**Dispatch ready, workers not started by Captain.** Read
[common setup/ownership](DISPATCH_BATCH_7.md),
[frozen API](BATCH_7_CONTRACTS.md) and the assigned brief from origin/main.
All workers branch from **`bffcfb473d14f66bf47b85be96558497cc387dc4`**.

| Worker | Work | Brief |
|---|---|---|
| A | Reconcile reported pending reminders against ledger, then reuse applier | [A7](briefs/AGENT_A_BATCH_7.md) |
| B | Concrete Android notifications, permission and validated tap boundary | [B7](briefs/AGENT_B_BATCH_7.md) |
| C | Retryable resource/runtime factory with sync triggers and cleanup | [C7](briefs/AGENT_C_BATCH_7.md) |

Disjoint namespaces; only frozen ports cross boundaries. Captain has prepared
packages/lock, ports/tests, Android permission/boot receiver/desugaring/icon/keep
prerequisites. No worker implementation is claimed complete. Foundation gates:
471 Flutter tests (including 19 new port tests), analyzer and preflight clean;
Android XML/static prerequisite checks only. See [evidence](reports/CAPTAIN_BATCH_7_DISPATCH.md).

## Captain integration afterwards
Read actual pushed diffs; review and integrate one stream at a time. Compose the
three outputs in lib/app/**, bind lifecycle resume and safe job-ID tap navigation,
expose real sync failures/status through the existing optional settings surface,
and add integration regressions. Keep web demo separate. Plugin pending records
are not independent proof of live OS alarms or visible delivery.

**Activation still blocked:** no owner-approved production HTTPS feed URL.
Do not guess one or wire main to a fake live feed. Real Android permission,
reboot/upgrade/cold-start and delivery evidence remains pending. No local
flutter build/gradlew, CI dispatch/wait, settings/secrets changes, publication,
release, keys/payment or Play approval is authorized by this dispatch.
