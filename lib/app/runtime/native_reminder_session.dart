import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../contracts/job_repository.dart';
import '../../contracts/user_preferences.dart';
import '../../data/reminders/reminder_apply.dart';
import '../../data/reminders/reminder_plan.dart';
import '../../features/common/app_language.dart';
import 'runtime_reminder_session.dart';

/// The integration closure captures jobs/language for a single run, builds B's
/// text and opaque variant, then invokes A's pending-aware reconcile method.
/// A missing implementation is not replaced by a successful no-op.
typedef ReconcileNativePlan = Future<ReminderApplyResult> Function(
  ReminderPlan desired,
  AppLang language,
);

class ReminderSessionState {
  const ReminderSessionState({this.result, this.error});
  final ReminderApplyResult? result;
  final Object? error;
  bool get hasFailure =>
      error != null || (result?.failures.isNotEmpty ?? false);
}

/// One ordered reconciliation path for feed, stored intent, language and resume.
/// No permission prompts, real OS calls or user-intent mutations live here.
class NativeReminderSession implements RuntimeReminderSession {
  NativeReminderSession({
    required this._repository,
    required this._preferences,
    required AppLang initialLanguage,
    required this._reconcile,
    DateTime Function()? now,
  }) : _language = initialLanguage,
       _now = now ?? DateTime.now;

  final JobRepository _repository;
  final UserPreferences _preferences;
  final ReconcileNativePlan _reconcile;
  final DateTime Function() _now;
  final _state = ValueNotifier<ReminderSessionState>(
    const ReminderSessionState(),
  );
  AppLang _language;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;
  bool _started = false;
  bool _closed = false;

  ValueListenable<ReminderSessionState> get state => _state;

  @override
  Future<void> start() {
    if (_closed) return Future<void>.error(StateError('Session is closed'));
    if (_started) return _tail;
    _started = true;
    _repository.state.addListener(_changed);
    _preferences.reminderJobIds.addListener(_changed);
    return _request();
  }

  void _changed() {
    // Errors are exposed in state; listener callbacks must not create uncaught
    // asynchronous errors or poison the next refresh/permission-resume attempt.
    unawaited(_request().then<void>((_) {}, onError: (Object _) {}));
  }

  @override
  void languageChanged(AppLang language) {
    if (_closed || _language == language) return;
    _language = language;
    if (_started) _changed();
  }

  @override
  Future<void> resumed() {
    if (_closed) return Future<void>.value();
    if (!_started) {
      return Future<void>.error(StateError('Session is not started'));
    }
    return _request();
  }

  Future<void> _request() {
    if (_closed) return Future<void>.value();
    final task = _tail.then((_) => _run());
    _tail = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  Future<void> _run() async {
    if (_closed) return;
    // No feed/cache yet does not mean every selected job has been removed.
    // Preserve OS reminders and ledger until a validated snapshot is available.
    final feed = _repository.state.value.feed;
    if (feed == null) return;
    try {
      final desired = planReminders(
        jobs: feed.jobs,
        selectedJobIds: Set<String>.of(_preferences.reminderJobIds.value),
        now: _now().toUtc(),
      );
      final language = _language;
      final result = await _reconcile(desired, language);
      if (!_closed) _state.value = ReminderSessionState(result: result);
    } catch (error) {
      if (!_closed) _state.value = ReminderSessionState(error: error);
      rethrow;
    }
  }

  @override
  Future<void> close() {
    final closing = _closing;
    if (closing != null) return closing;
    _closed = true;
    if (_started) {
      _repository.state.removeListener(_changed);
      _preferences.reminderJobIds.removeListener(_changed);
    }
    return _closing = _tail.then((_) => _state.dispose());
  }
}
