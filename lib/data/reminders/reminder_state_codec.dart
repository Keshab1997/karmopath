/// Strict JSON codec for the reminder registry and applied-state ledger.
///
/// The whole document is encoded as **one** string and written as a
/// single-element string list, so a half-written registry can never be paired
/// with half-written applied metadata.
///
/// Decoding is deliberately unforgiving. A document produced by this codec
/// always round-trips; anything else raises [ReminderStateException] with a
/// precise [ReminderStateFailure], because a silently repaired ledger would
/// re-use or forget platform IDs that the OS may still be holding. There is no
/// migration and no auto-repair in this module — a captain decision, not a
/// convenience here.
library;

import 'dart:convert';

import 'reminder_state.dart';

/// Contract-shaped job IDs: lowercase slug, at most 100 characters.
final RegExp _jobIdPattern = RegExp(r'^[a-z0-9-]{1,100}$');

/// Encodes [state] as the single string the store writes.
String encodeReminderStateDocument(ReminderState state) {
  final document = <String, dynamic>{
    'schema_version': ReminderState.schemaVersion,
    'next_platform_id': state.nextPlatformId,
    'entries': <Map<String, dynamic>>[
      for (final entry in state.entries)
        <String, dynamic>{
          'job_id': entry.jobId,
          'platform_id': entry.platformId,
          'applied': entry.applied == null
              ? null
              : <String, dynamic>{
                  'due_at': _encodeInstant(entry.applied!.dueAtUtc),
                  'closes_at': _encodeInstant(entry.applied!.closesAtUtc),
                  'content_key': entry.applied!.contentKey,
                  'payload_variant': entry.applied!.payloadVariant,
                },
        },
    ],
  };
  return jsonEncode(document);
}

