import 'job.dart';

/// Frozen Batch 7 integration ports. No plugin, storage, network or UI effects.
/// Workers implement these independently; the captain composes them afterwards.
const reminderPayloadNamespace = 'karmopath.reminder.v1';
const reminderAndroidChannelId = 'karmopath.deadlines.v1';
const reminderAndroidChannelName = 'Deadline reminders';
const reminderAndroidIcon = 'ic_stat_karmopath';

String reminderPayloadVariant(String languageCode) => switch (languageCode) {
  'bn' => 'bn@reminder-v1',
  'en' => 'en@reminder-v1',
  _ => throw ArgumentError.value(
    languageCode,
    'languageCode',
    'expected bn/en',
  ),
};

enum ReminderPermission { granted, denied, unavailable, unsupported }

/// Identity of the schedule, not a delivery receipt. The full values are used
/// for reconciliation; neither job IDs nor content fingerprints may be hashed.
class NativeReminderIdentity {
  NativeReminderIdentity({
    required this.jobId,
    required DateTime dueAtUtc,
    required DateTime closesAtUtc,
    required this.contentKey,
    required this.payloadVariant,
  }) : dueAtUtc = dueAtUtc.toUtc(),
       closesAtUtc = closesAtUtc.toUtc() {
    if (!RegExp(r'^[a-z0-9-]{1,100}$').hasMatch(jobId) ||
        !this.dueAtUtc.isBefore(this.closesAtUtc) ||
        contentKey.trim().isEmpty ||
        payloadVariant.trim().isEmpty) {
      throw ArgumentError('Invalid reminder identity');
    }
  }

  final String jobId;
  final DateTime dueAtUtc;
  final DateTime closesAtUtc;
  final String contentKey;
  final String payloadVariant;

  @override
  bool operator ==(Object other) =>
      other is NativeReminderIdentity &&
      other.jobId == jobId &&
      other.dueAtUtc == dueAtUtc &&
      other.closesAtUtc == closesAtUtc &&
      other.contentKey == contentKey &&
      other.payloadVariant == payloadVariant;

  @override
  int get hashCode =>
      Object.hash(jobId, dueAtUtc, closesAtUtc, contentKey, payloadVariant);
}

class NativeReminderRequest {
  NativeReminderRequest({
    required this.platformId,
    required this.identity,
    required this.title,
    required this.body,
  }) {
    if (platformId < 1 ||
        platformId > 2147483647 ||
        title.trim().isEmpty ||
        body.trim().isEmpty) {
      throw ArgumentError('Invalid reminder request');
    }
  }

  final int platformId;
  final NativeReminderIdentity identity;
  final String title;
  final String body;
}

/// Every backend-reported pending ID is included, even unrecognised payloads,
/// so a reserved ID cannot overwrite another reported notification. The plugin
/// registry is not independent proof that an OS alarm exists or was delivered.
class NativePendingReminder {
  const NativePendingReminder({
    required this.platformId,
    required this.isManaged,
    required this.identity,
  });

  final int platformId;

  /// True only for the exact [reminderPayloadNamespace]. Unknown/future
  /// namespaces are not ours to cancel. A malformed known payload may have a
  /// null identity but is still managed when its namespace was decoded safely.
  final bool isManaged;
  final NativeReminderIdentity? identity;
}

abstract class NativeNotifications {
  /// No permission dialog here. Valid cold-start/foreground taps are forwarded
  /// as job IDs only. Calls can be retried after an initialization failure.
  Future<void> initialize({required void Function(String jobId) onJobTap});

  /// Passive OS query; null/unknown plugin answers must never become granted.
  Future<ReminderPermission> permissionStatus();

  /// Called only by an explicit user action, never startup or resume.
  Future<ReminderPermission> requestPermission();

  /// Failure throws; an unreadable backend list is never treated as empty.
  Future<List<NativePendingReminder>> pendingReminders();
  Future<void> schedule(NativeReminderRequest request);

  /// Idempotent for an absent ID. No cancelAll/namespace-wide destructive API.
  Future<void> cancel(int platformId);

  /// Detach callbacks/resources, but keep already scheduled notifications.
  Future<void> dispose();
}

class ReminderSyncInput {
  ReminderSyncInput({
    required Iterable<Job>? jobs,
    required Iterable<String> selectedJobIds,
    required this.languageCode,
  }) : jobs = jobs == null ? null : List<Job>.unmodifiable(jobs),
       selectedJobIds = Set<String>.unmodifiable(selectedJobIds) {
    reminderPayloadVariant(languageCode);
  }

  /// Null means no verified feed is available. It is NOT an empty feed and
  /// must not cause cancellation merely because all jobs appear missing.
  final List<Job>? jobs;
  final Set<String> selectedJobIds;
  final String languageCode;
}

enum ReminderSyncStage {
  permission,
  pending,
  ledger,
  cancel,
  schedule,
  conflict,
}

class ReminderSyncProblem {
  const ReminderSyncProblem({
    required this.stage,
    required this.error,
    this.jobId,
    this.platformId,
    this.stackTrace,
  });

  final ReminderSyncStage stage;
  final String? jobId;
  final int? platformId;

  /// Developer diagnostics only; UI renders generic, localized error copy.
  final Object error;
  final StackTrace? stackTrace;
}

class ReminderSyncReport {
  ReminderSyncReport({
    required this.permission,
    required this.feedAvailable,
    required Iterable<String> scheduledJobIds,
    required Iterable<String> cancelledJobIds,
    required Iterable<int> cancelledOrphanIds,
    required Iterable<ReminderSyncProblem> problems,
  }) : scheduledJobIds = List<String>.unmodifiable(scheduledJobIds),
       cancelledJobIds = List<String>.unmodifiable(cancelledJobIds),
       cancelledOrphanIds = List<int>.unmodifiable(cancelledOrphanIds),
       problems = List<ReminderSyncProblem>.unmodifiable(problems);

  final ReminderPermission permission;
  final bool feedAvailable;
  final List<String> scheduledJobIds;
  final List<String> cancelledJobIds;
  final List<int> cancelledOrphanIds;
  final List<ReminderSyncProblem> problems;
  bool get hasFailures => problems.isNotEmpty;
  // No "delivered" or "successful permission" flag is inferred from this DTO.
}

abstract class ReminderSynchronizer {
  /// Serializes reconciliation and apply. Never prompts for permission, changes
  /// intent preferences, or claims OS acceptance proves visible delivery.
  Future<ReminderSyncReport> synchronize(ReminderSyncInput input);

  /// Reject new work, drain queued work, then release owned ledger resources.
  /// Closing must not erase stored intents or cancel scheduled notifications.
  Future<void> close();
}
