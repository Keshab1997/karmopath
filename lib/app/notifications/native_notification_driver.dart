import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../contracts/native_reminders.dart';

/// OS boundary. Queries never prompt; only [requestPermission] may prompt.
abstract interface class NativeNotificationDriver {
  Future<void> initialize();
  Future<bool> notificationsEnabled();
  Future<bool> requestPermission();

  /// Plugin-reported pending requests, not proof that AlarmManager still holds
  /// every alarm (force-stop/reboot can invalidate OS state independently).
  Future<Set<int>> pendingIds();
  Future<void> cancel(int id);
  Future<void> schedule({
    required int id,
    required DateTime dueAtUtc,
    required String title,
    required String body,
    required String payload,
  });

  /// Release this runtime, NOT its durable OS schedules.
  Future<void> close();
}

/// Android-only implementation; never initialized by the web demo/entrypoint.
///
/// UTC schedules preserve the planner's absolute instant when the device moves
/// timezone. Inexact idle scheduling deliberately avoids exact-alarm permission
/// and any claim of on-time delivery. Android boot/package receivers restore
/// the plugin's persisted schedules; Dart reconciliation is still necessary.
class AndroidNotificationDriver implements NativeNotificationDriver {
  AndroidNotificationDriver({AndroidFlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? AndroidFlutterLocalNotificationsPlugin();

  // Reuse the already-published resource/metadata rather than replacing the
  // newer main prerequisites with this foundation's earlier icon choice.
  static const icon = reminderAndroidIcon;
  static const channelId = reminderAndroidChannelId;
  final AndroidFlutterLocalNotificationsPlugin _plugin;
  Future<void>? _initializing;
  bool _ready = false;
  bool _closed = false;

  @override
  Future<void> initialize() {
    if (_closed) return Future<void>.error(StateError('Driver is closed'));
    if (_ready) return Future<void>.value();
    final running = _initializing;
    if (running != null) return running;
    final attempt = Completer<void>();
    _initializing = attempt.future;
    unawaited(_initialize(attempt));
    return attempt.future;
  }

  Future<void> _initialize(Completer<void> attempt) async {
    try {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        throw UnsupportedError('Native reminders require Android');
      }
      final initialized = await _plugin.initialize(
        settings: const AndroidInitializationSettings(icon),
      );
      if (initialized != true) {
        throw StateError('Notification plugin did not initialize');
      }
      if (_closed) throw StateError('Driver closed during initialization');
      _ready = true;
      attempt.complete();
    } catch (error, stack) {
      _initializing = null;
      attempt.completeError(error, stack);
    }
  }

  void _requireReady() {
    if (_closed || !_ready) throw StateError('Driver is not ready');
  }

  @override
  Future<bool> notificationsEnabled() async {
    _requireReady();
    final enabled = await _plugin.areNotificationsEnabled();
    _requireReady();
    if (enabled == null) throw StateError('Notification permission is unknown');
    return enabled;
  }

  @override
  Future<bool> requestPermission() async {
    _requireReady();
    final granted = await _plugin.requestNotificationsPermission();
    _requireReady();
    if (granted == null) throw StateError('Notification permission is unknown');
    return granted;
  }

  @override
  Future<Set<int>> pendingIds() async {
    _requireReady();
    final requests = await _plugin.pendingNotificationRequests();
    _requireReady();
    return Set<int>.unmodifiable(requests.map((request) => request.id));
  }

  @override
  Future<void> cancel(int id) async {
    _requireReady();
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> schedule({
    required int id,
    required DateTime dueAtUtc,
    required String title,
    required String body,
    required String payload,
  }) async {
    _requireReady();
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      payload: payload,
      scheduledDate: tz.TZDateTime.from(dueAtUtc.toUtc(), tz.UTC),
      scheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: const AndroidNotificationDetails(
        channelId,
        reminderAndroidChannelName,
        channelDescription: 'Optional application deadline reminders',
        icon: icon,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
    _ready = false;
    // The plugin has no per-instance dispose API. Never cancel notifications
    // on app close: doing so would defeat persistence and boot restoration.
  }
}
