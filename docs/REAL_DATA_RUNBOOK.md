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
