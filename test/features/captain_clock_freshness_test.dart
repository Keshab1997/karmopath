import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/features/common/deadline_clock.dart';

void main() {
  testWidgets('new feed rebuild uses wall clock, not last timer tick', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 11, 1);
    final ticker = DeadlineTicker(now: () => now);
    ticker.watch([now.add(const Duration(days: 1))]);
    now = now.add(const Duration(hours: 1));
    expect(ticker.now, now);
    final closes = now.add(const Duration(seconds: 5));
    var ticks = 0;
    ticker.addListener(() {
      ticks++;
    });
    ticker.watch([closes]);
    now = closes;
    await tester.pump(const Duration(seconds: 5));
    expect(ticks, 1);
    ticker.dispose();
  });
}
