# Product requirements — v1
## Goal
Bengali-first West Bengal recruitment discovery, official-source links, results/admit-card updates and deadline tracking. Independent information utility, not a government service or application-submission portal.

## Scope of employers
State-government and central-government recruitments are both in scope: West
Bengal bodies (WBPSC, WBSSC, WBPRB, WBHRB) and all-India ones whose posts are
served in the state (railway cells and boards, IBPS, SSC, UPSC, Ministry
recruitments). What limits coverage is which official listing page can be
crawled, never the employer's level - see `docs/OFFICIAL_SOURCES.md`. Recorded
2026-10-20 at the owner's instruction, after "West Bengal" was read as "state
bodies only" and an agent proposed removing the railway notices.

## Approved identity
Karmopath; com.keshabstudios.karmopath; tagline কোনো ডেডলাইন আর মিস নয়। Approved home v2 screenshot is visual reference, not a raster screen to ship. English fallback; proper Unicode Bengali text rendered by Flutter.

## MVP
- Search/filter by category, district, qualification, update kind and closing status.
- Home, job detail, saved list, deadline calendar, profile/settings (no account required).
- Details: dates, eligibility, vacancy count if known, application procedure, original notice/apply links, source, last verified time, correction contact.
- Local bookmarks and opt-in local reminders; cached read-only offline feed with stale/offline indicator.
- Manual admin draft/validation/export; captain-controlled publication.
- Accessible light theme; dark theme after core parity. FCM and production AdMob are release integrations, not worker prerequisites.

## Non-goals
No exam coaching, AI chatbot, paid subscription, embedded government forms, user accounts, public write endpoints, automatic unreviewed AI publication, competitor-summary copying, or claims of official affiliation. No salary/eligibility guessing. No production fixture jobs.

## Content quality
Only human-reviewed entries with directly linked official notice/source. AI may assist extraction but cannot certify accuracy. Missing information stays null/unknown. Corrections update the same ID and timestamp. Expired entries remain accessible clearly marked closed; withdrawn entries never look open.
