# Official sources — West Bengal recruitment bodies

Added: 2026-10-20, on the owner's instruction to find and record official
websites. This list records **where official notices are published**. It does
not contain job data, and no feed has been built or published from it.

Verification rule: a domain is listed here only when the official site itself
was opened, or when a government document or the body's own page names it.
Aggregator and job-blog sites are not sources and are excluded on purpose.

## Sources

| Body | Official site | What it publishes | How verified (2026-10-20) |
|---|---|---|---|
| West Bengal Public Service Commission (WBPSC) | https://psc.wb.gov.in/ | WBCS, Clerkship, Miscellaneous Services, Stenographer and other PSC advertisements, results, notices | Site opened; page title "Public Service Commission,WB"; "What's New" notices list |
| West Bengal School Service Commission (WBSSC, teachers and non-teaching in aided schools) | https://www.westbengalssc.com/ | SLST teacher recruitment, Group C/D non-teaching, notices, answer keys, results | Site opened; page title "WBSSC Teacher and Non-Teacher Recruitment" |
| West Bengal Police Recruitment Board (WBPRB) | https://prb.wb.gov.in/ | Constable and other police recruitment notices, results, merit lists | Official notice PDF names `https://prb.wb.gov.in` and `www.wbpolice.gov.in`; recruitment pages found on the domain. Homepage not fetched directly |
| West Bengal Police (main portal) | https://www.wbpolice.gov.in/ | Police department news and links | Named as the police website inside the WBPRB official notice PDF. Not fetched directly |
| West Bengal Health Recruitment Board (WBHRB) | https://www.hrb.wb.gov.in/ | Staff Nurse, Medical Officer, faculty and health posts | Notice page labelled "Only Official Website"; govt advertisement PDF gives `www.hrb.wb.gov.in`. Direct fetch returned 403 |
| Railway Recruitment Cell, Eastern Railway (RRC-ER, Kolkata) | https://www.rrcer.org/ | Cultural Quota, Scouts & Guides Quota, Act Apprentice notices (Eastern Railway units) | Notice board page opened; Cultural Quota 2026-27 PDF opened |
| WBPSC alternate host | https://www.psc.wb.gov.in/ | Same pages as `psc.wb.gov.in` | Used only as a fallback when the primary host times out. Checked 2026-10-20: both hosts returned the identical page title "Public Service Commission,WB" and the same "What's New" entries. Links from either host are still filtered by `allowed_domains` |
| Institute of Banking Personnel Selection (IBPS, banking/CRP recruitment) | https://www.ibps.in/index.php/crp-updates/ | CRP PO/MT, Clerk, Specialist Officer notifications, corrigenda, exam calendar | Added 2026-10-20: listing page opened, dated rows carry real `<a href>` targets to HTTPS PDFs, so `discover_notices.py` can read it. Domain is the commission's own (`ibps.in`); registration portals live on `ibpsreg.ibps.in` |
| Railway Recruitment Boards (RRB) central portal | https://rrbapply.gov.in/ (apply), https://rrb.indianrailways.gov.in/ (notices) | RRB NTPC, Group D and other CENs | `rrbapply.gov.in` named as the apply portal by several sources, but the page did not render and the notice PDF could not be opened. Not verified directly |
| RRB Kolkata (RRB for Eastern Railway) | https://www.rrbkolkata.gov.in/ | CEN notices for Eastern Railway, South Eastern Railway and unit-wise posts | Named in the RRB all-RRBs listing; homepage fetch failed (`HTTP 500`). Not opened directly. Note: an RRB is *zonal*, not state-wide - RRB Kolkata selects for ER/SER posts that include Bihar, Jharkhand and Odisha, so it is neither an all-India body nor a West Bengal-only one |
| RRB Siliguri | https://www.rrbsiliguri.gov.in/ | RRB Siliguri CEN notices | Named in the RRB all-RRBs listing and a city-intimation page on the domain. Not opened directly |

## Found while listing these sources (2026-10-20)

- **`rrceronline.co.in` is the RRC-ER application host, and it is not an
  approved domain.** The Cultural Quota and Scouts & Guides apply links on the
  RRC-ER notice board point there, so `publish_notice.py` rejects them and
  `notice_url` for the Eastern Railway source can only ever be the
  `rrcer.org` notice PDF. That is the correct gate: the notice board is the
  source of truth, and the apply portal is reached from it. Adding the host to
  `allowed_domains` needs an owner decision, not a code change.
