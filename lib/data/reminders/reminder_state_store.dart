/// Durable reminder registry and applied-state ledger: storage and operations.
///
/// One key, one document, one write: `karmopath.reminder_state.v1` holds a
/// schema-versioned JSON string (see `reminder_state_codec.dart`) written as a
/// single-element string list. Registry rows and applied metadata therefore
/// cannot tear apart across separate keys or separate writes.
///
/// This class owns **allocation and bookkeeping only**. The captain owns the
/// notification plugin, permission handling and the actual apply orchestration.
///
/// ## The crash window this module cannot close
///
/// Scheduling is two steps in two systems: the OS accepts a notification, and
/// *then* the ledger records it. If the process dies between those two steps,
/// the OS holds a notification the ledger does not know about. The mirror case
/// exists for cancellation. No amount of local bookkeeping can make that
/// atomic, and this module deliberately does not pretend otherwise: it exposes
/// explicit "this really was applied" operations and never fabricates a
/// success. On restart the captain must reconcile against the OS
/// (query/cancel pending notifications) before trusting the ledger.
///
/// A ledger entry is a record of an applied intent. It is **not** a
/// delivery receipt and not proof that the user ever saw a notification.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../preferences_store.dart';
import 'reminder_plan.dart';
import 'reminder_state.dart';
import 'reminder_state_codec.dart';

/// Registry and applied-state ledger over an injected [PreferencesStore].
class ReminderStateStore {
  ReminderStateStore({required this._store});

  /// The one key this module reads and writes. No other key is touched.
  static const String storageKey = 'karmopath.reminder_state.v1';

  /// Contract-shaped job IDs: lowercase slug, at most 100 characters.
  static final RegExp _jobIdPattern = RegExp(r'^[a-z0-9-]{1,100}$');

  final PreferencesStore _store;

  final ValueNotifier<ReminderState> _state = ValueNotifier<ReminderState>(
    ReminderState.empty(),
  );

  Future<void>? _initialization;
  Future<void> _queue = Future<void>.value();
  bool _loaded = false;
  bool _disposed = false;

  /// Immutable snapshots of the ledger. Listeners fire after a write was
  /// persisted, never before, so a listener can never observe state that a
  /// storage failure would then have to take back.
  ValueListenable<ReminderState> get state => _state;

  /// The current snapshot (same value [state] holds).
  ReminderState get snapshot => _state.value;

  /// True once a load has succeeded in this instance.
  ///
  /// Before that, [snapshot] is the empty document. That is honest — absence
  /// means empty — but the captain should `await initialize()` before
  /// composing UI so "no reminders yet" is not shown while a stored document
  /// is still being read.
  bool get isInitialized => _loaded;

  /// Loads the stored document. Idempotent; a failed load is not cached, so
  /// calling it again retries the read.
  ///
  /// A read failure or a corrupt/unknown document throws
  /// [ReminderStateException] and leaves [snapshot] untouched; every mutating
  /// operation calls this first and therefore also refuses to run. Nothing in
  /// this module ever overwrites a document it could not read.
  Future<void> initialize() => _initialization ??= _load();

  Future<void> _load() async {
    try {
      final List<String>? stored;
      try {
        stored = await _store.readStrings(storageKey);
      } catch (error) {
        // Distinct from corruption on purpose: we never saw the bytes, so
        // nothing at all may be assumed — not even that the key is absent.
        throw ReminderStateException(
          ReminderStateFailure.unreadable,
          'could not read the reminder state: $error',
        );
      }
      final loaded = decodeReminderStateDocument(stored);
      if (_disposed) return;
      _state.value = loaded;
      _loaded = true;
    } catch (_) {
      // Retryable: a later call re-reads instead of caching the failure.
      _initialization = null;
      rethrow;
    }
  }

  /// Reserves a stable platform ID for [jobId] and returns it.
  ///
  /// * The reservation is persisted **before** this returns; if the write
  ///   fails, nothing is handed out and [snapshot] is unchanged.
  /// * Calling it again for the same job returns the existing reservation
  ///   without writing, so an ID is stable across restarts.
  /// * IDs are handed out monotonically from [firstPlatformId] and never
  ///   reused, including after a cancellation. Exhaustion fails with
  ///   [ReminderStateFailure.exhausted] rather than wrapping.
  Future<ReminderReservation> reserve(String jobId) => _serialize(() async {
    final id = _validateJobId(jobId);
    final current = _state.value;
    final existing = current.entryFor(id);
    if (existing != null) {
      return ReminderReservation(jobId: id, platformId: existing.platformId);
    }
    if (current.isExhausted) {
      throw const ReminderStateException(
        ReminderStateFailure.exhausted,
        'every platform notification id has been allocated',
      );
    }
    final platformId = current.nextPlatformId;
    final next = current.withEntry(
      ReminderRegistryEntry(jobId: id, platformId: platformId),
    );
    await _commit(next);
    return ReminderReservation(jobId: id, platformId: platformId);
  });