/// Decodes the stored value.
///
/// `null` — the key was never written — is the only value that means "empty".
/// Every other deviation from this codec's own output is an error:
///
///  * an empty list, more than one element, or an empty string -> [corrupt];
///  * invalid JSON or a non-object root -> [corrupt];
///  * `schema_version` missing, not an integer, or not [ReminderState.schemaVersion]
///    -> [unknownSchema];
///  * wrong field types, an unknown/misspelled job ID shape, an out-of-range
///    platform ID, a bad instant, or `due >= closes` -> [corrupt];
///  * duplicate platform IDs, duplicate job IDs, or an allocated ID not below
///    `next_platform_id` -> [inconsistent].
///
/// Unknown *extra* keys are tolerated so a future additive field can be read by
/// an older build without pretending the document is empty; unknown schema
/// versions are not.
ReminderState decodeReminderStateDocument(List<String>? stored) {
  if (stored == null) return ReminderState.empty();
  if (stored.length != 1) {
    throw ReminderStateException(
      ReminderStateFailure.corrupt,
      'expected exactly one stored document, found ${stored.length}',
    );
  }
  final raw = stored.single;
  if (raw.trim().isEmpty) {
    throw const ReminderStateException(
      ReminderStateFailure.corrupt,
      'stored document is empty',
    );
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (error) {
    throw ReminderStateException(
      ReminderStateFailure.corrupt,
      'stored document is not valid JSON: ${error.message}',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw const ReminderStateException(
      ReminderStateFailure.corrupt,
      'stored document root is not an object',
    );
  }

  final version = decoded['schema_version'];
  if (version is! int || version != ReminderState.schemaVersion) {
    throw ReminderStateException(
      ReminderStateFailure.unknownSchema,
      'unsupported schema_version ${version ?? '(missing)'}; '
      'this build reads ${ReminderState.schemaVersion}',
    );
  }

  final nextPlatformId = decoded['next_platform_id'];
  if (nextPlatformId is! int ||
      nextPlatformId < firstPlatformId ||
      nextPlatformId > maxPlatformId + 1) {
    throw ReminderStateException(
      ReminderStateFailure.corrupt,
      'invalid next_platform_id $nextPlatformId',
    );
  }

  final rawEntries = decoded['entries'];
  if (rawEntries is! List) {
    throw const ReminderStateException(
      ReminderStateFailure.corrupt,
      'entries is not a list',
    );
  }

  final entries = <ReminderRegistryEntry>[
    for (var i = 0; i < rawEntries.length; i++)
      _decodeEntry(rawEntries[i], index: i),
  ];

  // The constructor re-checks uniqueness, ranges and the allocator invariant,
  // so both the codec and any hand-built state share one source of truth.
  try {
    return ReminderState(nextPlatformId: nextPlatformId, entries: entries);
  } on ReminderStateException {
    rethrow;
  } catch (error) {
    throw ReminderStateException(
      ReminderStateFailure.inconsistent,
      'inconsistent registry: $error',
    );
  }
}

ReminderRegistryEntry _decodeEntry(Object? raw, {required int index}) {
  if (raw is! Map<String, dynamic>) {
    throw ReminderStateException(
      ReminderStateFailure.corrupt,
      'entry $index is not an object',
    );
  }
  final jobId = raw['job_id'];
  if (jobId is! String || !_jobIdPattern.hasMatch(jobId)) {
    throw ReminderStateException(
      ReminderStateFailure.corrupt,
      'entry $index has an invalid job_id',
    );
  }
  final platformId = raw['platform_id'];
  if (platformId is! int ||
      platformId < firstPlatformId ||
      platformId > maxPlatformId) {
    throw ReminderStateException(
      ReminderStateFailure.corrupt,
      'entry $jobId has an out-of-range platform_id',
    );
  }
  if (!raw.containsKey('applied')) {
    throw ReminderStateException(
      ReminderStateFailure.corrupt,
      'entry $jobId has no applied key',
    );
  }
  final appliedRaw = raw['applied'];
  return ReminderRegistryEntry(
    jobId: jobId,
    platformId: platformId,
    applied: appliedRaw == null
        ? null
        : _decodeApplied(appliedRaw, jobId: jobId),
  );
}

AppliedReminder _decodeApplied(Object raw, {required String jobId}) {
  if (raw is! Map<String, dynamic>) {
    throw ReminderStateException(
      ReminderStateFailure.corrupt,
      'applied metadata for $jobId is not an object',
    );
  }
  final dueAt = _decodeInstant(raw['due_at'], jobId: jobId, field: 'due_at');
  final closesAt = _decodeInstant(
    raw['closes_at'],
    jobId: jobId,
    field: 'closes_at',
  );
  final contentKey = raw['content_key'];
  final payloadVariant = raw['payload_variant'];
  if (contentKey is! String || contentKey.trim().isEmpty) {
    throw ReminderStateException(
      ReminderStateFailure.corrupt,
      'applied metadata for $jobId has an invalid content_key',
    );
  }
  if (payloadVariant is! String || payloadVariant.trim().isEmpty) {
    throw ReminderStateException(
      ReminderStateFailure.corrupt,
      'applied metadata for $jobId has an invalid payload_variant',
    );
  }
  try {
    return AppliedReminder(
      dueAtUtc: dueAt,
      closesAtUtc: closesAt,
      contentKey: contentKey,
      payloadVariant: payloadVariant,
    );
  } on ReminderStateException catch (error) {
    throw ReminderStateException(
      ReminderStateFailure.corrupt,
      'applied metadata for $jobId is invalid: ${error.message}',
    );
  }
}

/// UTC instants are stored the way the feed contract stores them: ISO-8601
/// with an explicit `Z`. A value without the suffix is rejected even though
/// `DateTime.parse` would accept it, because a local time in a durable ledger
/// changes meaning on a device whose timezone moved.
DateTime _decodeInstant(
  Object? raw, {
  required String jobId,
  required String field,
}) {
  if (raw is! String || !raw.endsWith('Z')) {
    throw ReminderStateException(
      ReminderStateFailure.corrupt,
      'applied $field for $jobId is not a UTC timestamp',
    );
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw ReminderStateException(
      ReminderStateFailure.corrupt,
      'applied $field for $jobId is not a valid timestamp',
    );
  }
  return parsed.toUtc();
}

String _encodeInstant(DateTime value) => value.toUtc().toIso8601String();
