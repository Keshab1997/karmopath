import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/app/notifications/native_app_actions.dart';
import 'package:karmopath/contracts/native_reminders.dart';

import '../support/native_test_support.dart';

void main() {
  late FakeNativeNotificationBackend driver;
  late NativeAppActions actions;
  late List<Uri> opened;
  setUp(() {
    driver = FakeNativeNotificationBackend();
    opened = [];
    actions = NativeAppActions(
      notifications: driver,
      openExternal: (uri) async => opened.add(uri),
    );
  });
  test(
    'construction never prompts; existing permission skips prompt',
    () async {
      expect(driver.events, isEmpty);
      expect(await actions.requestReminderPermission(), isTrue);
      expect(driver.permissionRequests, 0);
    },
  );
  test('denial is false, with no storage or scheduling effects', () async {
    driver.enabled = false;
    driver.permissionResult = ReminderPermission.denied;
    expect(await actions.requestReminderPermission(), isFalse);
    expect(driver.permissionRequests, 1);
    expect(driver.scheduled, isEmpty);
  });
  test('grant is rechecked against actual enabled state', () async {
    driver.enabled = false;
    expect(await actions.requestReminderPermission(), isTrue);
    expect(driver.events, [
      'driver.enabled',
      'driver.request',
      'driver.enabled',
    ]);
  });
  test('concurrent requests share one permission dialog', () async {
    driver.enabled = false;
    final gate = Completer<ReminderPermission>();
    driver.permissionGate = gate.future;
    final first = actions.requestReminderPermission();
    final second = actions.requestReminderPermission();
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(driver.permissionRequests, 1);
    gate.complete(ReminderPermission.granted);
    expect(await first, isTrue);
    expect(await second, isTrue);
  });
  test(
    'permission-query failure propagates and next request can retry',
    () async {
      final error = StateError('channel unavailable');
      driver.queryError = error;
      await expectLater(
        actions.requestReminderPermission(),
        throwsA(same(error)),
      );
      driver.queryError = null;
      expect(await actions.requestReminderPermission(), isTrue);
    },
  );
  test('late grant after close cannot enable a stored intent', () async {
    driver.enabled = false;
    final gate = Completer<ReminderPermission>();
    driver.permissionGate = gate.future;
    final request = actions.requestReminderPermission();
    final assertion = expectLater(request, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    actions.close();
    gate.complete(ReminderPermission.granted);
    await assertion;
    await expectLater(actions.requestReminderPermission(), throwsStateError);
  });
  test(
    'external launch uses explicit HTTPS URL; unsafe URLs are refused',
    () async {
      final safe = Uri.parse('https://example.org/official-notice');
      await actions.openExternal(safe);
      expect(opened, [safe]);
      for (final url in [
        'http://example.org',
        'https://user:pass@example.org',
        'https://example.org/#fragment',
        'file:///tmp/a',
        'javascript:alert(1)',
      ]) {
        await expectLater(
          actions.openExternal(Uri.parse(url)),
          throwsArgumentError,
        );
      }
      expect(opened, [safe]);
    },
  );
  test(
    'closed actions do not launch; real launcher failures propagate',
    () async {
      final uri = Uri.parse('https://example.org/notice');
      final error = StateError('launcher unavailable');
      final broken = NativeAppActions(
        notifications: driver,
        openExternal: (_) async => throw error,
      );
      await expectLater(broken.openExternal(uri), throwsA(same(error)));
      actions.close();
      await expectLater(actions.openExternal(uri), throwsStateError);
      expect(opened, isEmpty);
    },
  );
}
