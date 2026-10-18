# Batch 6 — reminder apply orchestration, surfaces everywhere, publish checklist

## Starting point
Batch 5 (state/eligibility/admin safety) squash-integrated and pushed as `2f4ae45` (docs/BATCH_5). Immutable code base: `2f4ae45`. Captain verified 416 Flutter + 41 Python + 26 Node pass, analyzer clean. No build/release/publication performed.

**All workers start NEW branches from this exact base.** Do not continue old branches; squash integration includes captain docs absent from those histories.

| Worker | New branch | Exclusive write scope | Task |
|---|---|---|---|
| A | `agent/A/reminder-apply-v1` | `lib/data/**`, `test/data/**`, `docs/reports/A6.md` | Pure reminder apply orchestrator: platform abstraction, cancel-before-schedule, per-operation ledger persistence, failure-safe |
| B | `agent/B/reminder-surface-v1` | `lib/features/**`, `test/features/**`, `docs/reports/B6.md` | Show stored-intent subtitle on Calendar/Saved + settings summary, reuse B5 intent_state |
| C | `agent/C/publish-check-v1` | `admin/**`, `tools/feed/**`, `tests/feed/**`, `docs/reports/C6.md` | Offline publish-readiness checklist CLI + admin panel (no upload) |

Read exact A/B/C briefs in `docs/briefs/AGENT_*_BATCH_6.md`. No overlapping writes; max three workers. Reports from prior batches stay intact.

## Decisions frozen
- Orchestrator is pure: no plugin, no permission, no network; only `ReminderStateStore` + abstract platform. Failure never marks whole plan applied.
- Surfaces never claim scheduled/delivered/missed — only "stored request" copy from `reminder_intent_state.dart`.
- Checklist is read-only, offline, reuses validator; it does not publish or auto-approve. Owner publication remains separate.

## Captain-owned follow-up
After Batch 6: select notification plugin, wire concrete factory/composition with finally-safe init, add reboot/permission reconciliation, then activate native entrypoint only with explicit feed config. Keep web demo isolated. Real approved feed content and release remain owner-gated.

