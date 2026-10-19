# Showing real data in the app — runbook

Status: **not yet executed.** The code path below exists. The data step needs
a human who verifies each notice against its official source. No real feed is
published by this repository.

## Why the app shows no real data today

| Build | Selected by `lib/main.dart` | What the user sees |
|---|---|---|
| Android APK, no `test_feed_url` | `KarmopathApp` (foundation) | Placeholder screen |
| Android APK, `test_feed_url` = fixture | `ProductionBootstrap` | Invented TEST FIXTURE jobs only |
| Web, no feed URL | `KarmopathPreviewApp` (demo) | Labelled sample data |
| Web, `KARMOPATH_FEED_URL` set | `ProductionBootstrap` (after this change) | The configured feed |

## Steps

1. **Approve the source.** The owner names the official notice sources. Nothing
   is scraped or guessed. Each job needs `source_url`, `notice_url`,
   `reviewed_at` and a human check of dates and eligibility.
2. **Create the candidate feed.** Use `admin/index.html` (run locally). Fill both
   languages, then export as a candidate. Schema v1.
3. **Validate offline.**
   ```bash
   python3 tools/feed/validate.py feed.json
   python3 tools/feed/check_publish.py feed.json
   ```
   Both must exit 0. A pass proves structure only, not that a source is official.
4. **Publish at a public HTTPS URL** with no credentials, token or fragment.
   The host must answer HTTP 200 with `access-control-allow-origin: *` so the
   web build can read it. Check with `curl -I <url>`.
5. **Point the build at it.**
   - Android APK: run *Build Android APK or AAB (Manual)* with `test_feed_url`
     set to the public URL. AAB builds ignore this input.
   - Web: build with `--dart-define=KARMOPATH_FEED_URL=<url>`. The
     `Karmopath web preview (manual)` workflow does not accept dart-defines, so
     a web build with a real feed needs its own workflow or a local
     `flutter build web` run.
6. **Verify on a device** using `docs/ANDROID_REMINDER_DEVICE_TEST_PLAN.md`:
   fresh feed, empty feed, unavailable feed, offline, reboot, relaunch.
   Reminder delivery is only proven on a real device.

## Not covered here

- Choosing or contacting data sources.
- Production-feed approval (owner decision).
- Play Store release, signing and privacy declarations.
