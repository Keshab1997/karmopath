import '../../data/reminders/reminder_apply.dart';
import '../../data/reminders/reminder_plan.dart';
import '../../data/reminders/reminder_state.dart';
import 'native_notification_driver.dart';

/// Transport fields extracted from B's content DTO by the integration binding.
/// The binding captures one plan's validated jobs and explicit language.
typedef ReminderNotificationText = ({
  String title,
  String body,
  String payload,
});
typedef ReminderTextBuilder = ReminderNotificationText Function(
  ReminderPlanEntry entry,
);

/// Concrete platform for one immutable plan/language snapshot.
///
/// Permission denial/query failure is an operation failure, not a successful
/// schedule. Cancellation does not require permission. Only explicit feature
/// actions request permission; startup/reconciliation never does.
class LocalReminderPlatform implements ReminderPlatform {
  LocalReminderPlatform({
    required this.driver,
    required this._contentFor,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final NativeNotificationDriver driver;
  final ReminderTextBuilder _contentFor;
  final DateTime Function() _now;

  Future<Set<int>> pendingIds() => driver.pendingIds();

  static void _validateId(int id) {
    if (id < firstPlatformId || id > maxPlatformId) {
      throw ArgumentError.value(id, 'id', 'invalid reserved platform ID');
    }
  }

  @override
  Future<void> cancel(int id) async {
    _validateId(id);
    await driver.cancel(id);
  }

  @override
  Future<void> schedule(ReminderPlanEntry entry, int platformId) async {
    _validateId(platformId);
    if (!entry.dueAtUtc.isBefore(entry.closesAtUtc) ||
        entry.contentKey.trim().isEmpty) {
      throw ArgumentError('Invalid reminder entry');
    }
    if (!entry.dueAtUtc.toUtc().isAfter(_now().toUtc())) {
      throw StateError('Reminder due time is no longer in the future');
    }
    final text = _contentFor(entry);
    if (text.title.trim().isEmpty ||
        text.body.trim().isEmpty ||
        text.payload != entry.jobId) {
      throw StateError('Notification content does not match the reminder');
    }
    if (!await driver.notificationsEnabled()) {
      throw StateError('Notification permission is not granted');
    }
    // A permission query may itself cross the cutoff. Never catch up a past
    // reminder or turn an expired plan into an immediate notification.
    if (!entry.dueAtUtc.toUtc().isAfter(_now().toUtc())) {
      throw StateError('Reminder expired during the permission query');
    }
    await driver.schedule(
      id: platformId,
      dueAtUtc: entry.dueAtUtc.toUtc(),
      title: text.title,
      body: text.body,
      payload: text.payload,
    );
  }
}
