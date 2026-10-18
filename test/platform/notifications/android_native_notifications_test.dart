import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/native_reminders.dart';
import 'package:karmopath/data/reminders/native_reminder_payload.dart';
import 'package:karmopath/platform/notifications/android_native_notifications.dart';

const channel = MethodChannel('dexterous.com/flutter/local_notifications');
final due = DateTime.utc(2099, 10, 19, 4, 30);

NativeReminderIdentity makeIdentity() => NativeReminderIdentity(
  jobId: List.filled(100, 'a').join(),
  dueAtUtc: due,
  closesAtUtc: due.add(const Duration(days: 1)),
  contentKey: 'বাংলা। English 🔔',
  payloadVariant: 'bn@reminder-v1',
);

NativeReminderRequest makeRequest() => NativeReminderRequest(
  platformId: 37,
  identity: makeIdentity(),
  title: 'নিয়োগ।',
  body: 'মূল বিজ্ঞপ্তি দেখে নিন।',
);

// Deliberately bypass constructors to verify boundary validation.
class UncheckedRequest implements NativeReminderRequest {
  UncheckedRequest({
    this.platformId = 37,
    this.title = 'Title',
    this.body = 'Body',
    NativeReminderIdentity? identity,
  }) : identity = identity ?? makeIdentity();
  @override
  final int platformId;
  @override
  final String title;
  @override
  final String body;
  @override
  final NativeReminderIdentity identity;
}

class UncheckedIdentity implements NativeReminderIdentity {
  @override
  String get jobId => 'invalid ID';
  @override
  DateTime get dueAtUtc => due;
  @override
  DateTime get closesAtUtc => due.add(const Duration(days: 1));
  @override
  String get contentKey => 'content';
  @override
  String get payloadVariant => 'en@reminder-v1';
}

class ChannelHarness {
  final calls = <MethodCall>[];
  final records = <Map<String, Object?>>[];
  Object? launch;
  Completer<Object?>? launchWait;
  Completer<void>? launchRequested;
  bool? enabled = true;
  bool? promptResult = true;
  bool initialized = true;
  String? failMethod;
  Completer<bool?>? permissionWait;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    if (call.method == failMethod) {
      throw PlatformException(code: 'native_failure', message: call.method);
    }
    switch (call.method) {
      case 'initialize':
        return initialized;
      case 'getNotificationAppLaunchDetails':
        launchRequested?.complete();
        return launchWait == null ? launch : await launchWait!.future;
      case 'areNotificationsEnabled':
        return permissionWait == null ? enabled : await permissionWait!.future;
      case 'requestNotificationsPermission':
        return promptResult;
      case 'pendingNotificationRequests':
        return records;
      case 'zonedSchedule':
        final args = Map<String, Object?>.from(call.arguments as Map);
        records.add({
          'id': args['id'],
          'title': args['title'],
          'body': args['body'],
          'payload': args['payload'],
        });
        return null;
      case 'cancel':
        records.removeWhere((record) => record['id'] == call.arguments['id']);
        return null;
      default:
        throw StateError('Unexpected plugin method: ${call.method}');
    }
  }

  List<String> get methods => calls.map((call) => call.method).toList();

  void coldTap(String? payload, {bool launched = true}) {
    launch = {
      'notificationLaunchedApp': launched,
      'notificationResponse': {
        'notificationId': 37,
        'notificationResponseType': 0,
        'payload': payload,
      },
    };
  }
}

