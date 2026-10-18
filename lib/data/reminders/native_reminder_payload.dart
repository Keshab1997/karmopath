import 'dart:convert';

import '../../contracts/native_reminders.dart';

class DecodedNativeReminderPayload {
  const DecodedNativeReminderPayload({
    required this.isManaged,
    required this.identity,
  });

  final bool isManaged;
  final NativeReminderIdentity? identity;
}

const _keys = {
  'namespace',
  'job_id',
  'due_at_utc',
  'closes_at_utc',
  'content_key',
  'payload_variant',
};

String encodeNativeReminderPayload(NativeReminderIdentity identity) =>
    jsonEncode({
      'namespace': reminderPayloadNamespace,
      'job_id': identity.jobId,
      'due_at_utc': identity.dueAtUtc.toUtc().toIso8601String(),
      'closes_at_utc': identity.closesAtUtc.toUtc().toIso8601String(),
      'content_key': identity.contentKey,
      'payload_variant': identity.payloadVariant,
    });

DecodedNativeReminderPayload decodeNativeReminderPayload(String? payload) {
  const foreign = DecodedNativeReminderPayload(
    isManaged: false,
    identity: null,
  );
  const malformed = DecodedNativeReminderPayload(
    isManaged: true,
    identity: null,
  );
  if (payload == null) return foreign;
  final Object? root;
  try {
    root = jsonDecode(payload);
  } on FormatException {
    return foreign;
  }
  if (root is! Map<String, dynamic> ||
      root['namespace'] != reminderPayloadNamespace) {
    return foreign;
  }
  final fields = root;
  if (fields.length != _keys.length ||
      !_keys.every((key) => fields[key] is String)) {
    return malformed;
  }
  final due = _parseUtc(root['due_at_utc'] as String);
  final closes = _parseUtc(root['closes_at_utc'] as String);
  if (due == null || closes == null) return malformed;
  try {
    return DecodedNativeReminderPayload(
      isManaged: true,
      identity: NativeReminderIdentity(
        jobId: root['job_id'] as String,
        dueAtUtc: due,
        closesAtUtc: closes,
        contentKey: root['content_key'] as String,
        payloadVariant: root['payload_variant'] as String,
      ),
    );
  } on ArgumentError {
    return malformed;
  }
}

// Reject offsets, missing zones and DateTime.parse's calendar overflow repair.
DateTime? _parseUtc(String text) {
  final match = RegExp(
    r'^([+-]?\d{4,6}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?Z$',
  ).firstMatch(text);
  if (match == null) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null || !parsed.isUtc) return null;
  final fraction = (match[2] ?? '').padRight(6, '0');
  final canonical = parsed.toIso8601String();
  final canonicalMatch = RegExp(r'^(.*)\.(\d+)Z$').firstMatch(canonical);
  if (canonicalMatch == null ||
      canonicalMatch[1] != match[1] ||
      canonicalMatch[2]!.padRight(6, '0') != fraction) {
    return null;
  }
  return parsed.toUtc();
}
