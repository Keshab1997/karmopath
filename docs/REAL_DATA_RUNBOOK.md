# Showing real official notices in the app — runbook

Status: **one path is wired and public.** `feed/jobs.json` on `main` is the app
feed. It starts empty and grows one notice at a time, only after a human checks
the official link.

## The chain

| Step | Who | What happens |
|---|---|---|
| 1. Discover | `discover-notices.yml` (daily 09:00 IST, or manual) | Reads the approved listing pages in `ops/notice_sources.json`, records every current link in `ops/notice_seen.json`, and opens one `notice-review` issue for each **new** link. The first run is a baseline and reports nothing. |
| 2. Check | Human | Opens the notice on the official site. Confirms the source and the notice are genuine. |
| 3. Approve | Human with write access | Applies the `approve-notice` label to that `notice-review` issue. |
| 4. Publish | `publish-notice.yml` (issues event) | Parses the issue, re-checks the link against the approved domains for that source, appends one `kind: notice` card to `feed/jobs.json`, validates the feed offline, commits to `main`, comments the result and closes the issue. |
| 5. Consume | App | Fetches `https://raw.githubusercontent.com/Keshab1997/karmopath/main/feed/jobs.json`. |

Discovery still never publishes to the feed. The label is the only publication
gate, and it can only be applied by someone with repository write access.

## Notices that discovery will never report

Step 1 records links before it reports them, so anything already on a listing
page at the time of the first successful crawl is invisible to the pipeline for
good. Two consequences, both seen on 2026-10-20:

- **A thin feed is not a broken feed.** On 2026-10-20 the live feed carried one
  card, and that card was the only notice the pipeline had ever reached. The
  other current notices on the three approved boards had been recorded as seen
  without ever being proposed.
- **A source that has never answered has never been crawled at all.** Every
  scheduled run of 2026-10-19/20 reported `WBPSC ... <urlopen error timed out>`
  and `ops/notice_seen.json` holds zero `psc.wb.gov.in` keys.

The read-only backfill for both cases is `scripts/notice_proposals.py`. It
accepts a discovery report or a hand-curated list, prints one notice-only card
per link using the publisher's own builder, and writes `gh issue create`
commands. It never touches `feed/jobs.json` (it refuses any path inside
`feed/`) and never applies `approve-notice`, so the gate is unchanged:

Scratch files stay outside the repo (`../scratch/`) so no artifact is ever committed:

```bash
# 1. What is live right now, including links an earlier run already recorded.
#    This writes nothing: the seen file is left alone on purpose.
python3 scripts/discover_notices.py \
  --sources ops/notice_sources.json --seen ops/notice_seen.json \
  --out ../scratch/candidates.json --report-candidates --max-new 40

# 2. Turn the links worth a review into proposals + an issue script.
python3 scripts/notice_proposals.py \
  --candidates ../scratch/candidates.json --sources ops/notice_sources.json \
  --seen ops/notice_seen.json --feed feed/jobs.json \
  --out docs/proposals/batch.json --feed-preview docs/proposals/batch.preview.json \
  --issues-out docs/proposals/batch.sh --limit 14
```

`docs/proposals/notice-only-batch-2026-10-20.*` is the result of the first such
run (14 cards, 2 links skipped: one already in the feed, one on a host the
source does not allow). Approving it means opening the issues, checking each
notice on the official site and labelling it — not merging the preview.

## Adding a source that has never been crawled (state or central)

Level of employer is not a filter: WBPSC, WBSSC, RRC-ER and IBPS are all approved
sources now. A new source needs three things, in this order:

1. Open the listing page and confirm the domain is the body's own, then record
   it in `docs/OFFICIAL_SOURCES.md` - including a failure, and why.
2. Check the served HTML actually contains the notice anchors. Commission sites
   that render their board in JavaScript (SSC, UPSC) are not crawlable by this
   script, and `HTTP 500` from a datacenter connection (RRB) is not proof of a
   dead site. Both are recorded rather than guessed at.
