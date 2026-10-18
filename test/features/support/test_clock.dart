import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/features/common/deadline_clock.dart';

/// Deterministic clock for deadline tests.
///
/// Installs itself through [DeadlineClock.overrideNow] and moves in lockstep
/// with the widget tester's fake async clock, so a scheduled ticker fires at
/// exactly the instants the test intends.
class TestClock {
  TestClock(this.value);

  DateTime value;

  DateTime now() => value;

  /// Installs this clock as the app clock.
  void install() => DeadlineClock.overrideNow(now);

  /// Advances wall time and the fake async clock together.
  Future<void> advance(WidgetTester tester, Duration delta) async {
    value = value.add(delta);
    await tester.pump(delta);
    await tester.pump();
  }

  /// Jumps wall time without letting scheduled timers run, simulating a
  /// suspended app that slept through its timer.
  Future<void> jumpWithoutTimers(WidgetTester tester, Duration delta) async {
    value = value.add(delta);
    await tester.pump();
  }
}
