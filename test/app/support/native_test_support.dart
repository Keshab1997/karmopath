import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:karmopath/app/notifications/native_notification_driver.dart';
import 'package:karmopath/contracts/native_reminders.dart';

typedef ScheduledCall = ({
  int id,
  DateTime dueAtUtc,
  String title,
  String body,
  String payload,
});

class FakeNativeNotifications implements NativeNotificationDriver {
  FakeNativeNotifications({List<String>? events}) : events = events ?? [];
  final List<String> events;
  final scheduled = <ScheduledCall>[];
  final cancelled = <int>[];
  Set<int> pending = {};
  bool enabled = true;
  bool permissionResult = true;
  Object? initError;
  Object? queryError;
  Object? scheduleError;
  Object? cancelError;
  Object? closeError;
  Future<bool>? permissionGate;
  Future<void>? initGate;
  void Function()? onEnabled;
  int permissionRequests = 0;
  int closes = 0;

  @override
  Future<void> initialize() async {
    events.add('driver.initialize');
    if (initGate case final gate?) await gate;
    if (initError case final error?) throw error;
  }

  @override
  Future<bool> notificationsEnabled() async {
    events.add('driver.enabled');
    onEnabled?.call();
    if (queryError case final error?) throw error;
    return enabled;
  }

  @override
  Future<bool> requestPermission() async {
    events.add('driver.request');
    permissionRequests++;
    final granted =
        await (permissionGate ?? Future<bool>.value(permissionResult));
    enabled = granted;
    return granted;
  }

  @override
  Future<Set<int>> pendingIds() async {
    events.add('driver.pending');
    if (queryError case final error?) throw error;
    return Set<int>.of(pending);
  }

  @override
  Future<void> cancel(int id) async {
    events.add('driver.cancel:$id');
    if (cancelError case final error?) throw error;
    cancelled.add(id);
    pending.remove(id);
  }

  @override
  Future<void> schedule({
    required int id,
    required DateTime dueAtUtc,
    required String title,
    required String body,
    required String payload,
  }) async {
    events.add('driver.schedule:$id');
    if (scheduleError case final error?) throw error;
    scheduled.add((
      id: id,
      dueAtUtc: dueAtUtc,
      title: title,
      body: body,
      payload: payload,
    ));
    pending.add(id);
  }

  @override
  Future<void> close() async {
    events.add('driver.close');
    closes++;
    if (closeError case final error?) throw error;
  }
}

class FakeNativeNotificationBackend implements NativeNotifications {
  FakeNativeNotificationBackend({List<String>? events}) : events = events ?? [];

  final List<String> events;
  final scheduled = <NativeReminderRequest>[];
  final cancelled = <int>[];
  final pending = <NativePendingReminder>[];
  bool enabled = true;
  ReminderPermission permissionResult = ReminderPermission.granted;
  Object? initError;
  Object? queryError;
  Object? pendingError;
  Object? scheduleError;
  Object? cancelError;
  Object? closeError;
  Future<ReminderPermission>? permissionGate;
  void Function(String)? _onJobTap;
  int permissionRequests = 0;
  int closes = 0;

  @override
  Future<void> initialize({
    required void Function(String jobId) onJobTap,
  }) async {
    events.add('driver.initialize');
    _onJobTap = onJobTap;
    if (initError case final error?) throw error;
  }

  @override
  Future<ReminderPermission> permissionStatus() async {
    events.add('driver.enabled');
    if (queryError case final error?) throw error;
    return enabled ? ReminderPermission.granted : ReminderPermission.denied;
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    events.add('driver.request');
    permissionRequests++;
    final result = await (permissionGate ?? Future.value(permissionResult));
    if (result == ReminderPermission.granted) enabled = true;
    if (result == ReminderPermission.denied) enabled = false;
    return result;
  }

  @override
  Future<List<NativePendingReminder>> pendingReminders() async {
    events.add('driver.pending');
    if (pendingError case final error?) throw error;
    return List<NativePendingReminder>.of(pending);
  }

  @override
  Future<void> schedule(NativeReminderRequest request) async {
    events.add('driver.schedule:${request.platformId}');
    if (scheduleError case final error?) throw error;
    scheduled.add(request);
    pending.add(
      NativePendingReminder(
        platformId: request.platformId,
        isManaged: true,
        identity: request.identity,
      ),
    );
  }

  @override
  Future<void> cancel(int platformId) async {
    events.add('driver.cancel:$platformId');
    if (cancelError case final error?) throw error;
    cancelled.add(platformId);
    pending.removeWhere((record) => record.platformId == platformId);
  }

  @override
  Future<void> dispose() async {
    events.add('driver.close');
    closes++;
    _onJobTap = null;
    if (closeError case final error?) throw error;
  }

  void tap(String jobId) => _onJobTap?.call(jobId);
}

class RecordingHttpClient extends http.BaseClient {
  RecordingHttpClient(this.events);
  final List<String> events;
  String body =
      '{"schema_version":1,"updated_at":"2026-01-01T00:00:00Z","jobs":[]}';
  int sends = 0;
  int closes = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    events.add('client.send');
    sends++;
    if (closes > 0) throw StateError('HTTP client already closed');
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }

  @override
  void close() {
    events.add('client.close');
    closes++;
    super.close();
  }
}
