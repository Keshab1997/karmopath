# Remaining work and dispatch — batch 2
Status: A/B batch 1 merged; C review-fix branch pending captain approval. Preview startup failure patched; owner must start a new main workflow run. No successful new preview deployment is claimed.

A/B common code base: `184ca97a2e34c7d93bb10273538312c69730742e`. Captain added http 1.6.0 and shared_preferences 2.5.6; dependency baseline analysis clean, 132 Flutter tests PASS, preflight PASS. Read latest docs BEFORE switching to base, since dispatch docs are a following docs-only commit. Shared dependency/interfaces ready: no worker needs another worker's implementation.

## Dispatch now (three independent sessions)
- A: read docs/briefs/AGENT_A_BATCH_2.md; branch agent/A/platform-v2 from common code base. Concrete HTTP/persistent storage adapters and tests.
- B: read docs/briefs/AGENT_B_BATCH_2.md; branch agent/B/ui-polish-v2 from common code base. District/qualification filters, truthful error feedback, accessibility and tests.
- C: read docs/briefs/AGENT_C_BATCH_2.md; CONTINUE agent/C/admin-v1 (do not start from A/B base). Finish admin regression/browser/validator hardening without dropping prior fixes.

No overlapping write ownership. Captain won't edit worker-owned areas during this batch. New reports A2/B2 and existing C only. Every worker returns a commit SHA and five-line report; captain reviews actual diff and tests before merging. No one dispatches CI except Keshab.

## Remaining captain-owned work after this batch
1. Review C fixes/full admin; review A/B batch 2 branches and integrate one at a time.
2. Production composition: persistent adapters, safe configured public feed URL, missing/stale-detail handling, navigation, language persistence, robust startup errors, lifecycle disposal. Demo preview remains separate and labeled.
3. Local reminder delivery: add/pin platform plugin centrally, permission UX, scheduling/cancel/reschedule on corrections/closure, storage-vs-scheduling failure reconciliation, Android timezone/background restrictions and device testing. FCM optional later; no existing delivery guarantee.
4. Original reviewed content and publication: validate candidate, check actual original notices/eligibility/dates/source ownership, set actual publication timestamps, atomic last-good-feed publication on approved public host; no browser writes/tokens. Automation only later in a separately approved private ingestion repo; Indian-source connectivity unresolved.
5. Final art/visual review: AI category assets/launcher, real Bengali rendering/contrast/large-font checks, native-vs-web behavior, owner-approved actual UI. Never treat AI screenshot/mock data as release proof.
6. Legal/support/privacy: owner contact, correction channel, legal pages and real SDK Data safety/consent/audience review, government/news policy declarations as applicable. Disabled placeholders are release blockers.
7. AdMob integration: test IDs first, consent, safe placements, app-ads.txt/developer-site verification; real IDs/secrets only through authorized secure setup. No paid services without approval.
8. Play release: current target SDK, identity/account/testing requirements, real device testing, signing/keystore safety, accurate store screenshots/copy and production review. Keshab alone authorizes CI/release/tag/upload. No approval or revenue guarantees.

## Owner inputs required later
Support/correction email; actual original notices for initial jobs; Play account/tester status; AdMob/FCM project setup if used; authorized signing setup. Don't paste private keys into public repo or worker briefs. Monthly-zero is a free-tier design target, not unlimited infrastructure.

Work here is sequenced: these remaining release tasks cannot safely be promised as three one-shot worker jobs before integration and owner inputs exist.