3. Give it a `districts` list in `ops/notice_sources.json`: where that body's
   *posts* are, not where its office is. The publisher refuses a source that has
   not declared it, because stamping every card `West Bengal` was the old default
   and it is wrong for a zonal or all-India body (RRC-ER selects for ER units that
   include Bihar divisions; an IBPS CRP allocates across participating banks in
   many states, so it is `All India`).
4. Before the first successful crawl, `--seed` it (see *Flaky sources*), or the
   run opens one issue per historic notice up to `--max-new`.

## Flaky sources

`scripts/discover_notices.py` now retries each listing URL (default 3 attempts
with a short backoff, `--retries`/`--backoff`/`--timeout` to tune) and, when a
source defines `alternates`, falls through to those URLs before declaring the
source unreadable. A source is reported as failed only when every URL for it has
exhausted its retries, so a slow mirror can no longer look like "no new
notices". WBPSC carries `https://www.psc.wb.gov.in/` as an alternate.

After a source that has been unreachable finally works, seed it before you want
issues: `--seed` records the whole current listing and reports nothing. Without
it, the first successful WBPSC crawl opens one issue per historic notice up to
`--max-new`.

## What a notice card contains

- `kind: notice`, `status: published`.
- The official listing title, in both `title_bn` and `title_en`. No translation
  is invented; if the official title is English, both fields carry it.
- The source body's name as `organization`, the source listing page as
  `source_url`, and the official PDF/page as `notice_url`.
- `districts: ["West Bengal"]`, `qualifications: []`, `vacancies: null`.
- No application dates, exam date or `apply_url`.
- A fixed bilingual summary that says eligibility, vacancies and the last date
  were **not** checked for the card, and points to the original notice.

The app therefore shows a notice-only card: no deadline pill, no reminder, no
apply button. The detail page keeps only the summary, eligibility
(qualifications/district), official links, last verified and correction
sections.

## Builds that can show it

| Build | Selected by `lib/main.dart` | What the user sees |
|---|---|---|
| Android APK, no `test_feed_url` | `KarmopathApp` (foundation) | Placeholder screen |
| Android APK, `test_feed_url` = public feed | `ProductionBootstrap` | The configured feed (notice cards once published) |
| Web, no feed URL | `KarmopathPreviewApp` (demo) | Labelled sample data |
| Web, `KARMOPATH_FEED_URL` set | `ProductionBootstrap` | The configured feed |

For the production feed URL above, run *Build Android APK or AAB (Manual)* with
`format = apk` and:

```
test_feed_url = https://raw.githubusercontent.com/Keshab1997/karmopath/main/feed/jobs.json
```

AAB builds ignore `test_feed_url`. The URL is embedded in the binary and must
stay credential-free.

## Offline checks

```bash
python3 tools/feed/validate.py feed/jobs.json
(cd tools/feed && python3 check_publish.py ../../feed/jobs.json)
python3 -m unittest discover -s tests/ops -p "test_*.py"
python3 -m unittest discover -s tests/feed -p "test_validate.py"

# Proposals only: the preview must validate, and the issue text must round
# trip through the publisher's own parser (tests/ops/test_notice_proposals.py).
python3 tools/feed/validate.py docs/proposals/notice-only-batch-2026-10-20.preview.json
```

A pass proves structure and readiness signals only. It cannot establish that a
source is official or that a human checked dates and eligibility — that is the
label step.

## Adding a source

Add it to `ops/notice_sources.json` only after a human confirms the domain on
`docs/OFFICIAL_SOURCES.md`. A source that fails to load is reported as a
`notice-review` issue; it is never treated as "no new notices".

## Not covered here

- Production-feed approval beyond the per-notice label (owner decision).
- Play Store release, signing and privacy declarations.
- Device verification of reminders, which is covered by
  `docs/ANDROID_REMINDER_DEVICE_TEST_PLAN.md`.
