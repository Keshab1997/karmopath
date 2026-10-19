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
| Railway Recruitment Boards (RRB) central portal | https://rrbapply.gov.in/ (apply), https://rrb.indianrailways.gov.in/ (notices) | RRB NTPC, Group D and other CENs | `rrbapply.gov.in` named as the apply portal by several sources, but the page did not render and the notice PDF could not be opened. Not verified directly |
| RRB Kolkata (RRB for Eastern Railway) | https://www.rrbkolkata.gov.in/ | RRB Kolkata CEN notices | Named in the RRB all-RRBs listing; homepage fetch failed. Not opened directly |
| RRB Siliguri | https://www.rrbsiliguri.gov.in/ | RRB Siliguri CEN notices | Named in the RRB all-RRBs listing and a city-intimation page on the domain. Not opened directly |

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
