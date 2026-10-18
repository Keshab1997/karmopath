/// Durable reminder registry and applied-state ledger: data model.
///
/// One schema-versioned JSON document lives under the single preferences key
/// `karmopath.reminder_state.v1` so the registry and the applied metadata
/// can never tear apart across separate keys. The strict codec lives in
/// `reminder_state_codec.dart`, and the serialised operations in
/// `reminder_state_store.dart`.
///
/// What this module is **not**: it does not schedule, cancel, prompt for
/// permission or query the OS. A recorded entry means "the captain reported
/// this scheduling or cancellation as applied", which is not proof that a
/// device displayed anything. See the store's documentation for the crash
/// window that no ledger can close on its own.
library;

/// First platform notification ID handed out in this namespace.
const int firstPlatformId = 1;

/// Largest ID allowed in a signed 32-bit platform field (2^31 - 1).
///
/// Allocations never wrap: when the counter would pass this value the store
/// fails with [ReminderStateFailure.exhausted] instead of reusing an ID.
const int maxPlatformId = 2147483647;

/// Why a reminder-state operation failed.
///
/// These are developer-facing categories; the captain maps them to user-safe
/// copy (or to a retry banner) and must never present them as success.
enum ReminderStateFailure {
  /// `PreferencesStore.readStrings` threw. The stored document was not read,
  /// so nothing may be assumed about it — not even that it is empty.
  unreadable,

  /// The stored value is not a well-formed document of this codec: invalid
  /// JSON, wrong types, more or fewer than one element, a bad job ID, a bad
  /// timestamp, or `due >= closes`.
  corrupt,

  /// The document declares a schema version this build does not understand.
  unknownSchema,

  /// Cross-entry or cross-field contradiction: duplicate platform IDs, an
  /// allocated ID that is not below the allocator counter, or a reservation
  /// pointing at an out-of-range ID.
  inconsistent,

  /// A write to the preferences store threw. The in-memory snapshot is
  /// unchanged and the operation can be retried.
  storage,

  /// Every 32-bit ID has been allocated. Nothing was written and no ID was
  /// reused.
  exhausted,

  /// `recordSchedulingSuccess` for a job that has no reservation yet. A
  /// scheduling record never creates a reservation implicitly.
  unknownReservation,

  /// The entry itself is unusable: a non-UTC or non-finite instant, an empty
  /// content key, or `dueAt` not strictly before `closesAt`.
  invalidEntry,

  /// The captain's opaque `payloadVariant` was empty or whitespace only.
  invalidPayloadVariant,

  /// The job ID is empty, longer than the contract's 100 characters, or uses
  /// characters outside `[a-z0-9-]`.
  invalidJobId,

  /// The store was disposed before the operation ran.
  disposed,
}

/// Error raised by the reminder-state codec and store.
class ReminderStateException implements Exception {
  const ReminderStateException(this.failure, this.message);

  final ReminderStateFailure failure;

  /// Developer-facing description. Never shown to users.
  final String message;

  @override
  String toString() => 'ReminderStateException(${failure.name}): $message';
}

/// Metadata for a reminder the captain reported as actually applied.
///
/// Only what was really applied is stored: the instants the notification was
/// planned for, the fingerprint of the copy it was built from, and the opaque
/// payload variant (active language + notification-copy version) that the
/// captain supplied. Nothing here is a delivery receipt.
class AppliedReminder {
  AppliedReminder({
    required DateTime dueAtUtc,
    required DateTime closesAtUtc,
    required this.contentKey,
    required this.payloadVariant,
  }) : dueAtUtc = dueAtUtc.toUtc(),
       closesAtUtc = closesAtUtc.toUtc() {
    if (!this.dueAtUtc.isBefore(this.closesAtUtc)) {
      throw const ReminderStateException(
        ReminderStateFailure.invalidEntry,
        'dueAtUtc must be strictly before closesAtUtc',
      );
    }
    if (contentKey.trim().isEmpty) {
      throw const ReminderStateException(
        ReminderStateFailure.invalidEntry,
        'contentKey must not be empty',
      );
    }
    if (payloadVariant.trim().isEmpty) {
      throw const ReminderStateException(
        ReminderStateFailure.invalidPayloadVariant,
        'payloadVariant must not be empty',
      );
    }
  }

  /// When the reminder was scheduled to fire, normalised to UTC.
  final DateTime dueAtUtc;

  /// The deadline the reminder belongs to, normalised to UTC.
  final DateTime closesAtUtc;

  /// A4's `ReminderPlanEntry.contentKey` — the fingerprint of the alert text
  /// this application was based on. Stored so a later correction is visible.
  final String contentKey;

  /// Opaque captain-supplied variant, e.g. `bn@copy-3`. Compared verbatim.
  final String payloadVariant;

  @override
  bool operator ==(Object other) =>
      other is AppliedReminder &&
      other.dueAtUtc == dueAtUtc &&
      other.closesAtUtc == closesAtUtc &&
      other.contentKey == contentKey &&
      other.payloadVariant == payloadVariant;

  @override
  int get hashCode =>
      Object.hash(dueAtUtc, closesAtUtc, contentKey, payloadVariant);

  @override
  String toString() =>
      'AppliedReminder(due $dueAtUtc, closes $closesAtUtc, '
      'variant $payloadVariant)';
}

/// A permanent platform-ID reservation for one full job ID.
///
/// Reservations outlive cancellations by design: removing applied metadata
/// must never free an ID for reuse, because an OS-level cancel can race with a
/// later schedule and resurrect a stale notification.
class ReminderReservation {
  const ReminderReservation({required this.jobId, required this.platformId});

