# Agent B — Batch 8 reminder payload codec

**Captain-issued assignment.** Branch: `agent/B/b8-payload-codec-20261018`  
**Immutable base:** `68808ee41485138c6a22db3ee012d60c7f644175`  
**Do not start until given this brief in your independent workspace.**

## Goal

Add a pure, strict JSON codec for `NativeReminderIdentity`. The current plugin boundary does not serialize the frozen namespace/identity contract; this helper will let the Captain add that adapter without workers touching Captain-owned app or Android files.

## Exact write allowlist — no other files

- `lib/data/reminders/native_reminder_payload.dart` — new pure codec.
- `test/data/reminders/native_reminder_payload_test.dart` — new focused tests; keep fakes local to the test.

Do not edit `lib/contracts/**`, `lib/app/**`, Android, `lib/main.dart`, existing content helpers, shared test helpers, fixtures, dependencies, workflows, or docs.

## Frozen API

```dart
class DecodedNativeReminderPayload {
  const DecodedNativeReminderPayload({
    required this.isManaged,
    required this.identity,
  });
  final bool isManaged;
  final NativeReminderIdentity? identity;
}

String encodeNativeReminderPayload(NativeReminderIdentity identity);
DecodedNativeReminderPayload decodeNativeReminderPayload(String? payload);
```

Use the existing `reminderPayloadNamespace` and `NativeReminderIdentity` from `lib/contracts/native_reminders.dart`; do not introduce a second identity model or change contract literals.

## Encoding and decoding rules

- Encoding produces one JSON object with exactly these keys: `namespace`, `job_id`, `due_at_utc`, `closes_at_utc`, `content_key`, `payload_variant`. Use the exact namespace constant; full job ID/content key/variant; UTC ISO-8601 timestamps ending in `Z`. Never include a platform notification ID, title/body, URI, or truncated/hash-derived job ID.
- Decoding returns `isManaged: true` only when a JSON object safely exposes the exact namespace. A matching namespace with missing/wrong fields, extra fields, invalid identity, non-UTC/bad timestamps, or invalid date ordering returns `isManaged: true, identity: null` (known but malformed payload).
- Null, non-JSON, non-object, missing/unreadable namespace, and every foreign namespace return `isManaged: false, identity: null`. Never guess that an undecodable payload belongs to this app.
- A valid payload must round-trip to full `NativeReminderIdentity` equality. Preserve values exactly except normalizing parsed instants to UTC. Do not parse or launch URLs.

## Required tests

Cover valid Bengali/English variants, long full IDs, Unicode content keys, UTC normalization, exact emitted key set, foreign namespace, invalid JSON/root, malformed known namespace, extra/missing fields, invalid job ID, empty content/variant, non-UTC timestamps, and `dueAtUtc >= closesAtUtc`. Tests must prove the decoder never invents identity or platform ID.

## Focused verification

```bash
flutter test test/data/reminders/native_reminder_payload_test.dart
python3 tool/preflight.py
```

If Flutter is unavailable, report **NOT RUN**. No analyze/full test/build/Gradle/CI.

## Handoff

Push only `agent/B/b8-payload-codec-20261018`, then provide the exact branch SHA and five-line Batch 8 report. The Captain alone wires this codec to the plugin.
