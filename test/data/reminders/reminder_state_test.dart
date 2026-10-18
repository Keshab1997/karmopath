import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/data/preferences_store.dart';
import 'package:karmopath/data/reminders/reminder_plan.dart';
import 'package:karmopath/data/reminders/reminder_state.dart';
import 'package:karmopath/data/reminders/reminder_state_codec.dart';
import 'package:karmopath/data/reminders/reminder_state_store.dart';

/// Deterministic [PreferencesStore] for the ledger.
///
/// * [backing] is shared by reference, so two stores over the same map model a
///   process restart without copying anything.
/// * [readError] / [writeError] inject platform failures on demand.
/// * [writeGate] holds a write open so concurrency and "write in flight" paths
///   are testable without timers.
class LedgerFakeStore implements PreferencesStore {
  LedgerFakeStore({Map<String, List<String>>? backing})
    : backing = backing ?? <String, List<String>>{};

  final Map<String, List<String>> backing;
  Object? readError;
  Object? writeError;
  Future<void>? writeGate;
  int reads = 0;
  int writes = 0;
  final List<String> writtenKeys = [];
  final List<List<String>> writtenValues = [];

  @override
  Future<List<String>?> readStrings(String key) async {
    reads++;
    final failure = readError;
    if (failure != null) throw failure;
    final value = backing[key];
    return value == null ? null : List<String>.of(value);
  }

  @override
  Future<void> writeStrings(String key, List<String> values) async {
    writes++;
    writtenKeys.add(key);
    writtenValues.add(List<String>.of(values));
    final failure = writeError;
    if (failure != null) throw failure;
    final gate = writeGate;
    if (gate != null) await gate;
    backing[key] = List<String>.of(values);
  }
}

DateTime utc(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min);

ReminderPlanEntry entryFor(
  String jobId, {
  DateTime? due,
  DateTime? closes,
  String contentKey = 'key-v1',
}) => ReminderPlanEntry(
  jobId: jobId,
  dueAtUtc: due ?? utc(2026, 11, 19, 12),
  closesAtUtc: closes ?? utc(2026, 11, 20, 12),
  contentKey: contentKey,
);

/// The stored document as decoded JSON, for assertions that must not depend on
/// the store's own parsing.
Map<String, dynamic> storedDocument(LedgerFakeStore store) =>
    jsonDecode(store.backing[ReminderStateStore.storageKey]!.single)
        as Map<String, dynamic>;

