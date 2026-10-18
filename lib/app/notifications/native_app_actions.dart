import 'dart:async';

import '../../contracts/app_actions.dart';
import '../../contracts/native_reminders.dart';

/// Explicit user actions; neither construction nor runtime startup prompts.
/// External URL launching is required/injected, never a fake successful no-op.
class NativeAppActions implements AppActions {
  NativeAppActions({required this._notifications, required this._openExternal});

  final NativeNotifications _notifications;
  final Future<void> Function(Uri uri) _openExternal;
  Future<bool>? _permissionRequest;
  bool _closed = false;

  void _requireOpen() {
    if (_closed) throw StateError('Runtime actions are closed');
  }

  @override
  Future<void> openExternal(Uri uri) async {
    _requireOpen();
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        RegExp(r'\s').hasMatch(uri.toString())) {
      throw ArgumentError.value(uri, 'uri', 'public HTTPS link required');
    }
    await _openExternal(uri);
  }

  @override
  Future<bool> requestReminderPermission() {
    if (_closed) return Future<bool>.error(StateError('Actions are closed'));
    final running = _permissionRequest;
    if (running != null) return running;
    final attempt = Completer<bool>();
    _permissionRequest = attempt.future;
    unawaited(_request(attempt));
    return attempt.future;
  }

  Future<void> _request(Completer<bool> attempt) async {
    try {
      var permission = await _notifications.permissionStatus();
      _requireOpen();
      if (permission != ReminderPermission.granted) {
        permission = await _notifications.requestPermission();
        _requireOpen();
        if (permission == ReminderPermission.granted) {
          permission = await _notifications.permissionStatus();
        }
      }
      _requireOpen();
      attempt.complete(permission == ReminderPermission.granted);
    } catch (error, stack) {
      attempt.completeError(error, stack);
    } finally {
      _permissionRequest = null;
    }
  }

  void close() => _closed = true;
}