  final String jobId;
  final int platformId;

  @override
  bool operator ==(Object other) =>
      other is ReminderReservation &&
      other.jobId == jobId &&
      other.platformId == platformId;

  @override
  int get hashCode => Object.hash(jobId, platformId);

  @override
  String toString() => 'ReminderReservation($jobId -> $platformId)';
}

/// One registry row: the reservation plus whatever is currently applied.
class ReminderRegistryEntry {
  const ReminderRegistryEntry({
    required this.jobId,
    required this.platformId,
    this.applied,
  });

  final String jobId;
  final int platformId;

  /// `null` when the reservation exists but nothing is applied (never
  /// scheduled, or explicitly cancelled).
  final AppliedReminder? applied;

  ReminderRegistryEntry withApplied(AppliedReminder? value) =>
      ReminderRegistryEntry(
        jobId: jobId,
        platformId: platformId,
        applied: value,
      );

  @override
  bool operator ==(Object other) =>
      other is ReminderRegistryEntry &&
      other.jobId == jobId &&
      other.platformId == platformId &&
      other.applied == applied;

  @override
  int get hashCode => Object.hash(jobId, platformId, applied);

  @override
  String toString() =>
      'ReminderRegistryEntry($jobId -> $platformId, '
      '${applied ?? 'not applied'})';
}

/// Immutable snapshot of the whole ledger.
class ReminderState {
  /// [entries] must be sorted by job ID and free of duplicates; the codec and
  /// the store both guarantee that, and this constructor enforces it loudly so
  /// a hand-built state cannot slip through.
  ReminderState({
    required this.nextPlatformId,
    required List<ReminderRegistryEntry> entries,
  }) : entries = List<ReminderRegistryEntry>.unmodifiable(entries) {
    if (nextPlatformId < firstPlatformId ||
        nextPlatformId > maxPlatformId + 1) {
      throw ReminderStateException(
        ReminderStateFailure.inconsistent,
        'nextPlatformId $nextPlatformId outside '
        '$firstPlatformId..${maxPlatformId + 1}',
      );
    }
    final seenJobs = <String>{};
    final seenIds = <int>{};
    for (final entry in this.entries) {
      if (!seenJobs.add(entry.jobId)) {
        throw ReminderStateException(
          ReminderStateFailure.inconsistent,
          'duplicate job id ${entry.jobId}',
        );
      }
      if (!seenIds.add(entry.platformId)) {
        throw ReminderStateException(
          ReminderStateFailure.inconsistent,
          'duplicate platform id ${entry.platformId}',
        );
      }
      if (entry.platformId < firstPlatformId ||
          entry.platformId > maxPlatformId) {
        throw ReminderStateException(
          ReminderStateFailure.inconsistent,
          'platform id ${entry.platformId} out of range',
        );
      }
      if (entry.platformId >= nextPlatformId) {
        throw ReminderStateException(
          ReminderStateFailure.inconsistent,
          'platform id ${entry.platformId} is not below the allocator '
          'counter $nextPlatformId',
        );
      }
    }
  }

  /// The document schema this build writes and accepts.
  static const int schemaVersion = 1;

  /// An absent document: no reservations, next ID is [firstPlatformId].
  factory ReminderState.empty() =>
      ReminderState(nextPlatformId: firstPlatformId, entries: const []);

  /// The next ID the allocator would hand out, or `maxPlatformId + 1` when
  /// every ID is taken.
  final int nextPlatformId;

  /// Reservations, sorted by job ID.
  final List<ReminderRegistryEntry> entries;

  bool get isEmpty => entries.isEmpty;

  bool get isExhausted => nextPlatformId > maxPlatformId;

  ReminderRegistryEntry? entryFor(String jobId) {
    for (final entry in entries) {
      if (entry.jobId == jobId) return entry;
    }
    return null;
  }

  AppliedReminder? appliedFor(String jobId) => entryFor(jobId)?.applied;

  int? platformIdFor(String jobId) => entryFor(jobId)?.platformId;

  /// A copy with [entry] inserted (or replacing the row for the same job) and
  /// the list re-sorted by job ID.
  ReminderState withEntry(ReminderRegistryEntry entry) {
    final next = <ReminderRegistryEntry>[
      for (final existing in entries)
        if (existing.jobId != entry.jobId) existing,
      entry,
    ]..sort((a, b) => a.jobId.compareTo(b.jobId));
    return ReminderState(
      // A new reservation consumes the current counter value.
      nextPlatformId: entry.platformId >= nextPlatformId
          ? entry.platformId + 1
          : nextPlatformId,
      entries: next,
    );
  }

  /// A copy with the applied metadata of [jobId] replaced (or cleared).
  ReminderState withApplied(String jobId, AppliedReminder? applied) {
    final current = entryFor(jobId);
    if (current == null) {
      throw ReminderStateException(
        ReminderStateFailure.unknownReservation,
        'no reservation for $jobId',
      );
    }
    return withEntry(current.withApplied(applied));
  }

  /// Value equality, so re-loading an unchanged document is not a change and
  /// a `ValueNotifier` does not fire for it.
  @override
  bool operator ==(Object other) {
    if (other is! ReminderState ||
        other.nextPlatformId != nextPlatformId ||
        other.entries.length != entries.length) {
      return false;
    }
    for (var i = 0; i < entries.length; i++) {
      if (other.entries[i] != entries[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(nextPlatformId, Object.hashAll(entries));

  @override
  String toString() =>
      'ReminderState(next $nextPlatformId, ${entries.length} entries)';
}
