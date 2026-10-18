import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../contracts/native_reminders.dart';
import '../../data/reminders/native_reminder_payload.dart';

/// Android plugin backend only. Plugin records/returns are not delivery receipts.
class AndroidNativeNotifications implements NativeNotifications {
  AndroidNativeNotifications({
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? nowUtc,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() _nowUtc;
  void Function(String)? _onJobTap;
  Future<void>? _initializing;
  bool _ready = false;
  bool _disposed = false;
  int _generation = 0;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  void _checkActive() {
    if (_disposed) throw StateError('Notification backend disposed');
  }

  void _checkAndroid() {
    _checkActive();
    if (!_supported) throw UnsupportedError('Android notifications only');
  }

  @override
  Future<void> initialize({
    required void Function(String jobId) onJobTap,
  }) async {
    _checkActive();
    if (!_supported) return;
    _onJobTap = onJobTap;
    if (_ready) return;
    final operation = _initializing ??= _initializePlugin();
    try {
      await operation;
    } finally {
      if (identical(_initializing, operation)) _initializing = null;
    }
  }

  Future<void> _initializePlugin() async {
    final generation = ++_generation;
    try {
      final initialized = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(reminderAndroidIcon),
        ),
        onDidReceiveNotificationResponse: (response) {
          if (generation == _generation) _tap(response.payload);
        },
      );
      if (initialized != true) throw StateError('Plugin initialization failed');
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (_disposed) return;
      _ready = true;
      if (launch?.didNotificationLaunchApp == true) {
        _tap(launch?.notificationResponse?.payload);
      }
    } catch (_) {
      _ready = false;
      _generation++;
      rethrow;
    }
  }

  void _tap(String? payload) {
    if (_disposed || !_ready) return;
    final decoded = decodeNativeReminderPayload(payload);
    final identity = decoded.identity;
    if (decoded.isManaged && identity != null) _onJobTap?.call(identity.jobId);
  }

  @override
  Future<ReminderPermission> permissionStatus() async {
    _checkActive();
    if (!_supported) return ReminderPermission.unsupported;
    final enabled = await _android?.areNotificationsEnabled();
    return switch (enabled) {
      true => ReminderPermission.granted,
      false => ReminderPermission.denied,
      null => ReminderPermission.unavailable,
    };
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    _checkActive();
    if (!_supported) return ReminderPermission.unsupported;
    final android = _android;
    if (android == null) return ReminderPermission.unavailable;
    await android.requestNotificationsPermission();
    return permissionStatus();
  }

  @override
  Future<List<NativePendingReminder>> pendingReminders() async {
    _checkAndroid();
    final records = await _plugin.pendingNotificationRequests();
    return records.map((record) {
      final decoded = decodeNativeReminderPayload(record.payload);
      return NativePendingReminder(
        platformId: record.id,
        isManaged: decoded.isManaged,
        identity: decoded.identity,
      );
    }).toList();
  }

  static void _validateId(int id) {
    if (id < 1 || id > 2147483647) throw ArgumentError.value(id, 'platformId');
  }

  void _checkFuture(DateTime due) {
    if (!due.isAfter(_nowUtc().toUtc())) {
      throw StateError('Reminder due time is no longer in the future');
    }
  }

  @override
  Future<void> schedule(NativeReminderRequest request) async {
    _checkAndroid();
    _validateId(request.platformId);
    // Revalidate at the boundary, including callers implementing the DTO types.
    final identity = NativeReminderIdentity(
      jobId: request.identity.jobId,
      dueAtUtc: request.identity.dueAtUtc,
      closesAtUtc: request.identity.closesAtUtc,
      contentKey: request.identity.contentKey,
      payloadVariant: request.identity.payloadVariant,
    );
    NativeReminderRequest(
      platformId: request.platformId,
      identity: identity,
      title: request.title,
      body: request.body,
    );
    _checkFuture(identity.dueAtUtc);
    if (await permissionStatus() != ReminderPermission.granted) {
      throw StateError('Notification permission is not granted');
    }
    final payload = encodeNativeReminderPayload(identity);
    final date = tz.TZDateTime.from(identity.dueAtUtc, tz.UTC);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        reminderAndroidChannelId,
        reminderAndroidChannelName,
        icon: reminderAndroidIcon,
        importance: Importance.defaultImportance,
      ),
    );
    _checkActive();
    _checkFuture(identity.dueAtUtc);
    await _plugin.zonedSchedule(
      id: request.platformId,
      title: request.title,
      body: request.body,
      payload: payload,
      scheduledDate: date,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int platformId) async {
    _checkAndroid();
    _validateId(platformId);
    await _plugin.cancel(id: platformId);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _ready = false;
    _generation++;
    _onJobTap = null;
  }
}
