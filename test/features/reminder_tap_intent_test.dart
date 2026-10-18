import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/features/common/reminder_tap_intent.dart';

void main() {
  final fullLengthId = 'n${List.filled(10, 'notice123').join('-')}';
  final validIds = [
    'a',
    '0',
    '-',
    'wb-teacher-2026',
    '-job--123-',
    'abcdefghijklmnopqrstuvwxyz0123456789-',
    fullLengthId,
  ];
  final invalidIds = <String?>[
    null,
    '',
    List.filled(101, 'a').join(),
    '$fullLengthId-extra',
    'Job-123',
    ' job-123',
    'job-123 ',
    'job 123',
    '\tjob-123',
    'job-123\n',
    'job-123\r\n',
    'job\n123',
    'job\t123',
    'job_123',
    'job.123',
    '/jobs/job-123',
    'https://example.com/jobs/job-123',
    'karmopath://jobs/job-123',
    'job-123?source=tap',
    'job-123#details',
    'job%2d123',
    'চাকরি-123',
    'jób-123',
    'job–123',
    'job-１２３',
    'job-123\u0000',
    'job-123\u200b',
    'job-123\u2028',
  ];

  test('accepts full valid IDs unchanged, including the 100-character limit', () {
    expect(fullLengthId.length, 100);
    for (final id in validIds) {
      final queue = ReminderTapIntentQueue();
      expect(queue.accept(id), isTrue);
      expect(queue.hasPending, isTrue);
      expect(queue.pendingJobId, id);
      expect(queue.consume(navigationReady: true), id);
      expect(queue.hasPending, isFalse);
      expect(queue.pendingJobId, isNull);
    }
  });

  test('rejects null and invalid input without creating an intent', () {
    final queue = ReminderTapIntentQueue();
    for (final id in invalidIds) {
      expect(queue.accept(id), isFalse, reason: 'candidate: $id');
      expect(queue.hasPending, isFalse);
      expect(queue.pendingJobId, isNull);
      expect(queue.consume(navigationReady: true), isNull);
    }
  });

  test('latest valid tap replaces the previous pending tap', () {
    final queue = ReminderTapIntentQueue();
    expect(queue.accept('first-job'), isTrue);
    expect(queue.accept('second-job'), isTrue);
    expect(queue.accept(fullLengthId), isTrue);
    expect(queue.hasPending, isTrue);
    expect(queue.pendingJobId, fullLengthId);
    expect(queue.consume(navigationReady: true), fullLengthId);
    expect(queue.consume(navigationReady: true), isNull);
  });

  test('every invalid candidate preserves an earlier valid intent', () {
    final queue = ReminderTapIntentQueue();
    expect(queue.accept(fullLengthId), isTrue);
    for (final id in invalidIds) {
      expect(queue.accept(id), isFalse, reason: 'candidate: $id');
      expect(queue.hasPending, isTrue);
      expect(queue.pendingJobId, fullLengthId);
    }
    expect(queue.consume(navigationReady: true), fullLengthId);
  });

  test('navigation not ready retains the pending ID across repeated calls', () {
    final queue = ReminderTapIntentQueue();
    queue.accept(fullLengthId);
    for (var i = 0; i < 3; i++) {
      expect(queue.consume(navigationReady: false), isNull);
      expect(queue.hasPending, isTrue);
      expect(queue.pendingJobId, fullLengthId);
    }
    expect(queue.consume(navigationReady: true), fullLengthId);
  });

  test('ready consume returns the ID once and allows a later tap', () {
    final queue = ReminderTapIntentQueue();
    queue.accept('job-123');
    expect(queue.consume(navigationReady: true), 'job-123');
    expect(queue.hasPending, isFalse);
    expect(queue.pendingJobId, isNull);
    expect(queue.consume(navigationReady: false), isNull);
    expect(queue.consume(navigationReady: true), isNull);
    expect(queue.accept('job-123'), isTrue);
    expect(queue.consume(navigationReady: true), 'job-123');
  });

  test('empty queue has no pending value regardless of navigation readiness', () {
    final queue = ReminderTapIntentQueue();
    expect(queue.hasPending, isFalse);
    expect(queue.pendingJobId, isNull);
    expect(queue.consume(navigationReady: false), isNull);
    expect(queue.consume(navigationReady: true), isNull);
    expect(queue.hasPending, isFalse);
    expect(queue.pendingJobId, isNull);
  });

  test('clear is idempotent on empty and populated queues', () {
    final queue = ReminderTapIntentQueue();
    queue.clear();
    queue.clear();
    expect(queue.hasPending, isFalse);
    expect(queue.pendingJobId, isNull);
    queue.accept('first-job');
    queue.clear();
    queue.clear();
    expect(queue.hasPending, isFalse);
    expect(queue.pendingJobId, isNull);
    expect(queue.consume(navigationReady: true), isNull);
    expect(queue.accept('next-job'), isTrue);
    expect(queue.consume(navigationReady: true), 'next-job');
  });

  test('queue instances do not share pending state', () {
    final first = ReminderTapIntentQueue();
    final second = ReminderTapIntentQueue();
    first.accept('first-job');
    expect(second.hasPending, isFalse);
    expect(second.pendingJobId, isNull);
    second.accept('second-job');
    first.clear();
    expect(second.consume(navigationReady: true), 'second-job');
    expect(first.consume(navigationReady: true), isNull);
  });
}
