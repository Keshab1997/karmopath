# Batch 5 — durable reminder state, eligibility truth and admin draft safety

## Integration status

A, B and C independently reviewed and integrated with captain corrections; **416 Flutter + 41 Python + 26 Node tests pass**, analyzer clean. No worker handoff remains blocked. See captain review below. The original Batch 4 dispatch remains historical; do not start duplicate work from it.

## Starting point

Batch 4 (planner/diff, action safety, feed diff) squash-integrated as `f09d8bd` (feed) + `d5e2b7e` (actions) + `3e79ad4` (planner) on top of `7d2e503`. Captain corrections included concurrency guard, sync-throw guard, deferred-permission semantics and Python type-preservation. See `docs/reports/CAPTAIN_BATCH_4.md`.

Immutable code base for this batch: `f09d8bdfd602fc584bbc916d100986d3be86ad76`. Captain fixes for batch 3 (re-entrant refresh, fresh wall clock) included.

**All Batch 5 workers started NEW branches from this exact base.** Do not continue old branches.

| Worker | Branch (now merged and deleted) | Exclusive scope | Task |
|---|---|---|---|
| A | `agent/A/reminder-state-v1` | `lib/data/reminders/**`, `test/data/reminders/**`, `docs/reports/A5.md` | Durable reminder registry and applied-state ledger — single-key versioned document, monotonic 1..2147483647 IDs, strict validation, serialised ledger |
| B | `agent/B/reminder-eligibility-v1` | `lib/features/**`, `test/features/**`, `docs/reports/B5.md` | 24h eligibility gate (strict `closes-24h > now`), truthful stored-intent state, ticker includes cutoff |
| C | `agent/C/admin-draft-safety-v1` | `admin/**`, `tests/feed/**`, `docs/reports/C5.md` | Dirty tracking per-draft/workspace, beforeunload/import/reset warnings, exact timestamp freshness guard |

Read exact A/B/C briefs in `docs/briefs/`.

## Decisions frozen for this batch
- Reminder state is one key `karmopath.reminder_state.v1` with schema_version inside document; no silent reset, no migration, no auto-repair.
- Allocation never wraps, never reuses IDs after cancellation, never derives from hashCode.
- 24h cutoff is strict: `closesAt - 24h > now` to accept; at equality it is too late. Closed/withdrawn checked first.
- Stored-intent copy never claims scheduled/delivered/missed; only "stored request" plus current job state.
- Admin dirty state compares canonical JSON; review requires later `reviewed_at`/`updated_at` than existing timestamps with submicrosecond precision; unknown/null extensions preserved.

## Captain-owned follow-up (still pending)
Assemble/initialize concrete preferences/cache/HTTP client with finally-safe cleanup; select notification plugin dependencies and platform settings; implement actual scheduling/reconciliation orchestration that persists only after OS success; then activate native entrypoint with explicit feed config. Keep web demo isolated. Real approved feed URL/content, source/legal/contact links, device tests and owner-authorized build/release remain required.

No keys/payment/account details needed for Batch 5 assignments.
