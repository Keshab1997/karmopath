import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/app_actions.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/features/calendar/calendar_screen.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/common/deadline_clock.dart';
import 'package:karmopath/features/common/formatting.dart';
import 'package:karmopath/features/common/reminder_controller.dart';
import 'package:karmopath/features/common/strings.dart';
import 'package:karmopath/features/home/home_screen.dart';
import 'package:karmopath/features/job_detail/job_detail_screen.dart';
import 'package:karmopath/features/saved/saved_screen.dart';

import 'support/fakes.dart';
import 'support/test_clock.dart';

/// Permission that takes [delay] of wall time, letting a deadline pass while
/// the system dialog is open.
class SlowPermissionActions implements AppActions {
  SlowPermissionActions({required this.delay, this.granted = true});

  final Duration delay;
  final bool granted;
  int requests = 0;

  @override
  Future<void> openExternal(Uri uri) async {}

  @override
  Future<bool> requestReminderPermission() async {
    requests += 1;
    await Future<void>.delayed(delay);
    return granted;
  }
}

/// Permission that advances a test clock by [advance] and returns at once.
/// Used for controller unit tests, where real/fake async delays would only
/// slow the suite down without adding a race.
class AdvancingPermissionActions implements AppActions {
  AdvancingPermissionActions({
    required this.clock,
    required this.advance,
    this.granted = true,
  });

  final TestClock clock;
  final Duration advance;
  final bool granted;
  int requests = 0;

  @override
  Future<void> openExternal(Uri uri) async {}

  @override
  Future<bool> requestReminderPermission() async {
    requests += 1;
    clock.value = clock.value.add(advance);
    return granted;
  }
}

