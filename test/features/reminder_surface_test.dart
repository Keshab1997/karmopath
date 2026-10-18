import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/features/calendar/calendar_screen.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/common/deadline_clock.dart';
import 'package:karmopath/features/common/reminder_intent_state.dart';
import 'package:karmopath/features/common/strings.dart';
import 'package:karmopath/features/saved/saved_screen.dart';
import 'package:karmopath/features/settings/settings_screen.dart';

import 'support/fakes.dart';
import 'support/test_clock.dart';

const Size phone320 = Size(320, 720);
const double textScale2x = 2.0;

void main() {
  // Fixed reference instant: 2026-11-15 12:00 UTC == 17:30 IST.
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

  final pendingJob = makeJob(
    id: 'pending-job',
    titleBn: 'চলমান নিয়োগ বিজ্ঞপ্তি',
    titleEn: 'Ongoing Recruitment Notice',
    applicationEndAt: base.add(const Duration(days: 5)),
    applicationEndDate: null,
  );
  final duePassedJob = makeJob(
    id: 'due-passed-job',
    titleBn: 'আসন্ন শেষ তারিখের নিয়োগ',
    titleEn: 'Closing Soon Recruitment',
    applicationEndAt: base.add(const Duration(hours: 6)),
    applicationEndDate: null,
  );
  final closedJob = makeJob(
    id: 'closed-job',
    titleBn: 'সমাপ্ত নিয়োগ বিজ্ঞপ্তি',
    titleEn: 'Closed Recruitment Notice',
    applicationEndAt: base.subtract(const Duration(days: 2)),
    applicationEndDate: null,
  );
  final withdrawnJob = makeJob(
    id: 'withdrawn-job',
    titleBn: 'প্রত্যাহৃত নিয়োগ বিজ্ঞপ্তি',
    titleEn: 'Withdrawn Recruitment Notice',
    status: JobStatus.withdrawn,
    applicationEndAt: base.add(const Duration(days: 10)),
    applicationEndDate: null,
  );
  final noDeadlineJob = makeJob(
    id: 'result-job',
    kind: JobKind.result,
    status: JobStatus.published,
    titleBn: 'লিখিত পরীক্ষার ফলাফল',
    titleEn: 'Written Exam Result',
    hasDeadline: false,
    applicationEndDate: null,
    applicationEndAt: null,
  );

  void expectNoDeliveryOrScheduleClaims() {
    for (final forbidden in [
      'পাঠানো হয়েছে',
      'নির্ধারিত',
      'মিস হয়েছে',
      'was delivered',
      'scheduled for',
      'was missed',
    ]) {
      expect(find.textContaining(forbidden), findsNothing);
    }
  }

  Future<void> scrollThrough(WidgetTester tester) async {
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isEmpty) return;
    final state = tester.state<ScrollableState>(scrollable.first);
    for (var i = 0; i < 16; i++) {
      await tester.drag(scrollable.first, const Offset(0, -260));
      await tester.pump();
      if (state.position.pixels >= state.position.maxScrollExtent - 1) break;
    }
    await tester.pump();
  }

  group('Calendar stored-intent subtitles', () {
    testWidgets(
      'pending, duePassed, closed and withdrawn rows show reminderRowSubtitle in Bengali',
      (tester) async {
        final prefs = FakePreferences(
          reminders: {
            pendingJob.id,
            duePassedJob.id,
            closedJob.id,
            withdrawnJob.id,
          },
        );
        final repo = FakeJobRepository(
          readyState([pendingJob, duePassedJob, closedJob, withdrawnJob]),
        );

        await pumpScreen(
          tester,
          CalendarScreen(
            repository: repo,
            preferences: prefs,
            onOpenJob: (_) {},
          ),
          surfaceSize: const Size(500, 1800),
        );

        // Upcoming view shows pending and duePassed rows with their subtitles.
        expect(
          find.text(
            reminderRowSubtitle(job: pendingJob, now: base, lang: AppLang.bn),
          ),
          findsOneWidget,
        );
        expect(find.text(K.reminderRowDuePassed.bn), findsOneWidget);
        expect(find.byIcon(Icons.alarm_on), findsNWidgets(2));

        // Switch to All to include closed and withdrawn rows.
        await tester.tap(find.text(K.allDeadlines.bn).first);
        await tester.pump();

        expect(
          find.text(
            reminderRowSubtitle(job: pendingJob, now: base, lang: AppLang.bn),
          ),
          findsOneWidget,
        );
        expect(find.text(K.reminderRowDuePassed.bn), findsOneWidget);
        expect(find.text(K.reminderRowClosed.bn), findsOneWidget);
        expect(find.text(K.reminderRowWithdrawn.bn), findsOneWidget);
        expect(find.byIcon(Icons.alarm_on), findsNWidgets(4));

        // Existing expired/withdrawn labels stay untouched alongside the subtitle.
        expect(find.textContaining('বন্ধ হয়েছে'), findsOneWidget);
        expect(find.text(K.statusWithdrawn.bn), findsOneWidget);

        expectNoDeliveryOrScheduleClaims();
        expect(prefs.reminderCalls, isEmpty);
      },
    );

    testWidgets(
      'pending, duePassed, closed and withdrawn rows show reminderRowSubtitle in English',
      (tester) async {
        appLanguage.value = AppLang.en;
        final prefs = FakePreferences(
          reminders: {
            pendingJob.id,
            duePassedJob.id,
            closedJob.id,
            withdrawnJob.id,
          },
        );
        final repo = FakeJobRepository(
          readyState([pendingJob, duePassedJob, closedJob, withdrawnJob]),
        );

        await pumpScreen(
          tester,
          CalendarScreen(
            repository: repo,
            preferences: prefs,
            onOpenJob: (_) {},
          ),
          surfaceSize: const Size(500, 1800),
        );

        await tester.tap(find.text(K.allDeadlines.en).first);
        await tester.pump();

        expect(
          find.text(
            reminderRowSubtitle(job: pendingJob, now: base, lang: AppLang.en),
          ),
          findsOneWidget,
        );
        expect(find.text(K.reminderRowDuePassed.en), findsOneWidget);
        expect(find.text(K.reminderRowClosed.en), findsOneWidget);
        expect(find.text(K.reminderRowWithdrawn.en), findsOneWidget);

        expectNoDeliveryOrScheduleClaims();
      },
    );

    testWidgets(
      'calendar cards without a stored intent do not show reminderRowSubtitle',
      (tester) async {
        final prefs = FakePreferences(reminders: {pendingJob.id});
        final repo = FakeJobRepository(readyState([pendingJob, duePassedJob]));

        await pumpScreen(
          tester,
          CalendarScreen(
            repository: repo,
            preferences: prefs,
            onOpenJob: (_) {},
          ),
          surfaceSize: const Size(500, 1400),
        );

        expect(
          find.text(
            reminderRowSubtitle(job: pendingJob, now: base, lang: AppLang.bn),
          ),
          findsOneWidget,
        );
        expect(find.text(K.reminderRowDuePassed.bn), findsNothing);
        expect(find.byIcon(Icons.alarm_on), findsOneWidget);
      },
    );

    testWidgets(
      'crossing the 24-hour cutoff updates the calendar subtitle live',
      (tester) async {
        final job = makeJob(
          id: 'cutoff-live-job',
          applicationEndAt: base.add(const Duration(hours: 25)),
          applicationEndDate: null,
        );
        final prefs = FakePreferences(reminders: {job.id});
        final repo = FakeJobRepository(readyState([job]));

        await pumpScreen(
          tester,
          CalendarScreen(
            repository: repo,
            preferences: prefs,
            onOpenJob: (_) {},
          ),
        );

        expect(
          find.textContaining('${K.reminderStored.bn} · '),
          findsOneWidget,
        );
        expect(find.text(K.reminderRowDuePassed.bn), findsNothing);

        await clock.advance(tester, const Duration(hours: 2));
        await tester.pump();

        expect(find.text(K.reminderRowDuePassed.bn), findsOneWidget);
        expect(find.textContaining('${K.reminderStored.bn} · '), findsNothing);
      },
    );
  });

  group('Saved stored-intent subtitles', () {
    testWidgets(
      'saved cards with stored intents show reminderRowSubtitle including missing, no-deadline and withdrawn jobs (bn)',
      (tester) async {
        final prefs = FakePreferences(
          saved: {
            pendingJob.id,
            duePassedJob.id,
            closedJob.id,
            withdrawnJob.id,
            noDeadlineJob.id,
            'missing-job-2026',
          },
          reminders: {
            pendingJob.id,
            duePassedJob.id,
            closedJob.id,
            withdrawnJob.id,
            noDeadlineJob.id,
            'missing-job-2026',
          },
        );
        final repo = FakeJobRepository(
          readyState([
            pendingJob,
            duePassedJob,
            closedJob,
            withdrawnJob,
            noDeadlineJob,
          ]),
        );

        await pumpScreen(
          tester,
          SavedScreen(repository: repo, preferences: prefs, onOpenJob: (_) {}),
          surfaceSize: const Size(500, 2600),
        );

        expect(
          find.text(
            reminderRowSubtitle(job: pendingJob, now: base, lang: AppLang.bn),
          ),
          findsOneWidget,
        );
        expect(find.text(K.reminderRowDuePassed.bn), findsOneWidget);
        expect(find.text(K.reminderRowClosed.bn), findsOneWidget);
        expect(find.text(K.reminderRowWithdrawn.bn), findsOneWidget);
        expect(find.text(K.reminderRowNoDeadline.bn), findsOneWidget);
        expect(find.text(K.reminderRowUnavailable.bn), findsOneWidget);

        expectNoDeliveryOrScheduleClaims();
        expect(prefs.reminderCalls, isEmpty);
      },
    );

    testWidgets(
      'saved cards with stored intents show reminderRowSubtitle in English',
      (tester) async {
        appLanguage.value = AppLang.en;
        final prefs = FakePreferences(
          saved: {
            pendingJob.id,
            withdrawnJob.id,
            noDeadlineJob.id,
            'missing-job-2026',
          },
          reminders: {
            pendingJob.id,
            withdrawnJob.id,
            noDeadlineJob.id,
            'missing-job-2026',
          },
        );
        final repo = FakeJobRepository(
          readyState([pendingJob, withdrawnJob, noDeadlineJob]),
        );

        await pumpScreen(
          tester,
          SavedScreen(repository: repo, preferences: prefs, onOpenJob: (_) {}),
          surfaceSize: const Size(500, 2200),
        );

        expect(
          find.text(
            reminderRowSubtitle(job: pendingJob, now: base, lang: AppLang.en),
          ),
          findsOneWidget,
        );
        expect(find.text(K.reminderRowWithdrawn.en), findsOneWidget);
        expect(find.text(K.reminderRowNoDeadline.en), findsOneWidget);
        expect(find.text(K.reminderRowUnavailable.en), findsOneWidget);

        expectNoDeliveryOrScheduleClaims();
      },
    );

    testWidgets(
      'saved cards without stored intent omit the subtitle and react to reminderJobIds updates',
      (tester) async {
        final prefs = FakePreferences(
          saved: {pendingJob.id, duePassedJob.id},
          reminders: {pendingJob.id},
        );
        final repo = FakeJobRepository(readyState([pendingJob, duePassedJob]));

        await pumpScreen(
          tester,
          SavedScreen(repository: repo, preferences: prefs, onOpenJob: (_) {}),
          surfaceSize: const Size(500, 1600),
        );

        expect(
          find.text(
            reminderRowSubtitle(job: pendingJob, now: base, lang: AppLang.bn),
          ),
          findsOneWidget,
        );
        expect(find.text(K.reminderRowDuePassed.bn), findsNothing);

        await prefs.setReminder(duePassedJob.id, true);
        await tester.pump();
        expect(find.text(K.reminderRowDuePassed.bn), findsOneWidget);

        await prefs.setReminder(pendingJob.id, false);
        await tester.pump();
        expect(
          find.text(
            reminderRowSubtitle(job: pendingJob, now: base, lang: AppLang.bn),
          ),
          findsNothing,
        );
      },
    );
  });

  group('Settings stored-reminder summary', () {
    testWidgets('shows 0, 1 and many stored reminders in Bengali and English', (
      tester,
    ) async {
      final prefs = FakePreferences();
      final repo = FakeJobRepository(
        readyState([pendingJob, duePassedJob, closedJob]),
      );
      final actions = FakeActions();

      await pumpScreen(
        tester,
        SettingsScreen(actions: actions, preferences: prefs, repository: repo),
        surfaceSize: const Size(500, 2000),
      );

      // 0 stored reminders (bn).
      expect(find.text('০টি সংরক্ষিত রিমাইন্ডার'), findsOneWidget);
      expect(find.text(K.noRemindersTitle.bn), findsOneWidget);

      // 1 stored reminder (bn) — uses reminderRowSubtitle for that job.
      await prefs.setReminder(pendingJob.id, true);
      await tester.pump();
      expect(find.text('১টি সংরক্ষিত রিমাইন্ডার'), findsOneWidget);
      expect(
        find.text(
          reminderRowSubtitle(job: pendingJob, now: base, lang: AppLang.bn),
        ),
        findsOneWidget,
      );

      // Many stored reminders (bn).
      await prefs.setReminder(duePassedJob.id, true);
      await prefs.setReminder('missing-id', true);
      await tester.pump();
      expect(find.text('৩টি সংরক্ষিত রিমাইন্ডার'), findsOneWidget);
      expect(
        find.text('${K.reminderStored.bn} · ${K.reminderSheetPolicy.bn}'),
        findsOneWidget,
      );
      expectNoDeliveryOrScheduleClaims();

      // Switch to English and verify 3 -> 1 -> 0 copy.
      appLanguage.value = AppLang.en;
      await tester.pump();
      expect(find.text('3 stored reminders'), findsOneWidget);
      expect(
        find.text('${K.reminderStored.en} · ${K.reminderSheetPolicy.en}'),
        findsOneWidget,
      );

      await prefs.setReminder(duePassedJob.id, false);
      await prefs.setReminder('missing-id', false);
      await tester.pump();
      expect(find.text('1 stored reminder'), findsOneWidget);
      expect(
        find.text(
          reminderRowSubtitle(job: pendingJob, now: base, lang: AppLang.en),
        ),
        findsOneWidget,
      );

      await prefs.setReminder(pendingJob.id, false);
      await tester.pump();
      expect(find.text('0 stored reminders'), findsOneWidget);
      expect(find.text(K.noRemindersTitle.en), findsOneWidget);

      expectNoDeliveryOrScheduleClaims();
    });

    testWidgets(
      'tapping the settings summary row navigates nowhere and persists nothing',
      (tester) async {
        final prefs = FakePreferences(reminders: {pendingJob.id});
        final actions = FakeActions();

        await pumpScreen(
          tester,
          SettingsScreen(
            actions: actions,
            preferences: prefs,
            repository: FakeJobRepository(readyState([pendingJob])),
          ),
          surfaceSize: const Size(500, 2000),
        );

        await tester.tap(find.text('১টি সংরক্ষিত রিমাইন্ডার'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('প্রোফাইল ও সেটিংস'), findsOneWidget);
        expect(actions.permissionRequests, 0);
        expect(actions.opened, isEmpty);
        expect(prefs.reminderCalls, isEmpty);
        expect(prefs.savedCalls, isEmpty);
      },
    );
  });

  group('320px at 2x text for modified cards', () {
    final longPending = makeJob(
      id: 'long-pending',
      titleBn: 'পশ্চিমবঙ্গ পুলিশ ও স্বাস্থ্য দপ্তরে দীর্ঘ শিরোনামের নিয়োগ বিজ্ঞপ্তি ২০২৬',
      titleEn: 'West Bengal Police and Health Department Long Recruitment Notice 2026',
      organization:
          'West Bengal Police Recruitment Board, Aravind Building, Kolkata',
      applicationEndAt: base.add(const Duration(days: 4)),
      applicationEndDate: null,
    );
    final longDuePassed = makeJob(
      id: 'long-due-passed',
      titleBn:
          'কলকাতা মেট্রো রেলওয়ে স্টেশন মাস্টার ও টেকনিশিয়ান পদে জরুরি নিয়োগ',
      titleEn:
          'Kolkata Metro Railway Station Master and Technician Urgent Notice',
      applicationEndAt: base.add(const Duration(hours: 5)),
      applicationEndDate: null,
    );

    testWidgets(
      'calendar with stored-intent subtitles fits at 320px 2x (bn/en)',
      (tester) async {
        final prefs = FakePreferences(
          reminders: {longPending.id, longDuePassed.id, closedJob.id},
        );
        final repo = FakeJobRepository(
          readyState([longPending, longDuePassed, closedJob]),
        );

        for (final lang in AppLang.values) {
          appLanguage.value = lang;
          await tester.pumpWidget(const SizedBox.shrink());
          await pumpScreen(
            tester,
            CalendarScreen(
              repository: repo,
              preferences: prefs,
              onOpenJob: (_) {},
            ),
            surfaceSize: phone320,
            textScale: textScale2x,
          );
          expect(tester.takeException(), isNull);

          await tester.tap(find.text(K.allDeadlines.inLang(lang)).first);
          await tester.pump();
          expect(tester.takeException(), isNull);

          await scrollThrough(tester);
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'saved cards + missing job with stored-intent subtitles fit at 320px 2x (bn/en)',
      (tester) async {
        final prefs = FakePreferences(
          saved: {
            longPending.id,
            longDuePassed.id,
            noDeadlineJob.id,
            'missing-long-job-id-2026',
          },
          reminders: {
            longPending.id,
            longDuePassed.id,
            noDeadlineJob.id,
            'missing-long-job-id-2026',
          },
        );
        final repo = FakeJobRepository(
          readyState([longPending, longDuePassed, noDeadlineJob]),
        );

        for (final lang in AppLang.values) {
          appLanguage.value = lang;
          await pumpScreen(
            tester,
            SavedScreen(
              repository: repo,
              preferences: prefs,
              onOpenJob: (_) {},
            ),
            surfaceSize: phone320,
            textScale: textScale2x,
          );
          expect(tester.takeException(), isNull);

          await scrollThrough(tester);
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets('settings summary row fits at 320px 2x (bn/en)', (
      tester,
    ) async {
      final prefs = FakePreferences(
        reminders: {longPending.id, longDuePassed.id},
      );
      final repo = FakeJobRepository(readyState([longPending, longDuePassed]));

      for (final lang in AppLang.values) {
        appLanguage.value = lang;
        await pumpScreen(
          tester,
          SettingsScreen(
            actions: FakeActions(),
            preferences: prefs,
            repository: repo,
          ),
          surfaceSize: phone320,
          textScale: textScale2x,
        );
        expect(tester.takeException(), isNull);

        await scrollThrough(tester);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
