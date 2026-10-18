# Batch 4 — reminder planning and production-readiness safeguards

## Starting point
A2+A3, B2+B3 and C are reviewed, squash-integrated and pushed. Immutable code base: `7d2e5037c163c64b1a14a62ccd62a56df0265623`. Captain independently fixed synchronous HTTP timeout cleanup and stale deadline clocks; **260 Flutter tests**, analyzer, **20 Python +17 Node tests**, structural preflight and Chromium 156 smoke passed. See [captain review](reports/CAPTAIN_BATCH_3.md). Production activation, actual scheduling and real feed remain pending.

**All workers start NEW branches from this exact code base.** Do not continue old branches: squash integration includes captain fixes absent from those histories. This dispatch-doc commit is later than the immutable code base; read the latest briefs before checking out the base. No merging latest main into a worker branch during work.

| Worker | New branch | Exclusive write scope | Task |
|---|---|---|---|
| A | `agent/A/reminder-plan-v1` | `lib/data/**`, `test/data/**`, `docs/reports/A4.md` | Pure deterministic reminder planner and reconciliation diff; no plugins |
| B | `agent/B/action-safety-v1` | `lib/features/**`, `test/features/**`, `docs/reports/B4.md` | External-link action safety, async lifecycle/races and truthful bilingual reminder feedback |
| C | `agent/C/feed-diff-v1` | `admin/**`, `tools/feed/**`, `tests/feed/**`, `docs/reports/C4.md` | Offline candidate-versus-published comparison gate and editorial handoff docs; no publication |

Read the exact [A](briefs/AGENT_A_BATCH_4.md), [B](briefs/AGENT_B_BATCH_4.md), [C](briefs/AGENT_C_BATCH_4.md) briefs. No overlapping writes; max three workers. Reports from prior batches stay intact. Worker evidence is not captain approval. Hand back pushed immutable SHAs; captain reviews and reruns gates before integration.

## Decisions frozen for this batch
- Planning only: one local reminder **24 hours before** each selected, open recruitment deadline, only when the reminder time is strictly in the future. Late opt-in produces no immediate catch-up alert. This policy must be visible in user copy. It is not proof a notification was scheduled or delivered.
- Deadline semantics remain the contract: exact UTC instant wins; date-only closes at next midnight Asia/Kolkata. Never import feature formatting into data or duplicate a conflicting rule.
- A returns a pure plan/diff; no OS ID mapping, permission prompt, timezone plugin or scheduler side effects. Captain owns real notification plugin, stable platform IDs, permissions, reconciliation orchestration and runtime composition. No change to UserPreferences or AppActions in a worker task.
- B success copy describes persisted intent only, not scheduled/delivered notifications. Do not claim OS cancellation merely because an intent was removed. Unsupported/denied permission must never be presented as a grant.
- C compares files locally. It cannot certify official-source authenticity and must never upload or replace the published feed. Human review and owner publication remain separate.

## Captain-owned follow-up
Assemble/initialize concrete preferences/cache/HTTP client with finally-safe cleanup, language persistence and retry tests; select appropriate plugin dependencies/platform settings; implement safe external actions and actual reminder scheduling/reconciliation; then activate native entrypoint only with explicit feed configuration. Keep web demo isolated. Real approved feed URL/content, source/legal/contact links, device tests and owner-authorized build/release remain required. No keys/payment/account details are needed for these three assignments.
