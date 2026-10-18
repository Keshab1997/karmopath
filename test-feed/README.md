# Test feed fixtures (NON-PRODUCTION)

Sanitized, obviously-synthetic fixtures for the Android reminder device plan
(`docs/ANDROID_REMINDER_DEVICE_TEST_PLAN.md`).

**These are not a production feed.** Every job is invented, every URL points at
`example.org`, and nothing here is an official notice. They exist only so the
device cases can be executed against real JSON instead of a mock.

## Files

| File | Serves | What it is |
|---|---|---|
| `jobs.json` | S-01, S-02, T-01, T-02, L-01…L-04, Z-01, D-01 | Two open recruitment jobs with future deadlines. Two are needed so S-01 can prove per-ID cancellation leaves the other reminder alone. |
| `jobs-empty.json` | F-02 | A *successfully loaded* feed with `"jobs": []`. |
| *(no file)* | F-01, F-03 | **Unavailable** is a transport outcome, not a payload — see [Unavailable](#unavailable-f-01). |

Both files pass the repository's own offline validator:

```bash
python3 tools/feed/validate.py test-feed/jobs.json        # VALID, 2 job(s)
python3 tools/feed/validate.py test-feed/jobs-empty.json  # VALID, 0 job(s)
```

The validator checks structure and timestamps only. It cannot establish that a
source is official, and it is not evidence that a device test ran.

## Hosted at

Published as a public GitHub Gist on 2026-10-19:
<https://gist.github.com/Keshab1997/edc4a209179e87f925ed519529c772d1>

| Variant | URL | Case |
|---|---|---|
| two open jobs | `https://gist.githubusercontent.com/Keshab1997/edc4a209179e87f925ed519529c772d1/raw/jobs.json` | approved test feed |
| successful empty | `https://gist.githubusercontent.com/Keshab1997/edc4a209179e87f925ed519529c772d1/raw/jobs-empty.json` | F-02 |
| unavailable | `https://gist.githubusercontent.com/Keshab1997/edc4a209179e87f925ed519529c772d1/raw/does-not-exist.json` | F-01 |

The unpinned `/raw/<file>` form is deliberate — it keeps serving the current
revision, so a job id or date can be corrected without changing the configured
URL. A revision-pinned URL (`/raw/<sha>/<file>`) also works, but on this host a
*pinned* URL with an unknown filename answers 200 with the gist's first file
instead of 404. So use the unpinned form for the unavailable case, never the
pinned one.

Verified 2026-10-19: both feed URLs answer HTTP 200 with
`access-control-allow-origin: *`, the downloaded bytes are byte-identical to
these files and pass `tools/feed/validate.py`, and the unavailable URL answers
HTTP 404.

## Unavailable (F-01)

There is no "null feed" file to host. `HttpFeedTransport` raises
`FeedTransportException` on any non-200 answer
(`lib/data/platform/http_feed_transport.dart`), and `CachedJobRepository` then
keeps the last good cache, reporting `isOffline` plus a user-safe `lastError`.
Use the 404 URL above, or disconnect the network (F-03).

## Stable identity

| Job | id | closes |
|---|---|---|
| A | `test-open-a-2026` | 2026-12-31 |
| B | `test-open-b-2026` | 2027-01-31 |

The ids are stable on purpose: `docs/CONTRACTS.md` explains that reminder
identity is keyed by job id, and S-02 asserts the *same* reserved id is reused
when the language changes. Renaming a job between cases breaks that assertion.

Dates are date-only (`application_end_date`), so the close instant is the end of
that day in Asia/Kolkata, not UTC midnight.

## Reminder timing

`reminderLeadTime` is 24 hours (`lib/data/reminders/reminder_plan.dart`), and the
reminder fires at `closesAt - 24h`. For job A that is 2026-12-30T18:30:00Z.

Consequences for the plan:

- **D-01** (observing a real notification) needs a ~24-hour wait at the fixture's
  spacing. Do not shorten the interval to make it faster — the plan forbids it.
- **F-04** (late opt-in must not catch up) needs a job whose reminder instant has
  already passed while its close instant is still future — i.e. a close less than
  24 hours away. No static date satisfies that, so create it at the time: edit
  `application_end_date` to tomorrow's date in the gist, or use
  `application_end_at` for an exact close instant. Mark F-04 `BLOCKED` if neither
  is available, as the plan itself instructs.

## Credentials

The app requires a credential-free public HTTPS URL
(`lib/app/runtime/feed_configuration.dart` rejects anything else, and
`lib/data/platform/http_feed_transport.dart` rejects embedded credentials).
Never use a URL with `user:pass@` or a token query parameter — neither the config
parser nor the build workflow can consume one, so it fails outright rather than
degrading.

## Status

The fixtures are published to the gist above for device testing only. This is
**not** the production feed and must never be swapped in at the production URL.
The owner's approval sentence for this test feed belongs in
`docs/ANDROID_REMINDER_DEVICE_TEST_PLAN.md`, not here. No production activation,
build, or device run is authorized by this directory.

Separately: a working feed URL is not by itself enough to run the device cases.
`createNativeRuntime()` (`lib/app/runtime/native_runtime_factory.dart`) is still
not called from `lib/main.dart`, so the native reminder entrypoint is not active
in any build.
