import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/native_reminders.dart';
import 'package:karmopath/data/reminders/native_reminder_payload.dart';

NativeReminderIdentity identity(String variant) => NativeReminderIdentity(
  jobId: List.filled(100, 'a').join(),
  dueAtUtc: DateTime.parse('2026-10-18T10:00:00.123456+05:30'),
  closesAtUtc: DateTime.parse('2026-10-19T10:00:00.123456+05:30'),
  contentKey: '  বাংলা বিজ্ঞপ্তি। English 🔔 / https://example.org  ',
  payloadVariant: variant,
);

Map<String, dynamic> validPayload() =>
    jsonDecode(encodeNativeReminderPayload(identity('bn@reminder-v1')))
        as Map<String, dynamic>;

void expectMalformed(Map<String, dynamic> value) {
  final decoded = decodeNativeReminderPayload(jsonEncode(value));
  expect(decoded.isManaged, isTrue);
  expect(decoded.identity, isNull);
}

void main() {
  for (final variant in ['bn@reminder-v1', 'en@reminder-v1']) {
    test('$variant: exact keys, full values and UTC round trip', () {
      final original = identity(variant);
      final encoded = encodeNativeReminderPayload(original);
      final map = jsonDecode(encoded) as Map<String, dynamic>;
      expect(map.keys.toSet(), {
        'namespace',
        'job_id',
        'due_at_utc',
        'closes_at_utc',
        'content_key',
        'payload_variant',
      });
      expect(map['namespace'], reminderPayloadNamespace);
      expect(map['job_id'], original.jobId);
      expect((map['job_id'] as String).length, 100);
      expect(map['content_key'], original.contentKey);
      expect(map['payload_variant'], variant);
      expect(map['due_at_utc'], '2026-10-18T04:30:00.123456Z');
      expect(map['closes_at_utc'], '2026-10-19T04:30:00.123456Z');
      final decoded = decodeNativeReminderPayload(encoded);
      expect(decoded.isManaged, isTrue);
      expect(decoded.identity, original);
      expect(decoded.identity!.dueAtUtc.isUtc, isTrue);
      expect(decoded.identity!.closesAtUtc.isUtc, isTrue);
      expect(encodeNativeReminderPayload(decoded.identity!), encoded);
      expect(map.containsKey('platform_id'), isFalse);
    });
  }

  test('UTC timestamps without fractions normalize to the same instant', () {
    final map = validPayload()..['due_at_utc'] = '2026-10-18T04:30:00Z';
    final decoded = decodeNativeReminderPayload(jsonEncode(map));
    expect(decoded.isManaged, isTrue);
    expect(decoded.identity!.dueAtUtc, DateTime.utc(2026, 10, 18, 4, 30));
    expect(decoded.identity!.dueAtUtc.isUtc, isTrue);
  });

  test('unreadable and foreign roots never invent ownership or identity', () {
    for (final payload in <String?>[
      null,
      '',
      'not json',
      '{',
      'null',
      '[]',
      '42',
      'true',
      '"notice"',
      '{}',
      '{"namespace":null}',
      '{"namespace":3}',
      '{"namespace":[]}',
      '{"namespace":{}}',
      jsonEncode({...validPayload(), 'namespace': 'karmopath.reminder.v2'}),
      jsonEncode({...validPayload(), 'namespace': 'other'}),
      jsonEncode({
        ...validPayload(),
        'namespace': '$reminderPayloadNamespace ',
      }),
    ]) {
      final result = decodeNativeReminderPayload(payload);
      expect(result.isManaged, isFalse, reason: payload);
      expect(result.identity, isNull, reason: payload);
    }
  });

  test(
    'known namespace missing, extra and wrong-type fields are malformed',
    () {
      expectMalformed({'namespace': reminderPayloadNamespace});
      for (final key in validPayload().keys.where(
        (key) => key != 'namespace',
      )) {
        expectMalformed(validPayload()..remove(key));
        for (final bad in [null, 1, true, <Object>[], <String, Object>{}]) {
          expectMalformed(validPayload()..[key] = bad);
        }
      }
      for (final key in ['platform_id', 'title', 'body', 'uri', 'extra']) {
        expectMalformed(validPayload()..[key] = 123);
      }
    },
  );

  test('invalid identities never become guessed IDs or content', () {
    for (final id in [
      '',
      'UPPER',
      'has space',
      'https://example.org',
      List.filled(101, 'a').join(),
    ]) {
      expectMalformed(validPayload()..['job_id'] = id);
    }
    for (final key in ['content_key', 'payload_variant']) {
      for (final value in ['', '   ', '\n\t']) {
        expectMalformed(validPayload()..[key] = value);
      }
    }
  });

  test('non-UTC, invalid and overflow timestamps are rejected', () {
    for (final key in ['due_at_utc', 'closes_at_utc']) {
      for (final value in [
        '',
        'bad',
        '2026-10-18',
        '2026-10-18T04:30:00',
        '2026-10-18T04:30:00+00:00',
        '2026-10-18T10:00:00+05:30',
        '2026-02-30T04:30:00Z',
        '2026-13-18T04:30:00Z',
        '2026-10-18T24:30:00Z',
        '2026-10-18T04:60:00Z',
        '2026-10-18T04:30:60Z',
      ]) {
        expectMalformed(validPayload()..[key] = value);
      }
    }
  });

  test('equal or reversed deadlines are managed but have no identity', () {
    final equal = validPayload();
    equal['due_at_utc'] = equal['closes_at_utc'];
    expectMalformed(equal);
    expectMalformed(validPayload()..['due_at_utc'] = '2026-10-20T00:00:00Z');
  });
}