void main() {
  group('absence and loading', () {
    test('an absent key is an empty state, not an error', () async {
      final store = LedgerFakeStore();
      final ledger = ReminderStateStore(store: store);

      await ledger.initialize();

      expect(ledger.snapshot.isEmpty, isTrue);
      expect(ledger.snapshot.entries, isEmpty);
      expect(ledger.snapshot.nextPlatformId, firstPlatformId);
      expect(ledger.isInitialized, isTrue);
      expect(store.writes, 0, reason: 'loading must never write');
      ledger.dispose();
    });

    test('initialize is idempotent and reads once', () async {
      final store = LedgerFakeStore();
      final ledger = ReminderStateStore(store: store);

      await ledger.initialize();
      await ledger.initialize();

      expect(store.reads, 1);
      ledger.dispose();
    });

    test(
      'a read failure is explicit, leaves the snapshot empty and retries',
      () async {
        final store = LedgerFakeStore()
          ..readError = StateError('platform channel unavailable');
        final ledger = ReminderStateStore(store: store);

        await expectLater(
          ledger.initialize(),
          throwsA(
            isA<ReminderStateException>().having(
              (e) => e.failure,
              'failure',
              ReminderStateFailure.unreadable,
            ),
          ),
        );
        expect(ledger.isInitialized, isFalse);
        expect(ledger.snapshot.isEmpty, isTrue);

        store.readError = null;
        await ledger.initialize();
        expect(ledger.isInitialized, isTrue);
        ledger.dispose();
      },
    );

    test(
      'a mutation refuses to run while the document is unreadable',
      () async {
        final store = LedgerFakeStore(
          backing: {
            ReminderStateStore.storageKey: ['{"schema_version":1}'],
          },
        )..readError = StateError('io error');
        final ledger = ReminderStateStore(store: store);

        await expectLater(
          ledger.reserve('a-job'),
          throwsA(isA<ReminderStateException>()),
        );
        expect(store.writes, 0, reason: 'unreadable data is never overwritten');
        ledger.dispose();
      },
    );
  });

  group('strict codec', () {
    test('round-trips through one stored string', () async {
      final store = LedgerFakeStore();
      final ledger = ReminderStateStore(store: store);
      await ledger.initialize();
      await ledger.reserve('a-job');

      expect(store.writtenValues.single, hasLength(1));
      expect(storedDocument(store)['schema_version'], 1);
      ledger.dispose();
    });

    test('an unknown schema version is refused, not reset', () async {
      final store = LedgerFakeStore(
        backing: {
          ReminderStateStore.storageKey: [
            '{"schema_version":2,"next_platform_id":1,"entries":[]}',
          ],
        },
      );
      final ledger = ReminderStateStore(store: store);

      await expectLater(
        ledger.initialize(),
        throwsA(
          isA<ReminderStateException>().having(
            (e) => e.failure,
            'failure',
            ReminderStateFailure.unknownSchema,
          ),
        ),
      );
      await expectLater(
        ledger.reserve('a-job'),
        throwsA(isA<ReminderStateException>()),
      );
      expect(store.writes, 0);
      expect(
        store.backing[ReminderStateStore.storageKey]!.single,
        contains('"schema_version":2'),
        reason: 'an unreadable document is never overwritten',
      );
      ledger.dispose();
    });

    test(
      'malformed JSON, empty strings and multi-element lists are corrupt',
      () async {
        for (final bad in <List<String>>[
          ['not json'],
          [''],
          ['   '],
          <String>[],
          ['{"schema_version":1,"next_platform_id":1,"entries":[]}', 'extra'],
          ['[]'],
        ]) {
          await expectLater(
            () async => decodeReminderStateDocument(bad),
            throwsA(
              isA<ReminderStateException>().having(
                (e) => e.failure,
                'failure',
                ReminderStateFailure.corrupt,
              ),
            ),
            reason: 'value $bad',
          );
        }
      },
    );

    test(
      'structurally valid but semantically broken documents are corrupt',
      () {
        final cases = <String, String>{
          'entries not a list':
              '{"schema_version":1,"next_platform_id":1,"entries":42}',
          'entry not an object':
              '{"schema_version":1,"next_platform_id":2,"entries":[7]}',
          'bad job id': '{"schema_version":1,"next_platform_id":2,"entries":[{"job_id":"Bad ID","platform_id":1,"applied":null}]}',
          'platform id zero': '{"schema_version":1,"next_platform_id":2,"entries":[{"job_id":"a-job","platform_id":0,"applied":null}]}',
          'platform id too large': '{"schema_version":1,"next_platform_id":2,"entries":[{"job_id":"a-job","platform_id":2147483648,"applied":null}]}',
          'platform id not an int': '{"schema_version":1,"next_platform_id":2,"entries":[{"job_id":"a-job","platform_id":"1","applied":null}]}',
          'missing applied key': '{"schema_version":1,"next_platform_id":2,"entries":[{"job_id":"a-job","platform_id":1}]}',
          'applied not an object': '{"schema_version":1,"next_platform_id":2,"entries":[{"job_id":"a-job","platform_id":1,"applied":"yes"}]}',
          'local timestamp': '{"schema_version":1,"next_platform_id":2,"entries":[{"job_id":"a-job","platform_id":1,"applied":{"due_at":"2026-11-19T12:00:00","closes_at":"2026-11-20T12:00:00Z","content_key":"k","payload_variant":"v"}}]}',
          'due not before closes': '{"schema_version":1,"next_platform_id":2,"entries":[{"job_id":"a-job","platform_id":1,"applied":{"due_at":"2026-11-20T12:00:00.000Z","closes_at":"2026-11-20T12:00:00.000Z","content_key":"k","payload_variant":"v"}}]}',
          'empty content key': '{"schema_version":1,"next_platform_id":2,"entries":[{"job_id":"a-job","platform_id":1,"applied":{"due_at":"2026-11-19T12:00:00.000Z","closes_at":"2026-11-20T12:00:00.000Z","content_key":" ","payload_variant":"v"}}]}',
          'empty variant': '{"schema_version":1,"next_platform_id":2,"entries":[{"job_id":"a-job","platform_id":1,"applied":{"due_at":"2026-11-19T12:00:00.000Z","closes_at":"2026-11-20T12:00:00.000Z","content_key":"k","payload_variant":""}}]}',
        };
        for (final entry in cases.entries) {
          expect(
            () => decodeReminderStateDocument([entry.value]),
            throwsA(
              isA<ReminderStateException>().having(
                (e) => e.failure,
                'failure',
                ReminderStateFailure.corrupt,
              ),
            ),
            reason: entry.key,
          );
        }
      },
    );

    test('duplicate platform IDs are inconsistent, not silently tolerated', () {
      const document =
          '{"schema_version":1,"next_platform_id":3,"entries":['
          '{"job_id":"a-job","platform_id":1,"applied":null},'
          '{"job_id":"b-job","platform_id":1,"applied":null}]}';

      expect(
        () => decodeReminderStateDocument([document]),
        throwsA(
          isA<ReminderStateException>().having(
            (e) => e.failure,
            'failure',
            ReminderStateFailure.inconsistent,
          ),
        ),
      );
    });

    test('an allocated id that is not below the counter is inconsistent', () {
      const document =
          '{"schema_version":1,"next_platform_id":2,"entries":['
          '{"job_id":"a-job","platform_id":2,"applied":null}]}';

      expect(
        () => decodeReminderStateDocument([document]),
        throwsA(
          isA<ReminderStateException>().having(
            (e) => e.failure,
            'failure',
            ReminderStateFailure.inconsistent,
          ),
        ),
      );
    });

    test('a null value means empty; an encoded empty state round-trips', () {
      expect(decodeReminderStateDocument(null).isEmpty, isTrue);

      final empty = ReminderState.empty();
      final decoded = decodeReminderStateDocument([
        encodeReminderStateDocument(empty),
      ]);
      expect(decoded.isEmpty, isTrue);
      expect(decoded.nextPlatformId, firstPlatformId);
    });
  });

  group('allocation', () {
    test('ids start at 1 and increase monotonically', () async {
      final store = LedgerFakeStore();
      final ledger = ReminderStateStore(store: store);

      final first = await ledger.reserve('a-job');
      final second = await ledger.reserve('b-job');
      final third = await ledger.reserve('c-job');

      expect(first.platformId, 1);
      expect(second.platformId, 2);
      expect(third.platformId, 3);
      expect(first.jobId, 'a-job');
      ledger.dispose();
    });

    test(
      'the same job keeps its id, and a repeat reservation writes nothing',
      () async {
        final store = LedgerFakeStore();
        final ledger = ReminderStateStore(store: store);

        final first = await ledger.reserve('a-job');
        final writes = store.writes;
        final again = await ledger.reserve('a-job');

        expect(again.platformId, first.platformId);
        expect(store.writes, writes, reason: 'a stable id needs no rewrite');
        ledger.dispose();
      },
    );

    test('the reservation is persisted before it is returned', () async {
      final store = LedgerFakeStore();
      final ledger = ReminderStateStore(store: store);

      final reservation = await ledger.reserve('a-job');

      expect(store.backing, isNotEmpty);
      expect(
        decodeReminderStateDocument(
          store.backing[ReminderStateStore.storageKey],
        ).platformIdFor('a-job'),
        reservation.platformId,
      );
      ledger.dispose();
    });

    test(
      'a failed write allocates nothing and leaves the snapshot unchanged',
      () async {
        final store = LedgerFakeStore()..writeError = StateError('disk full');
        final ledger = ReminderStateStore(store: store);

        await expectLater(
          ledger.reserve('a-job'),
          throwsA(
            isA<ReminderStateException>().having(
              (e) => e.failure,
              'failure',
              ReminderStateFailure.storage,
            ),
          ),
        );

        expect(ledger.snapshot.isEmpty, isTrue);
        expect(ledger.snapshot.platformIdFor('a-job'), isNull);

        store.writeError = null;
        final retried = await ledger.reserve('a-job');
        expect(
          retried.platformId,
          firstPlatformId,
          reason: 'id 1 was never used',
        );
        ledger.dispose();
      },
    );

    test('long full ids are stored whole and get distinct ids', () async {
      final store = LedgerFakeStore();
      final ledger = ReminderStateStore(store: store);
      final longA = 'wb-${'a' * 60}-2026';
      final longB = 'wb-${'a' * 59}b-2026';

      final a = await ledger.reserve(longA);
      final b = await ledger.reserve(longB);

      expect(a.platformId, isNot(b.platformId));
      expect(ledger.snapshot.platformIdFor(longA), a.platformId);
      expect(ledger.snapshot.platformIdFor(longB), b.platformId);
      expect(storedDocument(store)['entries'], hasLength(2));
      expect(
        (storedDocument(store)['entries'] as List)
            .map((e) => (e as Map)['job_id'])
            .toSet(),
        {longA, longB},
        reason: 'ids are stored in full, never truncated or hashed',
      );
      ledger.dispose();
    });

    test('a 101-character or non-slug id is refused', () async {
      final store = LedgerFakeStore();
      final ledger = ReminderStateStore(store: store);

      for (final bad in [
        '',
        'Upper-Case',
        'has space',
        'a' * 101,
        'emoji-😀',
      ]) {
        await expectLater(
          ledger.reserve(bad),
          throwsA(
            isA<ReminderStateException>().having(
              (e) => e.failure,
              'failure',
              ReminderStateFailure.invalidJobId,
            ),
          ),
          reason: 'id "$bad"',
        );
      }
      expect(store.writes, 0);
      ledger.dispose();
    });

    test('allocator exhaustion fails safely without reusing an id', () async {
      final store = LedgerFakeStore(
        backing: {
          ReminderStateStore.storageKey: [
            '{"schema_version":1,"next_platform_id":2147483647,"entries":[{"job_id":"a-job","platform_id":2147483646,"applied":null}]}',
          ],
        },
      );
      final ledger = ReminderStateStore(store: store);
      await ledger.initialize();

      final last = await ledger.reserve('b-job');
      expect(last.platformId, maxPlatformId);

      await expectLater(
        ledger.reserve('c-job'),
        throwsA(
          isA<ReminderStateException>().having(
            (e) => e.failure,
            'failure',
            ReminderStateFailure.exhausted,
          ),
        ),
      );
      expect(ledger.snapshot.nextPlatformId, maxPlatformId + 1);
      expect(ledger.snapshot.platformIdFor('c-job'), isNull);
      ledger.dispose();
    });

    test(
      'an already-exhausted document refuses even the first reservation',
      () async {
        final store = LedgerFakeStore(
          backing: {
            ReminderStateStore.storageKey: [
              '{"schema_version":1,"next_platform_id":2147483648,"entries":[]}',
            ],
          },
        );
        final ledger = ReminderStateStore(store: store);
        await ledger.initialize();

        await expectLater(
          ledger.reserve('a-job'),
          throwsA(
            isA<ReminderStateException>().having(
              (e) => e.failure,
              'failure',
              ReminderStateFailure.exhausted,
            ),
          ),
        );
        expect(store.writes, 0);
        ledger.dispose();
      },
    );
  });

  group('concurrency', () {
    test('concurrent reservations get distinct ids and all persist', () async {
      final store = LedgerFakeStore();
      final ledger = ReminderStateStore(store: store);

      final reservations = await Future.wait([
        ledger.reserve('a-job'),
        ledger.reserve('b-job'),
        ledger.reserve('c-job'),
        ledger.reserve('a-job'), // same job, must not take a second id
      ]);

      final ids = reservations.map((r) => r.platformId).toList();
      expect(ids.toSet(), hasLength(3));
      expect(ledger.snapshot.entries, hasLength(3));
      expect(
        ledger.snapshot.platformIdFor('a-job'),
        reservations.first.platformId,
      );
      expect(store.backing[ReminderStateStore.storageKey], hasLength(1));
      ledger.dispose();
    });

    test(
      'a slow write serialises later operations instead of losing them',
      () async {
        final gate = Completer<void>();
        final store = LedgerFakeStore()..writeGate = gate.future;
        final ledger = ReminderStateStore(store: store);

        final first = ledger.reserve('a-job');
        final second = ledger.reserve('b-job');
        await Future<void>.delayed(Duration.zero);
        expect(store.writes, 1, reason: 'the second write waits for the first');

        gate.complete();
        final results = await Future.wait([first, second]);

        expect(results.map((r) => r.platformId).toSet(), {1, 2});
        expect(ledger.snapshot.entries, hasLength(2));
        ledger.dispose();
      },
    );

    test('concurrent applied updates do not overwrite each other', () async {
      final store = LedgerFakeStore();
      final ledger = ReminderStateStore(store: store);
      await ledger.reserve('a-job');
      await ledger.reserve('b-job');

      await Future.wait([
        ledger.recordSchedulingSuccess(
          entry: entryFor('a-job'),
          payloadVariant: 'bn@copy-1',
        ),
        ledger.recordSchedulingSuccess(
          entry: entryFor(
            'b-job',
            due: utc(2026, 11, 20, 12),
            closes: utc(2026, 11, 21, 12),
          ),
          payloadVariant: 'en@copy-1',
        ),
      ]);

      expect(ledger.snapshot.appliedFor('a-job')?.payloadVariant, 'bn@copy-1');
      expect(ledger.snapshot.appliedFor('b-job')?.payloadVariant, 'en@copy-1');
      ledger.dispose();
    });
  });

  group('applied-state ledger', () {
    test(
      'a scheduling success stores the exact instants, key and variant',
      () async {
        final store = LedgerFakeStore();
        final ledger = ReminderStateStore(store: store);
        await ledger.reserve('a-job');

        final due = utc(2026, 11, 19, 12, 30);
        final closes = utc(2026, 11, 20, 12, 30);
        await ledger.recordSchedulingSuccess(
          entry: entryFor(
            'a-job',
            due: due,
            closes: closes,
            contentKey: 'wb-পুলিশ-2026|titles|deadline',
          ),
          payloadVariant: 'bn@copy-3',
        );

        final applied = ledger.snapshot.appliedFor('a-job')!;
        expect(applied.dueAtUtc, due);
        expect(applied.closesAtUtc, closes);
        expect(applied.dueAtUtc.isUtc, isTrue);
        expect(applied.contentKey, 'wb-পুলিশ-2026|titles|deadline');
        expect(applied.payloadVariant, 'bn@copy-3');
        ledger.dispose();
      },
    );

    test('a scheduling success without a reservation is refused', () async {
      final store = LedgerFakeStore();
      final ledger = ReminderStateStore(store: store);
      await ledger.initialize();

      await expectLater(
        ledger.recordSchedulingSuccess(
          entry: entryFor('never-reserved'),
          payloadVariant: 'bn@copy-1',
        ),
        throwsA(
          isA<ReminderStateException>().having(
            (e) => e.failure,
            'failure',
            ReminderStateFailure.unknownReservation,
          ),
        ),
      );
      expect(
        ledger.snapshot.entries,
        isEmpty,
        reason: 'no implicit reservation',
      );
      expect(store.writes, 0, reason: 'nothing was written');
      ledger.dispose();
    });

    test('an invalid entry is refused before any write', () async {
      final store = LedgerFakeStore();
      final ledger = ReminderStateStore(store: store);
      await ledger.reserve('a-job');
      final writes = store.writes;

      // due == closes is not a reminder, it is a coincidence.
      await expectLater(
        ledger.recordSchedulingSuccess(
          entry: entryFor(
            'a-job',
            due: utc(2026, 11, 20, 12),
            closes: utc(2026, 11, 20, 12),
          ),
          payloadVariant: 'bn@copy-1',
        ),
        throwsA(
          isA<ReminderStateException>().having(
            (e) => e.failure,
            'failure',
            ReminderStateFailure.invalidEntry,
          ),
        ),
      );
      await expectLater(
        ledger.recordSchedulingSuccess(
          entry: entryFor('a-job', contentKey: '   '),
          payloadVariant: 'bn@copy-1',
        ),
        throwsA(isA<ReminderStateException>()),
      );
      await expectLater(
        ledger.recordSchedulingSuccess(
          entry: entryFor('a-job'),
          payloadVariant: '  ',
        ),
        throwsA(
          isA<ReminderStateException>().having(
            (e) => e.failure,
            'failure',
            ReminderStateFailure.invalidPayloadVariant,
          ),
        ),
      );

      expect(store.writes, writes);
      expect(ledger.snapshot.appliedFor('a-job'), isNull);
      ledger.dispose();
    });

    test(
      'a failed write is not reported as applied, and retry works',
      () async {
        final store = LedgerFakeStore();
        final ledger = ReminderStateStore(store: store);
        await ledger.reserve('a-job');

        store.writeError = StateError('disk full');
        await expectLater(
          ledger.recordSchedulingSuccess(
            entry: entryFor('a-job'),
            payloadVariant: 'bn@copy-1',
          ),
          throwsA(
            isA<ReminderStateException>().having(
              (e) => e.failure,
              'failure',
              ReminderStateFailure.storage,
            ),
          ),
        );
        expect(
          ledger.snapshot.appliedFor('a-job'),
          isNull,
          reason: 'a failed write must never look applied',
        );
        expect(
          decodeReminderStateDocument(
            store.backing[ReminderStateStore.storageKey],
          ).appliedFor('a-job'),
          isNull,
          reason: 'durable state is untouched too',
        );

        store.writeError = null;
        await ledger.recordSchedulingSuccess(
          entry: entryFor('a-job'),
          payloadVariant: 'bn@copy-1',
        );
        expect(
          ledger.snapshot.appliedFor('a-job'),
          isNotNull,
          reason: 'the queue stayed retryable',
        );
        ledger.dispose();
      },
    );

    test(
      'a non-UTC entry instant is normalised to the same UTC instant',
      () async {
        final store = LedgerFakeStore();
        final ledger = ReminderStateStore(store: store);
        await ledger.reserve('a-job');

        // 2026-11-19T17:30+05:30 == 2026-11-19T12:00Z
        final istDue = DateTime.parse('2026-11-19T17:30:00+05:30');
        final istCloses = DateTime.parse('2026-11-20T17:30:00+05:30');
        await ledger.recordSchedulingSuccess(
          entry: entryFor('a-job', due: istDue, closes: istCloses),
          payloadVariant: 'bn@copy-1',
        );

        final applied = ledger.snapshot.appliedFor('a-job')!;
        expect(applied.dueAtUtc.isUtc, isTrue);
        expect(applied.closesAtUtc.isUtc, isTrue);
        expect(applied.dueAtUtc, utc(2026, 11, 19, 12));
        expect(applied.closesAtUtc, utc(2026, 11, 20, 12));
        expect(
          applied.dueAtUtc.isAtSameMomentAs(istDue),
          isTrue,
          reason: 'normalising must not shift the instant',
        );
        ledger.dispose();
      },
    );

    test('recording the identical application twice writes once', () async {
      final store = LedgerFakeStore();
      final ledger = ReminderStateStore(store: store);
      await ledger.reserve('a-job');
      await ledger.recordSchedulingSuccess(
        entry: entryFor('a-job'),
        payloadVariant: 'bn@copy-1',
      );
      final writes = store.writes;

      await ledger.recordSchedulingSuccess(
        entry: entryFor('a-job'),
        payloadVariant: 'bn@copy-1',
      );

      expect(store.writes, writes, reason: 'no churn for an unchanged record');
      ledger.dispose();
    });

    test('a correction replaces the applied metadata', () async {
      final store = LedgerFakeStore();
      final ledger = ReminderStateStore(store: store);
      await ledger.reserve('a-job');
      await ledger.recordSchedulingSuccess(
        entry: entryFor('a-job', contentKey: 'old-text'),
        payloadVariant: 'bn@copy-1',
      );

      await ledger.recordSchedulingSuccess(
        entry: entryFor(
          'a-job',
          due: utc(2026, 11, 21, 12),
          closes: utc(2026, 11, 22, 12),
          contentKey: 'corrected-text',
        ),
        payloadVariant: 'bn@copy-2',
      );

      final applied = ledger.snapshot.appliedFor('a-job')!;
      expect(applied.contentKey, 'corrected-text');
      expect(applied.payloadVariant, 'bn@copy-2');
      expect(applied.dueAtUtc, utc(2026, 11, 21, 12));
      ledger.dispose();
    });

    test(
      'a cancellation clears applied metadata but keeps the reservation',
      () async {
        final store = LedgerFakeStore();
        final ledger = ReminderStateStore(store: store);
        final reservation = await ledger.reserve('a-job');
        await ledger.recordSchedulingSuccess(
          entry: entryFor('a-job'),
          payloadVariant: 'bn@copy-1',
        );

        await ledger.recordCancellationSuccess('a-job');

        expect(ledger.snapshot.appliedFor('a-job'), isNull);
        expect(
          ledger.snapshot.platformIdFor('a-job'),
          reservation.platformId,
          reason: 'an id is never returned to the pool',
        );
        expect(ledger.snapshot.entries, hasLength(1));

        // The next new job still gets a fresh id, not the cancelled one.
        final next = await ledger.reserve('b-job');
        expect(next.platformId, reservation.platformId + 1);
        ledger.dispose();
      },
    );

    test(
      'cancelling twice, or cancelling an unknown job, is a harmless no-op',
      () async {
        final store = LedgerFakeStore();
        final ledger = ReminderStateStore(store: store);
        await ledger.reserve('a-job');
        await ledger.recordSchedulingSuccess(
          entry: entryFor('a-job'),
          payloadVariant: 'bn@copy-1',
        );
        await ledger.recordCancellationSuccess('a-job');
        final writes = store.writes;

        await ledger.recordCancellationSuccess('a-job');
        await ledger.recordCancellationSuccess('never-reserved');

        expect(store.writes, writes);
        expect(ledger.snapshot.platformIdFor('never-reserved'), isNull);
        ledger.dispose();
      },
    );

    test('a failed cancellation leaves the applied record in place', () async {
      final store = LedgerFakeStore();
      final ledger = ReminderStateStore(store: store);
      await ledger.reserve('a-job');
      await ledger.recordSchedulingSuccess(
        entry: entryFor('a-job'),
        payloadVariant: 'bn@copy-1',
      );

      store.writeError = StateError('disk full');
      await expectLater(
        ledger.recordCancellationSuccess('a-job'),
        throwsA(isA<ReminderStateException>()),
      );

      expect(
        ledger.snapshot.appliedFor('a-job'),
        isNotNull,
        reason: 'a cancellation that was not recorded must not look cancelled',
      );
      ledger.dispose();
    });

    test('snapshots are immutable and detached from later changes', () async {
      final store = LedgerFakeStore();
      final ledger = ReminderStateStore(store: store);
      await ledger.reserve('a-job');

      final before = ledger.snapshot;
      await ledger.recordSchedulingSuccess(
        entry: entryFor('a-job'),
        payloadVariant: 'bn@copy-1',
      );

      expect(
        before.appliedFor('a-job'),
        isNull,
        reason: 'an old snapshot is still valid',
      );
      expect(ledger.snapshot.appliedFor('a-job'), isNotNull);
      expect(
        () => before.entries.add(before.entries.first),
        throwsUnsupportedError,
      );
      ledger.dispose();
    });
  });

  group('restart', () {
    test(
      'a new instance over the same storage sees the same ids and ledger',
      () async {
        final backing = <String, List<String>>{};
        final firstProcess = ReminderStateStore(
          store: LedgerFakeStore(backing: backing),
        );
        final a = await firstProcess.reserve('a-job');
        await firstProcess.reserve('b-job');
        await firstProcess.recordSchedulingSuccess(
          entry: entryFor('a-job', contentKey: 'k-1'),
          payloadVariant: 'bn@copy-7',
        );
        firstProcess.dispose();

        final secondProcess = ReminderStateStore(
          store: LedgerFakeStore(backing: backing),
        );
        await secondProcess.initialize();

        expect(secondProcess.snapshot.platformIdFor('a-job'), a.platformId);
        final applied = secondProcess.snapshot.appliedFor('a-job')!;
        expect(applied.contentKey, 'k-1');
        expect(applied.payloadVariant, 'bn@copy-7');
        expect(applied.dueAtUtc, utc(2026, 11, 19, 12));
        expect(
          applied.dueAtUtc.toIso8601String(),
          '2026-11-19T12:00:00.000Z',
          reason: 'UTC fidelity survives the JSON round trip',
        );

        // The allocator continues where it stopped instead of restarting at 1.
        final c = await secondProcess.reserve('c-job');
        expect(c.platformId, 3);
        secondProcess.dispose();
      },
    );

    test(
      'a cancelled job reloads with its reservation and no applied state',
      () async {
        final backing = <String, List<String>>{};
        final first = ReminderStateStore(
          store: LedgerFakeStore(backing: backing),
        );
        final reservation = await first.reserve('a-job');
        await first.recordSchedulingSuccess(
          entry: entryFor('a-job'),
          payloadVariant: 'bn@copy-1',
        );
        await first.recordCancellationSuccess('a-job');
        first.dispose();

        final second = ReminderStateStore(
          store: LedgerFakeStore(backing: backing),
        );
        await second.initialize();

        expect(second.snapshot.platformIdFor('a-job'), reservation.platformId);
        expect(second.snapshot.appliedFor('a-job'), isNull);
        second.dispose();
      },
    );

    test('a locale/copy variant with unicode round-trips exactly', () async {
      final backing = <String, List<String>>{};
      final first = ReminderStateStore(
        store: LedgerFakeStore(backing: backing),
      );
      await first.reserve('a-job');
      await first.recordSchedulingSuccess(
        entry: entryFor('a-job', contentKey: 'কর্মপথ|শিরোনাম|২০২৬'),
        payloadVariant: 'bn-IN@copy-2026.10',
      );
      first.dispose();

      final second = ReminderStateStore(
        store: LedgerFakeStore(backing: backing),
      );
      await second.initialize();

      expect(
        second.snapshot.appliedFor('a-job')!.contentKey,
        'কর্মপথ|শিরোনাম|২০২৬',
      );
      expect(
        second.snapshot.appliedFor('a-job')!.payloadVariant,
        'bn-IN@copy-2026.10',
      );
      second.dispose();
    });
  });

  group('isolation from other settings', () {
    test('legacy keys are never read or rewritten', () async {
      final backing = <String, List<String>>{
        'karmopath.saved.v1': ['wb-police-2026'],
        'karmopath.reminders.v1': ['wb-police-2026'],
        'karmopath.feed.v1': ['{"schema_version":1}'],
        'language': ['bn'],
      };
      final store = LedgerFakeStore(backing: backing);
      final ledger = ReminderStateStore(store: store);

      await ledger.reserve('a-job');
      await ledger.recordSchedulingSuccess(
        entry: entryFor('a-job'),
        payloadVariant: 'bn@copy-1',
      );
      await ledger.recordCancellationSuccess('a-job');

      expect(store.writtenKeys.toSet(), {ReminderStateStore.storageKey});
      expect(backing['karmopath.saved.v1'], ['wb-police-2026']);
      expect(backing['karmopath.reminders.v1'], ['wb-police-2026']);
      expect(backing['karmopath.feed.v1'], ['{"schema_version":1}']);
      expect(backing['language'], ['bn']);
      ledger.dispose();
    });

    test('the storage key is the reserved versioned name', () {
      expect(ReminderStateStore.storageKey, 'karmopath.reminder_state.v1');
    });
  });

  group('lifecycle', () {
    test('operations after dispose fail explicitly', () async {
      final ledger = ReminderStateStore(store: LedgerFakeStore());
      ledger.dispose();

      await expectLater(
        ledger.reserve('a-job'),
        throwsA(
          isA<ReminderStateException>().having(
            (e) => e.failure,
            'failure',
            ReminderStateFailure.disposed,
          ),
        ),
      );
      ledger.dispose(); // idempotent
    });

    test('a write started before dispose finished is not published', () async {
      final gate = Completer<void>();
      final store = LedgerFakeStore()..writeGate = gate.future;
      final ledger = ReminderStateStore(store: store);
      final published = <ReminderState>[];
      ledger.state.addListener(() => published.add(ledger.snapshot));

      final pending = ledger.reserve('a-job');
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, 1, reason: 'the write had already begun');

      ledger.dispose();
      gate.complete();
      await pending;
      await Future<void>.delayed(Duration.zero);

      expect(
        published,
        isEmpty,
        reason: 'no state may be published after disposal',
      );
    });
  });
}