Future<void> foregroundTap(String? payload) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('didReceiveNotificationResponse', {
            'notificationId': 37,
            'notificationResponseType': 0,
            'payload': payload,
          }),
        ),
        (_) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChannelHarness harness;
  late AndroidNativeNotifications backend;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    harness = ChannelHarness();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, harness.handle);
    backend = AndroidNativeNotifications(
      nowUtc: () => due.subtract(const Duration(days: 1)),
    );
  });

  tearDown(() async {
    await backend.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'default real plugin initializes without prompting and can be reused',
    () async {
      final taps = <String>[];
      harness.coldTap(encodeNativeReminderPayload(makeIdentity()));
      await backend.initialize(onJobTap: taps.add);
      await backend.initialize(onJobTap: taps.add);
      expect(taps, [makeIdentity().jobId]);
      expect(harness.methods, [
        'initialize',
        'getNotificationAppLaunchDetails',
      ]);
      expect(harness.calls.first.arguments['defaultIcon'], reminderAndroidIcon);
    },
  );

  test('initialization failures and false results are retryable', () async {
    for (final failingMethod in [
      'initialize',
      'getNotificationAppLaunchDetails',
    ]) {
      harness.failMethod = failingMethod;
      await expectLater(
        backend.initialize(onJobTap: (_) {}),
        throwsA(isA<PlatformException>()),
      );
      harness.failMethod = null;
    }
    harness.initialized = false;
    await expectLater(backend.initialize(onJobTap: (_) {}), throwsStateError);
    harness.initialized = true;
    await backend.initialize(onJobTap: (_) {});
    expect(harness.methods.where((name) => name == 'initialize').length, 4);
  });

  test(
    'only valid managed foreground and cold taps forward full IDs',
    () async {
      final taps = <String>[];
      final malformed = jsonEncode({'namespace': reminderPayloadNamespace});
      final invalidPayloads = <String?>[
        null,
        '',
        'bad',
        '{}',
        malformed,
        jsonEncode({'namespace': 'foreign', 'job_id': 'invented'}),
      ];
      for (final payload in invalidPayloads) {
        final instance = AndroidNativeNotifications();
        harness.coldTap(payload);
        await instance.initialize(onJobTap: taps.add);
        await foregroundTap(payload);
        expect(taps, isEmpty);
        await instance.dispose();
      }
      harness.coldTap(encodeNativeReminderPayload(makeIdentity()));
      await backend.initialize(onJobTap: taps.add);
      await foregroundTap(encodeNativeReminderPayload(makeIdentity()));
      expect(taps, [makeIdentity().jobId, makeIdentity().jobId]);
      await backend.dispose();
      await foregroundTap(encodeNativeReminderPayload(makeIdentity()));
      expect(taps.length, 2);
    },
  );

  test(
    'cold response is ignored when app was not notification-launched',
    () async {
      harness.coldTap(
        encodeNativeReminderPayload(makeIdentity()),
        launched: false,
      );
      final taps = <String>[];
      await backend.initialize(onJobTap: taps.add);
      expect(taps, isEmpty);
    },
  );

  test('passive permission maps true false null and never prompts', () async {
    for (final pair in [
      (true, ReminderPermission.granted),
      (false, ReminderPermission.denied),
      (null, ReminderPermission.unavailable),
    ]) {
      harness.enabled = pair.$1;
      expect(await backend.permissionStatus(), pair.$2);
    }
    expect(harness.methods, List.filled(3, 'areNotificationsEnabled'));
  });

  test(
    'explicit request uses subsequent status, not prompt return value',
    () async {
      harness.promptResult = true;
      harness.enabled = false;
      expect(await backend.requestPermission(), ReminderPermission.denied);
      harness.promptResult = false;
      harness.enabled = true;
      expect(await backend.requestPermission(), ReminderPermission.granted);
      harness.promptResult = null;
      harness.enabled = null;
      expect(await backend.requestPermission(), ReminderPermission.unavailable);
      expect(harness.methods, [
        'requestNotificationsPermission',
        'areNotificationsEnabled',
        'requestNotificationsPermission',
        'areNotificationsEnabled',
        'requestNotificationsPermission',
        'areNotificationsEnabled',
      ]);
    },
  );

  test(
    'pending preserves every OS ID including foreign and malformed',
    () async {
      harness.records.addAll([
        {'id': 37, 'payload': encodeNativeReminderPayload(makeIdentity())},
        {'id': 0, 'payload': 'foreign'},
        {
          'id': -7,
          'payload': jsonEncode({'namespace': reminderPayloadNamespace}),
        },
        {'id': 2147483647, 'payload': null},
      ]);
      final pending = await backend.pendingReminders();
      expect(pending.map((record) => record.platformId), [
        37,
        0,
        -7,
        2147483647,
      ]);
      expect(pending.map((record) => record.isManaged), [
        true,
        false,
        true,
        false,
      ]);
      expect(pending.first.identity, makeIdentity());
      expect(
        pending.skip(1).map((record) => record.identity),
        everyElement(isNull),
      );
      expect(harness.methods, ['pendingNotificationRequests']);
    },
  );

  test('schedule uses full codec identity, UTC, existing channel and inexact idle mode', () async {
    await backend.initialize(onJobTap: (_) {});
    await backend.schedule(makeRequest());
    final call = harness.calls.last;
    expect(call.method, 'zonedSchedule');
    final args = call.arguments as Map;
    expect(args['id'], 37);
    expect(args['title'], makeRequest().title);
    expect(args['body'], makeRequest().body);
    expect(
      decodeNativeReminderPayload(args['payload'] as String).identity,
      makeIdentity(),
    );
    expect(args['timeZoneName'], 'Etc/UTC');
    expect(args['scheduledDateTime'], '2099-10-19T04:30:00');
    expect(args.containsKey('matchDateTimeComponents'), isFalse);
    final specifics = args['platformSpecifics'] as Map;
    expect(specifics['channelId'], reminderAndroidChannelId);
    expect(specifics['channelName'], reminderAndroidChannelName);
    expect(specifics['icon'], reminderAndroidIcon);
    expect(specifics['importance'], Importance.defaultImportance.value);
    expect(specifics['scheduleMode'], 'inexactAllowWhileIdle');
    expect(specifics['fullScreenIntent'], isFalse);
    expect(specifics['channelBypassDnd'], isFalse);
    expect(harness.methods, [
      'initialize',
      'getNotificationAppLaunchDetails',
      'areNotificationsEnabled',
      'zonedSchedule',
    ]);
  });

  test(
    'schedule revalidates ID, title, body and identity before plugin calls',
    () async {
      for (final request in [
        UncheckedRequest(platformId: 0),
        UncheckedRequest(platformId: -1),
        UncheckedRequest(platformId: 2147483648),
        UncheckedRequest(title: '  '),
        UncheckedRequest(body: ''),
        UncheckedRequest(identity: UncheckedIdentity()),
      ]) {
        await expectLater(backend.schedule(request), throwsArgumentError);
      }
      expect(harness.calls, isEmpty);
    },
  );

  test(
    'schedule rejects denied and unknown permission without prompting',
    () async {
      for (final enabled in [false, null]) {
        harness.enabled = enabled;
        await expectLater(backend.schedule(makeRequest()), throwsStateError);
      }
      expect(harness.methods, [
        'areNotificationsEnabled',
        'areNotificationsEnabled',
      ]);
    },
  );

  test(
    'due time equal to or before clock fails before permission query',
    () async {
      for (final clock in [due, due.add(const Duration(seconds: 1))]) {
        final instance = AndroidNativeNotifications(nowUtc: () => clock);
        await expectLater(instance.schedule(makeRequest()), throwsStateError);
        await instance.dispose();
      }
      expect(harness.calls, isEmpty);
    },
  );

  test('due time is rechecked after asynchronous permission query', () async {
    var clock = due.subtract(const Duration(seconds: 1));
    final instance = AndroidNativeNotifications(nowUtc: () => clock);
    harness.permissionWait = Completer<bool?>();
    final scheduling = instance.schedule(makeRequest());
    final assertion = expectLater(scheduling, throwsStateError);
    clock = due;
    harness.permissionWait!.complete(true);
    await assertion;
    expect(harness.methods, ['areNotificationsEnabled']);
    await instance.dispose();
  });

  test(
    'cancel is per-ID, repeatable, and validates the reserved ID range',
    () async {
      await backend.schedule(makeRequest());
      await backend.cancel(37);
      await backend.cancel(37);
      expect(harness.records, isEmpty);
      expect(
        harness.calls
            .where((call) => call.method == 'cancel')
            .map((call) => call.arguments['id']),
        [37, 37],
      );
      for (final id in [0, -1, 2147483648]) {
        await expectLater(backend.cancel(id), throwsArgumentError);
      }
      expect(harness.methods.contains('cancelAll'), isFalse);
    },
  );

  test(
    'dispose drops callbacks, preserves schedules and rejects later operations',
    () async {
      await backend.initialize(onJobTap: (_) => fail('callback after dispose'));
      await backend.schedule(makeRequest());
      final before = harness.calls.length;
      await backend.dispose();
      await backend.dispose();
      await foregroundTap(encodeNativeReminderPayload(makeIdentity()));
      expect(harness.records.single['id'], 37);
      expect(harness.calls.length, before);
      await expectLater(backend.initialize(onJobTap: (_) {}), throwsStateError);
      await expectLater(backend.schedule(makeRequest()), throwsStateError);
      await expectLater(backend.cancel(37), throwsStateError);
      await expectLater(backend.pendingReminders(), throwsStateError);
      await expectLater(backend.permissionStatus(), throwsStateError);
      await expectLater(backend.requestPermission(), throwsStateError);
    },
  );

  test('dispose during permission await prevents scheduling', () async {
    harness.permissionWait = Completer<bool?>();
    final scheduling = backend.schedule(makeRequest());
    final assertion = expectLater(scheduling, throwsStateError);
    await backend.dispose();
    harness.permissionWait!.complete(true);
    await assertion;
    expect(harness.methods, ['areNotificationsEnabled']);
  });

  test('unsupported platforms never invoke Android APIs', () async {
    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.fuchsia,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      await backend.initialize(onJobTap: (_) => fail('unsupported tap'));
      expect(await backend.permissionStatus(), ReminderPermission.unsupported);
      expect(await backend.requestPermission(), ReminderPermission.unsupported);
      await expectLater(backend.pendingReminders(), throwsUnsupportedError);
      await expectLater(
        backend.schedule(makeRequest()),
        throwsUnsupportedError,
      );
      await expectLater(backend.cancel(37), throwsUnsupportedError);
    }
    expect(harness.calls, isEmpty);
  });

  test(
    'native failures remain failures, not empty lists or assumed success',
    () async {
      for (final operation in <String, Future<Object?> Function()>{
        'areNotificationsEnabled': backend.permissionStatus,
        'requestNotificationsPermission': backend.requestPermission,
        'pendingNotificationRequests': backend.pendingReminders,
        'zonedSchedule': () => backend.schedule(makeRequest()),
        'cancel': () => backend.cancel(37),
      }.entries) {
        harness.failMethod = operation.key;
        await expectLater(
          operation.value(),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'native_failure',
            ),
          ),
        );
      }
    },
  );

  test('concurrent initialization shares one attempt; dispose drops delayed cold tap', () async {
    harness.coldTap(encodeNativeReminderPayload(makeIdentity()));
    harness.launchWait = Completer<Object?>();
    harness.launchRequested = Completer<void>();
    final taps = <String>[];
    final first = backend.initialize(onJobTap: taps.add);
    final second = backend.initialize(onJobTap: taps.add);
    await harness.launchRequested!.future;
    await backend.dispose();
    harness.launchWait!.complete(harness.launch);
    await Future.wait([first, second]);
    await foregroundTap(encodeNativeReminderPayload(makeIdentity()));
    expect(taps, isEmpty);
    expect(harness.methods, ['initialize', 'getNotificationAppLaunchDetails']);
  });
}
