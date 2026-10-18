import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/app/notifications/native_notification_driver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late AndroidNotificationDriver driver;
  Object? queryResponse;
  bool initResponse = true;
  bool queryThrows = false;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls = [];
    queryResponse = true;
    queryThrows = false;
    initResponse = true;
    driver = AndroidNotificationDriver();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'initialize' => initResponse,
        'areNotificationsEnabled' ||
        'requestNotificationsPermission' => queryResponse,
        'pendingNotificationRequests' =>
          queryThrows
              ? throw PlatformException(code: 'query-failed')
              : [
                  {
                    'id': 7,
                    'title': 'Job',
                    'body': 'Notice',
                    'payload': 'a-job',
                  },
                  {
                    'id': 9,
                    'title': 'Job',
                    'body': 'Notice',
                    'payload': 'b-job',
                  },
                ],
        _ => null,
      };
    });
  });
  tearDown(() async {
    await driver.close();
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
  test('initialization is single-flight and never prompts', () async {
    await Future.wait([driver.initialize(), driver.initialize()]);
    await driver.initialize();
    expect(calls.map((c) => c.method), ['initialize']);
    expect((calls.single.arguments as Map)['defaultIcon'], 'ic_stat_karmopath');
  });
  test('failed initialization can retry without fake success', () async {
    initResponse = false;
    await expectLater(driver.initialize(), throwsStateError);
    initResponse = true;
    await driver.initialize();
    expect(calls.where((c) => c.method == 'initialize'), hasLength(2));
  });
  test('unsupported platform fails before any method-channel call', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await expectLater(driver.initialize(), throwsUnsupportedError);
    expect(calls, isEmpty);
  });
  test(
    'unknown permission throws rather than granting or assuming denial',
    () async {
      await driver.initialize();
      queryResponse = null;
      await expectLater(driver.notificationsEnabled(), throwsStateError);
      await expectLater(driver.requestPermission(), throwsStateError);
    },
  );
  test(
    'permission query and explicit request are different OS calls',
    () async {
      await driver.initialize();
      expect(await driver.notificationsEnabled(), isTrue);
      queryResponse = false;
      expect(await driver.requestPermission(), isFalse);
      expect(calls.map((c) => c.method), [
        'initialize',
        'areNotificationsEnabled',
        'requestNotificationsPermission',
      ]);
    },
  );
  test('pending IDs are immutable and query errors propagate', () async {
    await driver.initialize();
    final pending = await driver.pendingIds();
    expect(pending, {7, 9});
    expect(() => pending.add(10), throwsUnsupportedError);
    queryThrows = true;
    await expectLater(driver.pendingIds(), throwsA(isA<PlatformException>()));
  });
  test(
    'actual plugin bridge sends UTC, inexact mode, icon and full payload',
    () async {
      await driver.initialize();
      final due = DateTime.utc(2035, 6, 15, 12, 30);
      await driver.schedule(
        id: 7,
        dueAtUtc: due,
        title: 'নিয়োগ',
        body: 'Notice',
        payload: 'long-full-job-id',
      );
      final call = calls.last;
      expect(call.method, 'zonedSchedule');
      final args = call.arguments as Map;
      expect(args['id'], 7);
      expect(args['title'], 'নিয়োগ');
      expect(args['payload'], 'long-full-job-id');
      expect(args['timeZoneName'], 'Etc/UTC');
      expect(args['scheduledDateTime'], startsWith('2035-06-15T12:30:00'));
      final specifics = args['platformSpecifics'] as Map;
      expect(specifics['scheduleMode'], 'inexactAllowWhileIdle');
      expect(specifics['icon'], 'ic_stat_karmopath');
      expect(specifics['channelId'], 'karmopath.deadlines.v1');
      expect(specifics['channelName'], 'Deadline reminders');
      expect(calls.any((c) => c.method.contains('Permission')), isFalse);
    },
  );
  test(
    'cancel is scoped to one ID; closing never cancels durable reminders',
    () async {
      await driver.initialize();
      await driver.cancel(7);
      expect(calls.last.method, 'cancel');
      expect((calls.last.arguments as Map)['id'], 7);
      await driver.close();
      await driver.close();
      expect(calls.map((c) => c.method), ['initialize', 'cancel']);
      await expectLater(driver.pendingIds(), throwsStateError);
      await expectLater(driver.initialize(), throwsStateError);
    },
  );
}
