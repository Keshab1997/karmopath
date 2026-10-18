# Batch 3 — focused hardening, no new branches
Batch 2 work is pushed but NOT captain-approved/merged. Do not treat worker report counts as independent captain validation. Continue each existing branch so fixes aren't lost. Read latest briefs from main first, then return to your own branch without merging main.

- A: agent/A/platform-v2 — re-entrant single-flight repository and dispose regression tests/fix. Brief: docs/briefs/AGENT_A_BATCH_3.md.
- B: agent/B/ui-polish-v2 — time-aware deadline state, app-resume refresh and delayed permission race. Brief: docs/briefs/AGENT_B_BATCH_3.md.
- C: agent/C/admin-v1 — actual browser admin smoke, not just fake-DOM tests. Brief: docs/briefs/AGENT_C_BATCH_3.md.

No overlapping ownership. New reports A3/B3/C3 are explicitly allowed by these briefs. No waiting on another worker. Captain doesn't edit these owned areas while this batch runs. Workers hand off exact immutable SHAs after pushing; captain reviews complete diffs and actual gates before squash merges. Only then are their changes called integrated.

Captain's independent production shell is on main (8c1dadc), but native activation/feed/actions/scheduling remain pending. Do not reimplement captain composition. The previous successful web preview run deployed a773f9a, not these unmerged branches or the production shell. Owner may dispatch another preview after integration; workers must not dispatch it.

Remaining release work continues to be sequenced in docs/BATCH_2.md. No request for keys/payment/testing-account details is needed for this batch. No claim of Play readiness or guaranteed approval.
