import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../contracts/job_repository.dart';
import '../../contracts/native_reminders.dart';
import '../../contracts/user_preferences.dart';
import '../../features/common/app_language.dart';
import '../../features/common/reminder_sync_status.dart';
import 'runtime_reminder_session.dart';

/// Drives one ordered reconciliation path for feed, stored intent, language,
/// explicit retry, and app resume. Stale cached feed is never used to schedule
/// or cancel native work; permission prompts remain an explicit UI action.
class NativeReminderSession
    implements RuntimeReminderSession, RuntimeReminderStatusSource {
  NativeReminderSession({
    required this.repository,
    required this.preferences,
    required this.synchronizer,
    required AppLang initialLanguage,
  }) : _language = initialLanguage;

  final JobRepository repository;
  final UserPreferences preferences;
  final ReminderSynchronizer synchronizer;
  AppLang _language;

  final ValueNotifier<RuntimeReminderStatus> _status =
      ValueNotifier<RuntimeReminderStatus>(const RuntimeReminderStatus());
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;
  bool _started = false;
  bool _closed = false;
  bool _refreshingForRetry = false;

  @override
  ValueListenable<RuntimeReminderStatus> get status => _status;

  Future<void> get _tailFuture => _tail;

  @override
  Future<void> start() {
    if (_closed) return Future<void>.error(StateError('Session is closed'));
    if (_started) return _tailFuture;
    _started = true;
    repository.state.addListener(_changed);
    preferences.reminderJobIds.addListener(_changed);
    return _request();
  }

  void _changed() {
    if (_closed || _refreshingForRetry) return;
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

  @override
  Future<void> retry() {
    if (_closed) return Future<void>.value();
    if (!_started) {
      return Future<void>.error(StateError('Session is not started'));
    }
    return _enqueue(() async {
      if (_closed) return;
      final current = repository.state.value;
      if (current.feed == null || current.isOffline) {
        _status.value = RuntimeReminderStatus(
          phase: ReminderSyncUiPhase.syncing,
          report: _status.value.report,
        );
        _refreshingForRetry = true;
        try {
          await repository.refresh();
        } catch (error) {
          if (!_closed) {
            _status.value = RuntimeReminderStatus(
              phase: ReminderSyncUiPhase.failed,
              report: _status.value.report,
              error: error,
            );
          }
          return;
        } finally {
          _refreshingForRetry = false;
        }
      }
      await _run();
    });
  }

  Future<void> _request() => _enqueue(_run);

  Future<void> _enqueue(Future<void> Function() task) {
    if (_closed) return Future<void>.value();
    final current = _tail.then((_) => task());
    _tail = current.then<void>((_) {}, onError: (Object _) {});
    return current;
  }

  Future<void> _run() async {
    if (_closed) return;
    final feedState = repository.state.value;
    // During a refresh, wait for its terminal validated/stale state. In
    // particular, never reconcile from a cached feed while it is marked stale.
    if (feedState.isLoading) return;

    final freshFeed = feedState.feed != null && !feedState.isOffline;
    final jobs = freshFeed ? feedState.feed!.jobs : null;
    if (jobs == null && !feedState.isOffline && feedState.lastError == null) {
      // The initial runtime state has no feed yet; the shell will refresh it.
      return;
    }

    _status.value = RuntimeReminderStatus(
      phase: ReminderSyncUiPhase.syncing,
      report: _status.value.report,
    );
    try {
      final report = await synchronizer.synchronize(
        ReminderSyncInput(
          jobs: jobs,
          selectedJobIds: Set<String>.of(preferences.reminderJobIds.value),
          languageCode: _language.name,
        ),
      );
      if (_closed) return;
      final unavailable = !report.feedAvailable;
      final permissionUnknown =
          report.permission == ReminderPermission.unavailable;
      _status.value = RuntimeReminderStatus(
        phase: report.hasFailures || unavailable || permissionUnknown
            ? ReminderSyncUiPhase.failed
            : ReminderSyncUiPhase.idle,
        report: report,
      );
    } catch (error) {
      if (_closed) return;
      _status.value = RuntimeReminderStatus(
        phase: ReminderSyncUiPhase.failed,
        report: _status.value.report,
        error: error,
      );
    }
  }

  @override
  Future<void> close() {
    final closing = _closing;
    if (closing != null) return closing;
    _closed = true;
    if (_started) {
      repository.state.removeListener(_changed);
      preferences.reminderJobIds.removeListener(_changed);
    }
    return _closing = _tail.then((_) async {
      try {
        await synchronizer.close();
      } finally {
        _status.dispose();
      }
    });
  }
}
