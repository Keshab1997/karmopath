# Contract v1 — freeze before worker dispatch
Captain has implemented `lib/contracts/job.dart`, `job_feed.dart`, `job_repository.dart`, `user_preferences.dart` and `app_actions.dart` in foundation. Plain immutable Dart models; no generated files. JSON keys snake_case. Date-only values YYYY-MM-DD use Asia/Kolkata calendar semantics; timestamps ISO8601 UTC with Z. Last date is inclusive unless exact official closing timestamp is supplied; display unknown closing time without inventing one.

## JSON
Envelope: schema_version (integer 1), updated_at (UTC string), jobs (array).
Job required fields:
- id: unique stable lowercase slug, [a-z0-9-], max 100; never derived from mutable title alone
- kind: recruitment | result | admit_card
- title_bn, title_en: nonempty strings
- organization: nonempty display string, not affiliation claim
- category: police | railway | banking | teaching | medical | office | other
- districts: array of nonempty strings; statewide uses literal West Bengal
- qualifications: array of nonempty strings; no guessed equivalence
- status: open | closed | withdrawn | published (published for result/admit_card)
- source_url: HTTPS official page URL; notice_url: HTTPS original notice URL
- reviewed_at, published_at, updated_at: UTC timestamps
- summary_bn, summary_en: nonempty original factual summaries
- how_to_apply_bn, how_to_apply_en: strings; may be empty for non-recruitment
Nullable required keys: vacancies (nonnegative integer or null), application_start_date, application_end_date (date or null), application_end_at (UTC timestamp or null), exam_date (date or null), apply_url (HTTPS URL or null), age_note_bn, age_note_en (string or null).
Source URLs must be reviewed as genuinely official; .org/.in alone is neither proof nor rejection. No HTML/scripts in text. Unknown enum/schema version fails feed load. Invalid job fails whole candidate feed, retains last good cache. IDs unique. updated_at >= published_at; reviewed_at <= updated_at. No future reviewed/published timestamps beyond documented clock tolerance of 5 minutes. Date ordering must be valid. Open recruitment requires application_end_date; unknown deadline remains draft. Result/admit_card must not claim open application status.

## Dart surface (exact signatures)
`enum JobKind { recruitment, result, admitCard }`
`enum JobCategory { police, railway, banking, teaching, medical, office, other }`
`enum JobStatus { open, closed, withdrawn, published }`
`Job` has final camelCase equivalents of all JSON fields; dates represented as nullable String for date-only, UTC DateTime for timestamps; factories `Job.fromJson(Map<String,dynamic> json)` and `Map<String,dynamic> toJson()`; malformed input throws FormatException.
`JobFeed`: schemaVersion int, updatedAt DateTime, jobs List<Job>; same JSON methods.
`JobFeedState`: feed JobFeed?, isLoading bool, isOffline bool, lastError String?; lastError must be user-safe.
`abstract class JobRepository { ValueListenable<JobFeedState> get state; Future<void> refresh(); Future<void> dispose(); }`
`abstract class UserPreferences { ValueListenable<Set<String>> get savedJobIds; ValueListenable<Set<String>> get reminderJobIds; Future<void> setSaved(String jobId, bool saved); Future<void> setReminder(String jobId, bool enabled); }`
`abstract class AppActions { Future<void> openExternal(Uri uri); Future<bool> requestReminderPermission(); }`
B screen constructors:
`HomeScreen({super.key, required JobRepository repository, required UserPreferences preferences, required void Function(String) onOpenJob})`
`JobDetailScreen({super.key, required Job job, required UserPreferences preferences, required AppActions actions})`
`SavedScreen` and `CalendarScreen`: same constructor arguments as HomeScreen.
`SettingsScreen({super.key, required AppActions actions})`.
Captain wires routes and production notification behavior. B requests permission through actions before enabling reminder; preferences persists intent, captain schedules/cancels notifications. IDs may survive feed refresh; missing jobs show unavailable rather than crash.

A concrete adapters: `FeedTransport.fetch(): Future<String>` in lib/data/feed_transport.dart; `FeedCache.read(): Future<String?>` and `write(String raw): Future<void>` in lib/data/feed_cache.dart. `CachedJobRepository({required FeedTransport transport, required FeedCache cache})` implements JobRepository and `LocalUserPreferences({required PreferencesStore store})`; PreferencesStore has `readStrings(String key): Future<List<String>?>`, `writeStrings(String key,List<String> values): Future<void>`. Add async `initialize()` on LocalUserPreferences before UI composition. Captain supplies concrete HTTP/files/preferences adapters. Versioned keys karmopath.saved.v1 and karmopath.reminders.v1. No new dependency required in A code.

Python validator uses exactly the same schema and fixtures. Cross-language contract fixtures are captain-owned after integration. Any needed signature change goes to captain first, never silently renamed.

## Foundation implementation notes
Schema parser is in job.dart/job_feed.dart; use it in Dart rather than duplicating validation. Sample-only fixture is test/fixtures/sample_feed.json, deliberately example.org and NOT publishable. Validator schema success cannot establish an official source: human source verification remains separate. Screen names and import paths are specified in B brief. A owns creation of its own transport/cache/store abstract files under lib/data; captain owns their eventual platform implementations under lib/app. No notification scheduling backend is wired yet.

## Batch 2 — concrete platform adapters (supersedes earlier lib/app location)
Captain approved worker A to implement concrete adapters under `lib/data/platform/**`; app composition/lifecycle stays captain-owned in lib/app. Dependencies pinned by captain: http ^1.6.0, shared_preferences ^2.5.6. No worker edits pubspec/lock.

- `lib/data/platform/http_feed_transport.dart`: `HttpFeedTransport({required Uri feedUrl, required http.Client client, Duration timeout = const Duration(seconds: 20), int maxBytes = 2097152}) implements FeedTransport`. The caller owns and closes the injected client. Public HTTPS only, no embedded credentials or auth headers. No production URL hardcoded.
- `lib/data/platform/preferences_feed_cache.dart`: `PreferencesFeedCache({required SharedPreferencesAsync preferences}) implements FeedCache`; string key literal `karmopath.feed.v1`.
- `lib/data/platform/shared_preferences_store.dart`: `SharedPreferencesStore({required SharedPreferencesAsync preferences}) implements PreferencesStore`; use existing saved/reminder versioned keys supplied to readStrings/writeStrings, never clear unrelated settings.

HTTP transport checks 200 status, enforces configured byte limit against both declared and streamed size, rejects malformed UTF-8 and exposes errors to repository (not UI). Total fetch timeout, no automatic unbounded retries; test resource cleanup and document browser differences. Validation remains JobFeed.fromJson in repository; transport must not trust JSON. Cache/storage errors propagate; preferences setters await successful persistence. Production feed URL and CORS are owner/captain deployment gates, not permission to publish a feed now.
