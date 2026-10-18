import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/app_actions.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/common/deadline_clock.dart';
import 'package:karmopath/features/common/formatting.dart';
import 'package:karmopath/features/common/reminder_controller.dart';
import 'package:karmopath/features/common/reminder_intent_state.dart';
import 'package:karmopath/features/common/strings.dart';
import 'package:karmopath/features/home/home_screen.dart';
import 'package:karmopath/features/job_detail/job_detail_screen.dart';

import 'support/fakes.dart';
import 'support/test_clock.dart';

/// Permission prompt that runs a script (mutate the job, move the clock)
/// before answering, so a "correction while the prompt is open" is testable.
class ScriptedPermissionActions implements AppActions {
  ScriptedPermissionActions({
    this.granted = true,
    this.throws = false,
    this.delay = Duration.zero,
    this.onRequest,
  });

  final bool granted;
  final bool throws;
  final Duration delay;
  final void Function()? onRequest;
  int requests = 0;

  @override
  Future<void> openExternal(Uri uri) async {}

  @override
  Future<bool> requestReminderPermission() async {
    requests += 1;
    onRequest?.call();
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (throws) throw StateError('permission channel unavailable');
    return granted;
  }
}

const Size phone320 = Size(320, 720);
const double textScale2x = 2.0;

void main() {
  // 2026-11-15 12:00 UTC == 17:30 IST.
  final base = DateTime.utc(2026, 11, 15, 12);
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

  Job jobClosingIn(Duration delta, {String id = 'wb-police-2026'}) => makeJob(
    id: id,
    applicationEndAt: base.add(delta),
    applicationEndDate: null,
  );

  Widget detail(Job job, {FakePreferences? prefs, AppActions? actions}) =>
      JobDetailScreen(
        job: job,
        preferences: prefs ?? FakePreferences(),
        actions: actions ?? FakeActions(),
      );

  Widget home(List<Job> jobs, FakePreferences prefs) => HomeScreen(
    repository: FakeJobRepository(readyState(jobs)),
    preferences: prefs,
    onOpenJob: (_) {},
  );

  Future<ReminderOutcome> enable(
    Job job, {
    required FakePreferences prefs,
    required AppActions actions,
    DateTime? now,
  }) => setReminderIntent(
    preferences: prefs,
    actions: actions,
    jobId: job.id,
    enable: true,
    deadline: deadlineInfo(job, now ?? clock.value),
    deadlineAt: (instant) => deadlineInfo(job, instant),
    now: () => now ?? clock.value,
  );

  group('24-hour cutoff boundaries', () {
    test('the due instant is exactly 24 hours before the deadline', () {
      final closes = DateTime.utc(2026, 11, 18, 12);
      expect(reminderDueAtUtc(closes), DateTime.utc(2026, 11, 17, 12));
    });

    test('one second before the cutoff is still accepted', () async {
      final job = jobClosingIn(const Duration(days: 3));
      final prefs = FakePreferences();
      final actions = FakeActions();
      final cutoff = reminderDueAtUtc(base.add(const Duration(days: 3)));

      final outcome = await enable(
        job,
        prefs: prefs,
        actions: actions,
        now: cutoff.subtract(const Duration(seconds: 1)),
      );

      expect(outcome, ReminderOutcome.enabled);
      expect(actions.permissionRequests, 1);
      expect(prefs.reminderCalls, [(job.id, true)]);
    });

    test(
      'equality with the cutoff is too late: nothing asked, nothing saved',
      () async {
        final job = jobClosingIn(const Duration(days: 3));
        final prefs = FakePreferences();
        final actions = FakeActions();
        final cutoff = reminderDueAtUtc(base.add(const Duration(days: 3)));

        final outcome = await enable(
          job,
          prefs: prefs,
          actions: actions,
          now: cutoff,
        );

        expect(outcome, ReminderOutcome.tooLate);
        expect(actions.permissionRequests, 0);
        expect(prefs.reminderCalls, isEmpty);
        expect(prefs.reminderJobIds.value, isEmpty);
      },
    );

    test(
      'after the cutoff is too late even though the job is still open',
      () async {
        final job = jobClosingIn(const Duration(hours: 30));
        final prefs = FakePreferences();
        final actions = FakeActions();
        final cutoff = reminderDueAtUtc(base.add(const Duration(hours: 30)));

        final outcome = await enable(
          job,
          prefs: prefs,
          actions: actions,
          now: cutoff.add(const Duration(seconds: 1)),
        );

        expect(outcome, ReminderOutcome.tooLate);
        expect(actions.permissionRequests, 0);
        expect(prefs.reminderCalls, isEmpty);
        // The page state is untouched: the job is open and not closed.
        expect(deadlineInfo(job, clock.value).isOpen, isTrue);
      },
    );

    test('a past deadline reports closed, not late', () async {
      final job = jobClosingIn(const Duration(days: -1));
      final prefs = FakePreferences();
      final actions = FakeActions();

      final outcome = await enable(job, prefs: prefs, actions: actions);

      expect(outcome, ReminderOutcome.closed);
      expect(actions.permissionRequests, 0);
      expect(prefs.reminderCalls, isEmpty);
    });

    test(
      'a withdrawn job closes the window before the cutoff is considered',
      () async {
        final job = makeJob(
          status: JobStatus.withdrawn,
          applicationEndAt: base.add(const Duration(days: 10)),
        );
        final prefs = FakePreferences();
        final actions = FakeActions();

        final outcome = await enable(job, prefs: prefs, actions: actions);

        expect(outcome, ReminderOutcome.closed);
        expect(actions.permissionRequests, 0);
        expect(prefs.reminderCalls, isEmpty);
      },
    );
  });

  group('date-only deadlines use the IST closing boundary', () {
    // 2026-11-20 (inclusive) closes at 00:00 IST on the 21st == 18:30Z on the
    // 20th? No: inclusive through the named day, exclusive at 2026-11-21T00:00
    // IST == 2026-11-20T18:30Z.
    final job = makeJob(
      applicationEndDate: '2026-11-20',
      applicationEndAt: null,
    );
    final closes = DateTime.utc(2026, 11, 20, 18, 30);
    final cutoff = DateTime.utc(2026, 11, 19, 18, 30);

    test('the effective close and cutoff follow the IST day boundary', () {
      expect(effectiveClosingUtc(job), closes);
      expect(reminderDueAtUtc(closes), cutoff);
    });

    test('accepted one second before the date-only cutoff', () async {
      final prefs = FakePreferences();
      final outcome = await enable(
        job,
        prefs: prefs,
        actions: FakeActions(),
        now: cutoff.subtract(const Duration(seconds: 1)),
      );

      expect(outcome, ReminderOutcome.enabled);
      expect(prefs.reminderCalls, [(job.id, true)]);
    });

    test('too late at the date-only cutoff', () async {
      final prefs = FakePreferences();
      final actions = FakeActions();
      final outcome = await enable(
        job,
        prefs: prefs,
        actions: actions,
        now: cutoff,
      );

      expect(outcome, ReminderOutcome.tooLate);
      expect(actions.permissionRequests, 0);
      expect(prefs.reminderCalls, isEmpty);
    });
  });

  test('a non-UTC clock instant is compared in UTC, not wall time', () async {
    final job = jobClosingIn(const Duration(days: 3));
    final cutoff = reminderDueAtUtc(base.add(const Duration(days: 3)));

    final localBefore = cutoff.subtract(const Duration(seconds: 1)).toLocal();
    expect(localBefore.isUtc, isFalse);
    final okPrefs = FakePreferences();
    expect(
      await enable(
        job,
        prefs: okPrefs,
        actions: FakeActions(),
        now: localBefore,
      ),
      ReminderOutcome.enabled,
    );
    expect(okPrefs.reminderCalls, [(job.id, true)]);

    final localAt = cutoff.toLocal();
    expect(localAt.isUtc, isFalse);
    final latePrefs = FakePreferences();
    final actions = FakeActions();
    expect(
      await enable(job, prefs: latePrefs, actions: actions, now: localAt),
      ReminderOutcome.tooLate,
    );
    expect(actions.permissionRequests, 0);
    expect(latePrefs.reminderCalls, isEmpty);
  });

  group('deferred permission re-evaluates the cutoff', () {
    test('a prompt that outlives the cutoff saves nothing', () async {
      final closes = base.add(const Duration(days: 3));
      final job = makeJob(applicationEndAt: closes, applicationEndDate: null);
      final cutoff = reminderDueAtUtc(closes);
      final prefs = FakePreferences();
      // Tapped one hour before the cutoff; the prompt answers two hours later.
      clock.value = cutoff.subtract(const Duration(hours: 1));
      final actions = ScriptedPermissionActions(
        // The prompt answers two hours later, past the cutoff.
        onRequest: () => clock.value = cutoff.add(const Duration(hours: 1)),
      );

      final outcome = await setReminderIntent(
        preferences: prefs,
        actions: actions,
        jobId: job.id,
        enable: true,
        deadline: deadlineInfo(job, clock.value),
        deadlineAt: (instant) => deadlineInfo(job, instant),
        now: () => clock.value,
      );

      expect(outcome, ReminderOutcome.tooLate);
      expect(actions.requests, 1);
      expect(prefs.reminderCalls, isEmpty);
    });

    test(
      'a correction extending the deadline during the prompt still saves',
      () async {
        var current = makeJob(
          applicationEndAt: base.add(const Duration(days: 3)),
          applicationEndDate: null,
        );
        final prefs = FakePreferences();
        // Corrected while the dialog is open: the cutoff moves far ahead again.
        final actions = ScriptedPermissionActions(
          onRequest: () {
            current = makeJob(
              applicationEndAt: base.add(const Duration(days: 30)),
              applicationEndDate: null,
            );
          },
        );

        final outcome = await setReminderIntent(
          preferences: prefs,
          actions: actions,
          jobId: current.id,
          enable: true,
          deadline: deadlineInfo(current, clock.value),
          deadlineAt: (instant) => deadlineInfo(current, instant),
          now: () => clock.value,
        );

        expect(outcome, ReminderOutcome.enabled);
        expect(prefs.reminderCalls, [(current.id, true)]);
      },
    );

    test(
      'a correction shortening the deadline past the cutoff saves nothing',
      () async {
        var current = makeJob(
          applicationEndAt: base.add(const Duration(days: 10)),
          applicationEndDate: null,
        );
        final prefs = FakePreferences();
        final actions = ScriptedPermissionActions(
          onRequest: () {
            // Now closes in 12 hours: the 24 h instant is already in the past.
            current = makeJob(
              applicationEndAt: base.add(const Duration(hours: 12)),
              applicationEndDate: null,
            );
          },
        );

        final outcome = await setReminderIntent(
          preferences: prefs,
          actions: actions,
          jobId: current.id,
          enable: true,
          deadline: deadlineInfo(current, clock.value),
          deadlineAt: (instant) => deadlineInfo(current, instant),
          now: () => clock.value,
        );

        expect(outcome, ReminderOutcome.tooLate);
        expect(actions.requests, 1);
        expect(prefs.reminderCalls, isEmpty);
      },
    );

    test(
      'a correction withdrawing the job during the prompt saves nothing',
      () async {
        var current = makeJob(
          applicationEndAt: base.add(const Duration(days: 10)),
          applicationEndDate: null,
        );
        final prefs = FakePreferences();
        final actions = ScriptedPermissionActions(
          onRequest: () {
            current = makeJob(
              status: JobStatus.withdrawn,
              applicationEndAt: base.add(const Duration(days: 10)),
              applicationEndDate: null,
            );
          },
        );

        final outcome = await setReminderIntent(
          preferences: prefs,
          actions: actions,
          jobId: current.id,
          enable: true,
          deadline: deadlineInfo(current, clock.value),
          deadlineAt: (instant) => deadlineInfo(current, instant),
          now: () => clock.value,
        );

        expect(outcome, ReminderOutcome.closed);
        expect(prefs.reminderCalls, isEmpty);
      },
    );
  });

  group('failure modes stay distinct', () {
    test(
      'denied, channel error and storage failure are three outcomes',
      () async {
        final job = jobClosingIn(const Duration(days: 3));

        final deniedPrefs = FakePreferences();
        expect(
          await enable(
            job,
            prefs: deniedPrefs,
            actions: FakeActions(permission: false),
          ),
          ReminderOutcome.permissionDenied,
        );
        expect(deniedPrefs.reminderCalls, isEmpty);

        final errorPrefs = FakePreferences();
        expect(
          await enable(
            job,
            prefs: errorPrefs,
            actions: FakeActions(permissionThrows: true),
          ),
          ReminderOutcome.permissionError,
        );
        expect(errorPrefs.reminderCalls, isEmpty);

        final failedPrefs = FakePreferences();
        expect(
          await enable(job, prefs: failedPrefs, actions: FakeActions()),
          ReminderOutcome.enabled, // control: same job, healthy store
        );
        expect(
          await enable(
            job,
            prefs: FakePreferences(throwOnWrite: true),
            actions: FakeActions(),
          ),
          ReminderOutcome.failed,
        );
      },
    );

    test('late, closed, no-deadline and failure messages are all distinct', () {
      final messages = {
        for (final outcome in ReminderOutcome.values)
          reminderOutcomeMessage(outcome).en,
      };
      expect(messages.length, ReminderOutcome.values.length);
      expect(
        reminderOutcomeMessage(ReminderOutcome.tooLate).bn,
        contains('২৪'),
      );
      expect(
        reminderOutcomeMessage(ReminderOutcome.tooLate).en.toLowerCase(),
        contains('24-hour'),
      );
    });

    test('the too-late copy promises nothing and blames no delivery', () {
      for (final text in [
        K.reminderTooLateMsg.bn,
        K.reminderTooLateMsg.en,
        K.reminderRowDuePassed.bn,
        K.reminderRowDuePassed.en,
        K.reminderRowClosed.bn,
        K.reminderRowClosed.en,
      ]) {
        expect(text, isNot(contains('নির্ধারিত')));
        expect(text, isNot(contains('scheduled')));
        expect(text, isNot(contains('delivered')));
        expect(text, isNot(contains('মিস')));
      }
    });
  });

  group('turning off a stored intent always works', () {
    test(
      'late, closed and unsupported jobs all disable without permission',
      () async {
        final late = makeJob(
          id: 'late-job',
          applicationEndAt: base.add(const Duration(hours: 2)),
          applicationEndDate: null,
        );
        final closed = makeJob(
          id: 'closed-job',
          applicationEndAt: base.subtract(const Duration(days: 1)),
          applicationEndDate: null,
        );
        final noDeadline = makeJob(
          id: 'result-job',
          kind: JobKind.result,
          status: JobStatus.published,
          hasDeadline: false,
          applicationEndAt: null,
        );

        for (final entry in [
          (late, ReminderOutcome.tooLate),
          (closed, ReminderOutcome.closed),
          (noDeadline, ReminderOutcome.noDeadline),
        ]) {
          final job = entry.$1;
          final prefs = FakePreferences(reminders: {job.id});
          final actions = FakeActions(permission: false);

          // Enabling is refused for these reasons...
          expect(
            await enable(job, prefs: prefs, actions: actions),
            entry.$2,
            reason: 'enable should be refused for ${job.id}',
          );
          expect(actions.permissionRequests, 0);
          expect(prefs.reminderCalls, isEmpty);

          // ...but the stored intent can always be removed.
          final outcome = await setReminderIntent(
            preferences: prefs,
            actions: actions,
            jobId: job.id,
            enable: false,
            deadline: deadlineInfo(job, clock.value),
          );
          expect(outcome, ReminderOutcome.disabled, reason: job.id);
          expect(actions.permissionRequests, 0, reason: job.id);
          expect(prefs.reminderCalls, [(job.id, false)], reason: job.id);
          expect(prefs.reminderJobIds.value, isEmpty, reason: job.id);
        }
      },
    );
  });

  group('stored intent semantics', () {
    final pendingJob = makeJob(
      id: 'pending-job',
      applicationEndAt: base.add(const Duration(days: 5)),
      applicationEndDate: null,
    );

    test('classification follows the current fields and clock', () {
      expect(
        storedReminderState(info: deadlineInfo(pendingJob, base), now: base),
        StoredReminderState.pending,
      );
      expect(
        storedReminderState(
          info: deadlineInfo(pendingJob, base),
          now: pendingJob.applicationEndAt!.subtract(const Duration(hours: 24)),
        ),
        StoredReminderState.duePassed,
      );
      expect(
        storedReminderState(
          info: deadlineInfo(
            makeJob(
              applicationEndAt: base.subtract(const Duration(days: 1)),
              applicationEndDate: null,
            ),
            base,
          ),
          now: base,
        ),
        StoredReminderState.closed,
      );
      expect(
        storedReminderState(
          info: deadlineInfo(makeJob(status: JobStatus.withdrawn), base),
          now: base,
        ),
        StoredReminderState.withdrawn,
      );
      expect(
        storedReminderState(info: null, now: base),
        StoredReminderState.unavailable,
      );
      expect(
        storedReminderState(
          info: deadlineInfo(
            makeJob(
              kind: JobKind.result,
              status: JobStatus.published,
              hasDeadline: false,
              applicationEndDate: null,
            ),
            base,
          ),
          now: base,
        ),
        StoredReminderState.noDeadline,
      );
    });

    test('only a pending intent has no extra message', () {
      expect(storedReminderMessage(StoredReminderState.pending), isNull);
      for (final state in StoredReminderState.values) {
        if (state == StoredReminderState.pending) continue;
        final message = storedReminderMessage(state);
        expect(message, isNotNull, reason: '$state');
        expect(message!.bn, isNotEmpty, reason: '$state');
        expect(message.en, isNotEmpty, reason: '$state');
      }
    });

    test(
      'a pending row is qualified as a stored request, never a delivery',
      () {
        final subtitle = reminderRowSubtitle(
          job: pendingJob,
          now: base,
          lang: AppLang.bn,
        );
        expect(subtitle, contains(K.reminderStored.bn));
        expect(subtitle, isNot(contains('পাঠানো')));
        expect(subtitle, isNot(contains('নির্ধারিত')));
      },
    );

    test('a due-passed row explains the current state, not a missed alert', () {
      final subtitle = reminderRowSubtitle(
        job: pendingJob,
        now: pendingJob.applicationEndAt!.subtract(const Duration(hours: 1)),
        lang: AppLang.bn,
      );
      expect(subtitle, K.reminderRowDuePassed.bn);
      expect(subtitle, contains('জানা যায় না'));
      expect(subtitle, isNot(contains('পাঠানো হয়েছে')));
    });

    test('a job missing from the feed keeps its stored row, still unknown', () {
      final subtitle = reminderRowSubtitle(
        job: null,
        now: base,
        lang: AppLang.en,
      );
      expect(subtitle, K.reminderRowUnavailable.en);
      expect(subtitle, contains('still listed'));
    });
  });

  group('detail screen', () {
    testWidgets('a late job explains the refusal and saves nothing', (
      tester,
    ) async {
      final job = jobClosingIn(const Duration(hours: 20));
      final prefs = FakePreferences();
      final actions = FakeActions();
      await pumpScreen(tester, detail(job, prefs: prefs, actions: actions));

      // The control stays tappable so the reason can be read.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'রিমাইন্ডার দিন'),
      );
      expect(button.onPressed, isNotNull);
      // ...and the reason is already visible without a tap.
      expect(find.text(K.reminderTooLateMsg.bn), findsOneWidget);

      await tester.tap(find.text('রিমাইন্ডার দিন'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(actions.permissionRequests, 0);
      expect(prefs.reminderCalls, isEmpty);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(K.reminderTooLateMsg.bn),
        ),
        findsOneWidget,
      );
    });

    testWidgets('crossing the cutoff while mounted flips the panel live', (
      tester,
    ) async {
      final job = jobClosingIn(const Duration(hours: 25));
      await pumpScreen(tester, detail(job));

      // One hour before the cutoff the reminder is still offered.
      expect(find.text(K.reminderTooLateMsg.bn), findsNothing);
      final enabled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'রিমাইন্ডার দিন'),
      );
      expect(enabled.onPressed, isNotNull);

      await clock.advance(tester, const Duration(hours: 2));
      await tester.pump();

      expect(find.text(K.reminderTooLateMsg.bn), findsOneWidget);
      // Still tappable: the refusal is explained, not hidden.
      final after = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'রিমাইন্ডার দিন'),
      );
      expect(after.onPressed, isNotNull);
      expect(find.textContaining('আবেদনের সময় শেষ'), findsNothing);
    });

    testWidgets('a stored intent on a late job is explained and not cleared', (
      tester,
    ) async {
      final job = jobClosingIn(const Duration(hours: 20));
      final prefs = FakePreferences(reminders: {job.id});
      await pumpScreen(tester, detail(job, prefs: prefs));

      expect(find.text(K.reminderRowDuePassed.bn), findsOneWidget);
      // Nothing was written, and the stored id is untouched.
      expect(prefs.reminderCalls, isEmpty);
      expect(prefs.reminderJobIds.value, {job.id});

      // The only way it disappears is the explicit switch-off.
      await tester.tap(find.text('রিমাইন্ডার চালু'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(prefs.reminderCalls, [(job.id, false)]);
      expect(prefs.reminderJobIds.value, isEmpty);
    });

    testWidgets('a stored intent on a closed job says the deadline passed', (
      tester,
    ) async {
      final job = jobClosingIn(const Duration(days: -1));
      final prefs = FakePreferences(reminders: {job.id});
      await pumpScreen(tester, detail(job, prefs: prefs));

      expect(find.text(K.reminderRowClosed.bn), findsOneWidget);
      expect(prefs.reminderCalls, isEmpty);
      expect(prefs.reminderJobIds.value, {job.id});
    });

    testWidgets('a correction while the prompt is open uses the new deadline', (
      tester,
    ) async {
      final original = makeJob(
        applicationEndAt: base.add(const Duration(days: 30)),
        applicationEndDate: null,
      );
      final corrected = makeJob(
        applicationEndAt: base.add(const Duration(hours: 10)),
        applicationEndDate: null,
      );
      final prefs = FakePreferences();
      final actions = FakeActions(permissionDelay: const Duration(hours: 1));

      await pumpScreen(
        tester,
        detail(original, prefs: prefs, actions: actions),
      );
      await tester.tap(find.text('রিমাইন্ডার দিন'));
      await tester.pump();

      // The feed corrects the deadline while the dialog is still open.
      await tester.pumpWidget(
        MaterialApp(
          home: detail(corrected, prefs: prefs, actions: actions),
        ),
      );
      await tester.pump();
      await clock.advance(tester, const Duration(hours: 1));
      await tester.pump();

      expect(actions.permissionRequests, 1);
      expect(prefs.reminderCalls, isEmpty);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(K.reminderTooLateMsg.bn),
        ),
        findsOneWidget,
      );
    });

    testWidgets('unmounting during the prompt leaves no write and no error', (
      tester,
    ) async {
      // Cutoff is one hour away, so the prompt outlives it as well as the
      // screen: the recheck still refuses the write, off-tree and silently.
      final job = jobClosingIn(const Duration(hours: 25));
      final prefs = FakePreferences();
      final actions = FakeActions(permissionDelay: const Duration(hours: 1));
      await pumpScreen(tester, detail(job, prefs: prefs, actions: actions));

      await tester.tap(find.text('রিমাইন্ডার দিন'));
      await tester.pump();
      expect(actions.permissionRequests, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await clock.advance(tester, const Duration(hours: 2));

      expect(tester.takeException(), isNull);
      expect(actions.permissionRequests, 1);
      expect(prefs.reminderCalls, isEmpty);
    });

    testWidgets('unmounting right after a late tap throws nothing', (
      tester,
    ) async {
      final job = jobClosingIn(const Duration(hours: 20));
      final prefs = FakePreferences();
      await pumpScreen(tester, detail(job, prefs: prefs));

      await tester.tap(find.text('রিমাইন্ডার দিন'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(prefs.reminderCalls, isEmpty);
    });

    testWidgets('English users read the English late copy', (tester) async {
      appLanguage.value = AppLang.en;
      final job = jobClosingIn(const Duration(hours: 20));
      await pumpScreen(tester, detail(job));

      expect(find.text(K.reminderTooLateMsg.en), findsOneWidget);
      expect(find.text(K.reminderTooLateMsg.bn), findsNothing);
    });
  });

  group('home reminder sheet rows', () {
    final pending = makeJob(
      id: 'pending-job',
      titleBn: 'চলমান নিয়োগ',
      applicationEndAt: base.add(const Duration(days: 6)),
      applicationEndDate: null,
    );
    final duePassed = makeJob(
      id: 'due-passed-job',
      titleBn: 'আসন্ন শেষ তারিখ',
      applicationEndAt: base.add(const Duration(hours: 6)),
      applicationEndDate: null,
    );
    final closed = makeJob(
      id: 'closed-job',
      titleBn: 'শেষ হওয়া নিয়োগ',
      applicationEndAt: base.subtract(const Duration(days: 1)),
      applicationEndDate: null,
    );
    final withdrawn = makeJob(
      id: 'withdrawn-job',
      titleBn: 'প্রত্যাহৃত নিয়োগ',
      status: JobStatus.withdrawn,
    );

    testWidgets('every stored row states the stored request truthfully', (
      tester,
    ) async {
      final prefs = FakePreferences(
        reminders: {
          pending.id,
          duePassed.id,
          closed.id,
          withdrawn.id,
          'ghost-job',
        },
      );
      await pumpScreen(
        tester,
        home([pending, duePassed, closed, withdrawn], prefs),
        surfaceSize: const Size(420, 1600),
      );

      await tester.tap(find.byTooltip('নোটিফিকেশন'));
      await tester.pumpAndSettle();

      expect(find.textContaining('${K.reminderStored.bn} · '), findsOneWidget);
      expect(find.text(K.reminderRowDuePassed.bn), findsOneWidget);
      expect(find.text(K.reminderRowClosed.bn), findsOneWidget);
      expect(find.text(K.reminderRowWithdrawn.bn), findsOneWidget);
      expect(find.text(K.reminderRowUnavailable.bn), findsOneWidget);

      // No row claims delivery, scheduling or a missed alert.
      for (final claim in ['পাঠানো হয়েছে', 'নির্ধারিত', 'মিস হয়েছে']) {
        expect(find.textContaining(claim), findsNothing);
      }

      // Opening the sheet must not mutate the stored set.
      expect(prefs.reminderCalls, isEmpty);
      expect(prefs.reminderJobIds.value.length, 5);
    });

    testWidgets('the same rows read correctly in English', (tester) async {
      appLanguage.value = AppLang.en;
      final prefs = FakePreferences(reminders: {duePassed.id, closed.id});
      await pumpScreen(
        tester,
        home([pending, duePassed, closed], prefs),
        surfaceSize: const Size(420, 1600),
      );

      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();

      expect(find.text(K.reminderRowDuePassed.en), findsOneWidget);
      expect(find.text(K.reminderRowClosed.en), findsOneWidget);
      for (final claim in ['was delivered', 'scheduled for', 'was missed']) {
        expect(find.textContaining(claim), findsNothing);
      }
    });
  });

  group('320px at 2x text', () {
    Future<void> scrollThrough(WidgetTester tester) async {
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isEmpty) return;
      final state = tester.state<ScrollableState>(scrollable.first);
      for (var i = 0; i < 14; i++) {
        await tester.drag(scrollable.first, const Offset(0, -260));
        await tester.pump();
        if (state.position.pixels >= state.position.maxScrollExtent - 1) break;
      }
      await tester.pump();
    }

    testWidgets('the late explanation and control fit (bn)', (tester) async {
      final job = jobClosingIn(const Duration(hours: 20));
      await pumpScreen(
        tester,
        detail(job, prefs: FakePreferences(reminders: {job.id})),
        surfaceSize: phone320,
        textScale: textScale2x,
      );
      expect(tester.takeException(), isNull);

      final button = find.widgetWithText(FilledButton, K.reminderOn.bn);
      await tester.scrollUntilVisible(
        button,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));

      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    });

    Future<void> checkSheetAt2x(WidgetTester tester, AppLang lang) async {
      appLanguage.value = lang;
      final duePassed = makeJob(
        id: 'due-passed-job',
        titleBn: 'পশ্চিমবঙ্গ পুলিশে কনস্টেবল নিয়োগ, দীর্ঘ শিরোনাম',
        applicationEndAt: base.add(const Duration(hours: 6)),
        applicationEndDate: null,
      );
      final prefs = FakePreferences(reminders: {duePassed.id, 'ghost-job'});
      await pumpScreen(
        tester,
        home([duePassed], prefs),
        surfaceSize: phone320,
        textScale: textScale2x,
      );

      await tester.tap(
        find.byTooltip(lang == AppLang.bn ? 'নোটিফিকেশন' : 'Notifications'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Every row is laid out eagerly, so a 2x sheet has to fit them all.
      expect(
        find.text(
          lang == AppLang.bn ? K.unavailableJob.bn : K.unavailableJob.en,
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          lang == AppLang.bn
              ? K.reminderRowDuePassed.bn
              : K.reminderRowDuePassed.en,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // Scrolling inside the sheet keeps it stable at 2x.
      await tester.drag(
        find.byType(Scrollable).last,
        const Offset(0, -200),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets('the sheet rows fit at 2x text (bn)', (tester) async {
      await checkSheetAt2x(tester, AppLang.bn);
    });

    testWidgets('the sheet rows fit at 2x text (en)', (tester) async {
      await checkSheetAt2x(tester, AppLang.en);
    });
  });
}