- **The WBPSC homepage capture was dated.** Every entry in the captured
  "What's New" list carried a 2025 stamp. It is not known whether the site
  listed nothing newer or the fetch served a cached page, and the sandbox has no
  network egress to re-check. WBPSC candidates in `docs/proposals/` must be
  confirmed against the live page before any label is applied.

## Central bodies: what could not be crawled (checked 2026-10-20)

Scope includes central recruitments, so each candidate was opened and tested for
crawlability, not just authenticity. `discover_notices.py` needs a real
`<a href>` with visible text in the served HTML, HTTPS only.

| Body | Result | Why it is not a source yet |
|---|---|---|
| SSC (`ssc.gov.in`) | Homepage loads, Notice Board titles present | The board renders from JavaScript and `ssc.gov.in/notice`, `/notice-board` return the site's 404 view. No anchor targets in the served HTML, so discovery would find nothing |
| UPSC (`www.upsc.gov.in`) | Homepage loads | Served body is a skip link and nothing else; listings are JS-rendered |
| RRB Kolkata (`www.rrbkolkata.gov.in`), RRB portal (`www.rrb.gov.in`) | `HTTP 500` from this network | Could not be opened at all, so neither is confirmed official-by-inspection. Likely a WAF rejecting datacenter/foreign requests - retry from an ordinary Indian connection before ruling it out |
| Employment News (`employmentnews.gov.in/NewEmp/Home.aspx`) | Homepage loads | Notice links are `http://` (rejected: feeds and cards must be HTTPS) and the JOB HIGHLIGHTS table has no per-vacancy anchor. Weekly PDF would need a different reader |
| IBPS (`www.ibps.in`) | **Added as a source** | Plain HTML, dated rows, HTTPS PDFs. Its own result/registration rows point at `http://ibpsreg.ibps.in/...` and are skipped by the HTTPS rule, so a card can only link the notification PDF, not the login |

Consequence to keep in mind: an all-India central exam whose notice sits behind
JS or a WAF cannot be surfaced by the daily crawler at all. If RRB CEN coverage
matters, the practical route is one hand-checked card per CEN from
`rrbapply.gov.in`, approved through the label gate, rather than a source entry.

One consequence of the zonal structure: "add RRB Kolkata because the app is about
West Bengal" is not a valid reason. A CEN selects for a railway *zone*, whose
post locations are listed in that CEN's own vacancy schedule. `districts` on a card
therefore comes from the approved source entry in `ops/notice_sources.json`, which
states where that body's posts generally are - never from a default and never from
where its office sits. A single all-India CEN that also posts in Bengal is tagged
`All India`, and the home district filter keeps such a card visible for any district
(`allIndiaDistrict` in `lib/features/common/formatting.dart`).

## Not yet verified

- **Railway NTPC/Group D PDFs:** the official notice PDF did not open from the sandbox, so the dates and vacancy figures for those notices come from third-party articles and need checking against the PDF.

- **West Bengal Staff Selection Commission (WBSSC, Group C/D and clerical):**
  search results give different domains (`wbssc.gov.in`, `wbssc.wb.gov.in`).
  Neither could be opened, so none is listed. Confirm with the owner before
  adding one.
- **wb.gov.in (state government portal):** not opened from the sandbox. Add it
  only after a manual check.
- **Panchayat & Rural Development recruitment (wbprms.in, prd.wb.gov.in), WB
  Municipal Service Commission (mscwb.org), WBBPE, Employment Bank:** domains
  seen only in third-party articles, and the fetches failed.

## Naming warning

"WBSSC" is used for two different bodies. Keep them separate:

- **West Bengal School Service Commission** — teachers and non-teaching posts
  in aided schools. Domain: `westbengalssc.com`.
- **West Bengal Staff Selection Commission** — state clerical and Group C/D
  posts. Domain not verified yet.

## Still needed before a verified job feed

1. A human opens each row above and checks it matches the official notice. (Notice-only cards follow the `approve-notice` path in `REAL_DATA_RUNBOOK.md`; they do not claim vacancies, eligibility or dates.)
2. Each job added to a feed carries its own `source_url` and `notice_url` taken
   from the official notice page, plus a human `reviewed_at` date.
3. Owner approval for the production feed, as set out in `AGENTS.md`.