void main() {
  // Fixed instant: 2026-11-15 17:50 UTC == 23:20 IST.
  final base = DateTime.utc(2026, 11, 15, 17, 50);
  late TestClock clock;

  setUp(() {
    appLanguage.value = AppLang.bn;
    clock = TestClock(base);
    clock.install();
  });

  tearDown(() {
    DeadlineClock.overrideNow(null);
    appLanguage.value = AppLang.bn;
  });

  Widget detail(Job job, {FakePreferences? prefs, AppActions? actions}) =>
      JobDetailScreen(
        job: job,
        preferences: prefs ?? FakePreferences(),
        actions: actions ?? FakeActions(),
      );

  Widget home(Job job, {FakePreferences? prefs}) => HomeScreen(
    repository: FakeJobRepository(readyState([job])),
    preferences: prefs ?? FakePreferences(),
    onOpenJob: (_) {},
  );

  Widget calendar(Job job, {FakePreferences? prefs}) => CalendarScreen(
    repository: FakeJobRepository(readyState([job])),
    preferences: prefs ?? FakePreferences(),
    onOpenJob: (_) {},
  );

  group('exact deadline while the screen stays open', () {
    testWidgets('detail flips to closed without a feed refresh or tap', (
      tester,
    ) async {
      final job = makeJob(
        applicationEndAt: base.add(const Duration(minutes: 5)),
      );
      await pumpScreen(tester, detail(job));

      expect(find.textContaining('আবেদনের সময় শেষ'), findsNothing);
      expect(find.text('চাকরির বিবরণ'), findsOneWidget);

      await clock.advance(tester, const Duration(minutes: 6));

      expect(find.textContaining('আবেদনের সময় শেষ'), findsOneWidget);
      final reminder = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'রিমাইন্ডার দিন'),
      );
      expect(reminder.onPressed, isNull);
    });

    testWidgets('exact expiry still open one microsecond before the instant', (
      tester,
    ) async {
      final closes = base.add(const Duration(minutes: 5));
      final job = makeJob(applicationEndAt: closes);
      await pumpScreen(tester, detail(job));

      await clock.advance(
        tester,
        const Duration(minutes: 5) - const Duration(microseconds: 1),
      );
      expect(find.textContaining('আবেদনের সময় শেষ'), findsNothing);

      await clock.advance(tester, const Duration(microseconds: 1));
      expect(find.textContaining('আবেদনের সময় শেষ'), findsOneWidget);
    });
  });

  group('date-only deadline at IST midnight', () {
    testWidgets('stays open at 23:59 IST and closes at 00:00 next day', (
      tester,
    ) async {
      // Base is 23:20 IST on 2026-11-15; the named day is inclusive.
      final job = makeJob(applicationEndDate: '2026-11-15');
      await pumpScreen(tester, detail(job));
      expect(find.textContaining('আবেদনের সময় শেষ'), findsNothing);

      // 23:59:59 IST == 18:29:59Z, still inside the inclusive day.
      await clock.advance(tester, const Duration(minutes: 39, seconds: 59));
      expect(find.textContaining('আবেদনের সময় শেষ'), findsNothing);

      // 00:00 IST next day == 18:30Z closes it.
      await clock.advance(tester, const Duration(seconds: 1));
      expect(find.textContaining('আবেদনের সময় শেষ'), findsOneWidget);
      // Closed label keeps the date and invents no closing time.
      final info = deadlineInfo(job, clock.value);
      expect(info.expired, isTrue);
    });
  });

  group('home and filters advance with the clock', () {
    testWidgets('closing-soon filter picks the job up as the window opens', (
      tester,
    ) async {
      final job = makeJob(
        applicationEndAt: base.add(const Duration(days: 3, hours: 1)),
      );
      await pumpScreen(tester, home(job), surfaceSize: const Size(420, 1400));

      final chip = find.text('শেষ হচ্ছে');
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pump();
      expect(find.text('কোনো মিল পাওয়া যায়নি'), findsOneWidget);

      // Two hours later the three-day window has opened.
      await clock.advance(tester, const Duration(hours: 2));

      expect(find.text('কোনো মিল পাওয়া যায়নি'), findsNothing);
      expect(find.text(job.titleBn), findsOneWidget);
    });

    testWidgets('card status label turns closed after expiry', (tester) async {
      final job = makeJob(
        applicationEndAt: base.add(const Duration(minutes: 30)),
      );
      await pumpScreen(tester, home(job), surfaceSize: const Size(420, 1400));
      expect(find.textContaining('দিনে শেষ হচ্ছে'), findsNothing);
      expect(find.textContaining('ঘণ্টায় শেষ হচ্ছে'), findsNothing);

      await clock.advance(tester, const Duration(minutes: 31));

      expect(find.textContaining('বন্ধ হয়েছে'), findsOneWidget);
    });

    testWidgets('saved list also refreshes its deadine state', (tester) async {
      final job = makeJob(
        applicationEndAt: base.add(const Duration(minutes: 10)),
      );
      await pumpScreen(
        tester,
        SavedScreen(
          repository: FakeJobRepository(readyState([job])),
          preferences: FakePreferences(saved: {job.id}),
          onOpenJob: (_) {},
        ),
        surfaceSize: const Size(420, 1200),
      );
      expect(find.textContaining('বন্ধ হয়েছে'), findsNothing);

      await clock.advance(tester, const Duration(minutes: 11));
      expect(find.textContaining('বন্ধ হয়েছে'), findsOneWidget);
    });
  });

  group('calendar recomputes without a feed refresh', () {
    testWidgets('expired entry leaves Upcoming and appears in All', (
      tester,
    ) async {
      final job = makeJob(applicationEndAt: base.add(const Duration(hours: 1)));
      await pumpScreen(
        tester,
        calendar(job),
        surfaceSize: const Size(420, 1400),
      );
      expect(find.text(job.titleBn), findsOneWidget);

      await clock.advance(tester, const Duration(hours: 2));

      // Upcoming is now empty but the feed still has the job.
      expect(find.text(job.titleBn), findsNothing);
      expect(find.text('সামনের কোনো শেষ তারিখ নেই'), findsOneWidget);

      // The empty state offers an "All" action; tap it (it flips the scope).
      expect(find.text('সামনের কোনো শেষ তারিখ নেই'), findsOneWidget);
      await tester.tap(find.text('সব').last);
      await tester.pump();
      expect(find.text(job.titleBn), findsOneWidget);
      expect(find.textContaining('বন্ধ হয়েছে'), findsOneWidget);
    });

    testWidgets('month heading follows the IST day of the deadline', (
      tester,
    ) async {
      // 2026-11-15 23:59 IST is still November, then rolls into 16 November.
      final job = makeJob(applicationEndDate: '2026-11-15');
      await pumpScreen(
        tester,
        calendar(job),
        surfaceSize: const Size(420, 1400),
      );
      expect(find.text('নভেম্বর ২০২৬'), findsOneWidget);

      await clock.advance(tester, const Duration(minutes: 41));
      // Deadline passed; only the All scope still lists it, under November.
      expect(find.text('সামনের কোনো শেষ তারিখ নেই'), findsOneWidget);
      await tester.tap(find.text('সব').last);
      await tester.pump();
      expect(find.text('নভেম্বর ২০২৬'), findsOneWidget);
    });
  });

  group('app resume', () {
    testWidgets('resume after sleeping through the timer recomputes at once', (
      tester,
    ) async {
      final job = makeJob(applicationEndAt: base.add(const Duration(hours: 1)));
      await pumpScreen(tester, detail(job));
      expect(find.textContaining('আবেদনের সময় শেষ'), findsNothing);

      // Suspended: wall clock moves, timers never run.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await clock.jumpWithoutTimers(tester, const Duration(hours: 2));
      expect(find.textContaining('আবেদনের সময় শেষ'), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.textContaining('আবেদনের সময় শেষ'), findsOneWidget);
    });

    testWidgets('resume without a deadline change keeps the open state', (
      tester,
    ) async {
      final job = makeJob(applicationEndAt: base.add(const Duration(days: 5)));
      await pumpScreen(tester, detail(job));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await clock.jumpWithoutTimers(tester, const Duration(minutes: 20));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.textContaining('আবেদনের সময় শেষ'), findsNothing);
      expect(find.text('রিমাইন্ডার দিন'), findsOneWidget);
    });

    testWidgets('calendar resume past a deadline moves the entry', (
      tester,
    ) async {
      final job = makeJob(
        applicationEndAt: base.add(const Duration(minutes: 30)),
      );
      await pumpScreen(
        tester,
        calendar(job),
        surfaceSize: const Size(420, 1400),
      );
      expect(find.text(job.titleBn), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await clock.jumpWithoutTimers(tester, const Duration(hours: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.text(job.titleBn), findsNothing);
      expect(find.text('সামনের কোনো শেষ তারিখ নেই'), findsOneWidget);
    });
  });

  group('permission dialog outliving the deadline', () {
    test(
      'controller refuses to persist an enable intent after expiry',
      () async {
        final job = makeJob(
          applicationEndAt: base.add(const Duration(minutes: 2)),
        );
        final prefs = FakePreferences();
        final actions = AdvancingPermissionActions(
          clock: clock,
          advance: const Duration(minutes: 5),
        );

        final outcome = await setReminderIntent(
          preferences: prefs,
          actions: actions,
          jobId: job.id,
          enable: true,
          deadline: deadlineInfo(job, clock.value),
          deadlineAt: (now) => deadlineInfo(job, now),
          now: clock.now,
        );

        expect(outcome, ReminderOutcome.closed);
        expect(actions.requests, 1);
        expect(prefs.reminderCalls, isEmpty);
        expect(prefs.reminderJobIds.value, isEmpty);
      },
    );

    test(
      'controller still enables when permission returns before expiry',
      () async {
        final job = makeJob(
          applicationEndAt: base.add(const Duration(hours: 2)),
        );
        final prefs = FakePreferences();
        final actions = AdvancingPermissionActions(
          clock: clock,
          advance: const Duration(minutes: 5),
        );

        final outcome = await setReminderIntent(
          preferences: prefs,
          actions: actions,
          jobId: job.id,
          enable: true,
          deadline: deadlineInfo(job, clock.value),
          deadlineAt: (now) => deadlineInfo(job, now),
          now: clock.now,
        );

        expect(outcome, ReminderOutcome.enabled);
        expect(prefs.reminderCalls, [(job.id, true)]);
      },
    );

    testWidgets('detail shows the closed message and writes nothing', (
      tester,
    ) async {
      final closes = base.add(const Duration(minutes: 2));
      final job = makeJob(applicationEndAt: closes);
      final prefs = FakePreferences();
      final actions = SlowPermissionActions(delay: const Duration(minutes: 5));
      await pumpScreen(tester, detail(job, prefs: prefs, actions: actions));

      await tester.tap(find.text('রিমাইন্ডার দিন'));
      await tester.pump();
      // The permission dialog stays open while wall time passes the deadline.
      clock.value = clock.value.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      await tester.pump();

      expect(actions.requests, 1);
      expect(prefs.reminderCalls, isEmpty);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(K.reminderClosedMsg.bn),
        ),
        findsOneWidget,
      );
      // The page itself has also re-rendered as closed.
      expect(find.textContaining('আবেদনের সময় শেষ'), findsOneWidget);
    });

    testWidgets('denied permission after expiry stays a denial, no write', (
      tester,
    ) async {
      final job = makeJob(
        applicationEndAt: base.add(const Duration(minutes: 2)),
      );
      final prefs = FakePreferences();
      await pumpScreen(
        tester,
        detail(job, prefs: prefs, actions: FakeActions(permission: false)),
      );

      await tester.tap(find.text('রিমাইন্ডার দিন'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(prefs.reminderCalls, isEmpty);
      expect(find.text(K.reminderDeniedMsg.bn), findsOneWidget);
    });
  });

  group('teardown', () {
    testWidgets('disposing screens leaves no live ticker or pending timer', (
      tester,
    ) async {
      final job = makeJob(applicationEndAt: base.add(const Duration(days: 2)));
      await pumpScreen(tester, detail(job));
      expect(DeadlineTicker.debugLiveTickers, 1);

      await pumpScreen(tester, home(job));
      expect(DeadlineTicker.debugLiveTickers, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(DeadlineTicker.debugLiveTickers, 0);
      expect(tester.binding.transientCallbackCount, 0);
      // Time passing after disposal must not fire anything.
      await tester.pump(const Duration(days: 3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('every screen owns exactly one ticker while mounted', (
      tester,
    ) async {
      final job = makeJob(applicationEndAt: base.add(const Duration(days: 2)));
      await pumpScreen(tester, calendar(job));
      expect(DeadlineTicker.debugLiveTickers, 1);

      await pumpScreen(
        tester,
        SavedScreen(
          repository: FakeJobRepository(readyState([job])),
          preferences: FakePreferences(saved: {job.id}),
          onOpenJob: (_) {},
        ),
      );
      expect(DeadlineTicker.debugLiveTickers, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(DeadlineTicker.debugLiveTickers, 0);
    });
  });

  group('clock plumbing', () {
    test('watch instants include the closing-soon start and the deadline', () {
      final closes = base.add(const Duration(days: 10));
      final job = makeJob(applicationEndAt: closes);
      final instants = deadlineWatchInstants([job], base).toList();

      expect(instants, contains(closes));
      expect(instants, contains(closes.subtract(const Duration(days: 3))));
      // Always at least the next IST midnight for relative labels.
      expect(instants, contains(nextIstMidnightUtc(base)));
    });

    test('next IST midnight is 18:30Z regardless of the input offset', () {
      expect(
        nextIstMidnightUtc(DateTime.utc(2026, 11, 15, 17, 50)),
        DateTime.utc(2026, 11, 15, 18, 30),
      );
      expect(
        nextIstMidnightUtc(DateTime.utc(2026, 11, 15, 18, 30)),
        DateTime.utc(2026, 11, 16, 18, 30),
      );
    });
  });

  group('app name', () {
    test('Bengali product name is কর্মপথ everywhere in B copy', () {
      expect(K.appName.bn, 'কর্মপথ');
      expect(K.disclaimerBn, startsWith('কর্মপথ '));
      expect(K.appName.bn.contains('কার্মপথ'), isFalse);
    });

    testWidgets('home header renders the corrected spelling', (tester) async {
      final job = makeJob(applicationEndAt: base.add(const Duration(days: 3)));
      await pumpScreen(tester, home(job));
      expect(find.textContaining('কর্মপথ'), findsOneWidget);
      expect(find.textContaining('কার্মপথ'), findsNothing);
    });
  });
}