  /// Records that the captain's platform layer **actually applied** a schedule
  /// for [entry], with the opaque [payloadVariant] it used.
  ///
  /// Requires an existing reservation ([ReminderStateFailure.unknownReservation]
  /// otherwise): a scheduling report never creates an ID as a side effect.
  /// [entry] must be a real A4 entry — `dueAtUtc` strictly before
  /// `closesAtUtc`, non-empty `contentKey` — and [payloadVariant] must be
  /// non-empty. Recording the same applied value twice writes nothing.
  ///
  /// A storage failure throws and leaves the previous applied metadata exactly
  /// as it was, so "not recorded" never degrades into "looks applied".
  Future<void> recordSchedulingSuccess({
    required ReminderPlanEntry entry,
    required String payloadVariant,
  }) => _serialize(() async {
    _validateJobId(entry.jobId);
    if (payloadVariant.trim().isEmpty) {
      throw const ReminderStateException(
        ReminderStateFailure.invalidPayloadVariant,
        'payloadVariant must not be empty',
      );
    }
    final applied = AppliedReminder(
      dueAtUtc: entry.dueAtUtc,
      closesAtUtc: entry.closesAtUtc,
      contentKey: entry.contentKey,
      payloadVariant: payloadVariant,
    );
    final current = _state.value;
    final reservation = current.entryFor(entry.jobId);
    if (reservation == null) {
      throw ReminderStateException(
        ReminderStateFailure.unknownReservation,
        'no reservation for ${entry.jobId}; reserve it before recording a '
        'scheduling success',
      );
    }
    if (reservation.applied == applied) return; // already recorded verbatim
    await _commit(current.withApplied(entry.jobId, applied));
  });

  /// Records that the captain's platform layer **actually cancelled** the
  /// applied reminder for [jobId].
  ///
  /// The reservation and its platform ID are retained — an ID is never
  /// returned to the pool. Cancelling a job with no reservation, or one with
  /// nothing applied, is a no-op that writes nothing.
  Future<void> recordCancellationSuccess(String jobId) => _serialize(() async {
    final id = _validateJobId(jobId);
    final current = _state.value;
    final reservation = current.entryFor(id);
    if (reservation == null || reservation.applied == null) return;
    await _commit(current.withApplied(id, null));
  });

  /// Releases the notifier. Later operations fail with
  /// [ReminderStateFailure.disposed]; a write that already started is allowed
  /// to finish (its result is then not published).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _state.dispose();
  }

  /// Writes [next] and only then publishes it.
  ///
  /// The order is the guarantee: a throwing store leaves both the in-memory
  /// snapshot and the durable document on their previous value, so the caller
  /// can retry the same operation safely.
  Future<void> _commit(ReminderState next) async {
    if (_disposed) {
      throw const ReminderStateException(
        ReminderStateFailure.disposed,
        'the store was disposed',
      );
    }
    final encoded = encodeReminderStateDocument(next);
    try {
      await _store.writeStrings(storageKey, <String>[encoded]);
    } catch (error) {
      throw ReminderStateException(
        ReminderStateFailure.storage,
        'could not persist the reminder state: $error',
      );
    }
    if (_disposed) return;
    _state.value = next;
  }

  /// Serialises every read-modify-write so concurrent callers cannot duplicate
  /// an allocation or lose one another's entries.
  ///
  /// The queue is re-armed with an error-swallowing continuation, so a failed
  /// operation surfaces to its own caller and leaves the queue usable for the
  /// next attempt.
  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        if (_disposed) {
          throw const ReminderStateException(
            ReminderStateFailure.disposed,
            'the store was disposed',
          );
        }
        await initialize();
        if (_disposed) {
          throw const ReminderStateException(
            ReminderStateFailure.disposed,
            'the store was disposed',
          );
        }
        completer.complete(await action());
      } catch (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// Keeps an error message readable when the offending value is arbitrary.
  static String _quoted(String value) =>
      value.length <= 120 ? '"$value"' : '"${value.substring(0, 120)}…"';

  String _validateJobId(String jobId) {
    if (!_jobIdPattern.hasMatch(jobId)) {
      throw ReminderStateException(
        ReminderStateFailure.invalidJobId,
        'job id ${_quoted(jobId)} is not a contract-shaped slug '
        '([a-z0-9-], 1-100 characters)',
      );
    }
    return jobId;
  }
}
