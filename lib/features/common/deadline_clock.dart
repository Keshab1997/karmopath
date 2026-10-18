import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../contracts/job.dart';
import 'formatting.dart';

/// Source of "now" for every worker-B deadline surface.
typedef NowProvider = DateTime Function();

/// Feature-local clock seam.
///
/// Screens never read `DateTime.now()` directly, so tests can drive time
/// deterministically without changing any public screen constructor or the
/// shared contracts. Production keeps the real clock.
abstract final class DeadlineClock {
  static NowProvider _provider = DateTime.now;

  /// Current local time.
  static DateTime now() => _provider();

  /// Replaces the clock (tests only); pass null to restore the real clock.
  @visibleForTesting
  static void overrideNow(NowProvider? provider) {
    _provider = provider ?? DateTime.now;
  }
}

/// Rebuilds deadline UI when it can actually change, without polling.
///
/// One instance per mounted screen. It schedules a single timer for the
/// earliest instant at which visible deadline state may change (a deadline
/// expiring, the closing-soon window opening, the next IST day rollover) and
/// recomputes immediately when the app resumes, where a suspended process may
/// have missed the timer entirely.
class DeadlineTicker extends ChangeNotifier with WidgetsBindingObserver {
  DeadlineTicker({NowProvider? now}) {
    _provider = now ?? DeadlineClock.now;
    _now = _provider();
    WidgetsBinding.instance.addObserver(this);
    _liveTickers += 1;
  }

  static int _liveTickers = 0;

  /// Number of mounted tickers; must return to zero after screens are disposed.
  @visibleForTesting
  static int get debugLiveTickers => _liveTickers;

  late final NowProvider _provider;
  late DateTime _now;
  Timer? _timer;
  DateTime? _next;

  /// Read the current clock on every build, including feed/filter rebuilds
  /// between scheduled ticks. The next delay must not use an old snapshot.
  DateTime get now {
    _now = _provider();
    return _now;
  }

  @visibleForTesting
  bool get debugHasPendingTimer => _timer != null;

  /// Registers the instants that can change what the screen shows.
  ///
  /// Called from `build`, so it stays cheap: one comparison per instant and at
  /// most one timer. Instants already in the past are ignored because the
  /// current build has already rendered that state.
  void watch(Iterable<DateTime?> instants) {
    _now = _provider();
    DateTime? earliest;
    for (final instant in instants) {
      if (instant == null) continue;
      final utc = instant.toUtc();
      if (!utc.isAfter(_now)) continue;
      if (earliest == null || utc.isBefore(earliest)) earliest = utc;
    }
    if (earliest == null) {
      _timer?.cancel();
      _timer = null;
      _next = null;
      return;
    }
    if (_timer != null && _next == earliest) return;
    _next = earliest;
    _timer?.cancel();
    final delay = earliest.difference(_now);
    _timer = Timer(delay, _onTick);
  }

  void _onTick() {
    _timer = null;
    _next = null;
    _recompute();
  }

  void _recompute() {
    _now = _provider();
    // Listeners rebuild and call watch() again with the next instants.
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // A suspended process may have slept through the scheduled timer.
    _timer?.cancel();
    _timer = null;
    _next = null;
    _recompute();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _next = null;
    WidgetsBinding.instance.removeObserver(this);
    _liveTickers -= 1;
    super.dispose();
  }
}

/// Start of the next Asia/Kolkata calendar day, as a UTC instant.
DateTime nextIstMidnightUtc(DateTime now) {
  final ist = now.toUtc().add(istOffset);
  final nextDay = DateTime.utc(
    ist.year,
    ist.month,
    ist.day,
  ).add(const Duration(days: 1));
  return nextDay.subtract(istOffset);
}

/// Every instant at which deadline UI built from [jobs] can change:
/// the deadline itself, the start of its three-day "closing soon" window and
/// the next IST day rollover (for relative "posted ..." labels).
///
/// Past instants are harmless: [DeadlineTicker.watch] filters them.
Iterable<DateTime> deadlineWatchInstants(
  Iterable<Job> jobs,
  DateTime now,
) sync* {
  for (final job in jobs) {
    final closes = effectiveClosingUtc(job);
    if (closes == null) continue;
    yield closes.subtract(const Duration(days: 3));
    yield closes;
  }
  yield nextIstMidnightUtc(now);
}
