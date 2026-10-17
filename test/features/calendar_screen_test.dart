import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/contracts/job_repository.dart';
import 'package:karmopath/features/calendar/calendar_screen.dart';
import 'package:karmopath/features/common/app_language.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => appLanguage.value = AppLang.bn);
  tearDown(() => appLanguage.value = AppLang.bn);

  final now = utcNow();
  final soon = makeJob(
    id: 'deadline-soon',
    titleBn: 'শীঘ্রই শেষ হবে',
    applicationEndAt: now.add(const Duration(days: 3)),
  );
  final later = makeJob(
    id: 'deadline-later',
    titleBn: 'পরে শেষ হবে',
    applicationEndAt: now.add(const Duration(days: 40)),
  );
  final past = makeJob(
    id: 'deadline-past',
    titleBn: 'আগেই শেষ হয়েছে',
    applicationEndDate: dateOnly(now.subtract(const Duration(days: 6))),
    status: JobStatus.open, // deliberately stale server status
  );

  testWidgets('upcoming deadlines are grouped and ordered', (tester) async {
    final repo = FakeJobRepository(readyState([later, soon, past]));
    await pumpScreen(
      tester,
      CalendarScreen(
        repository: repo,
        preferences: FakePreferences(),
        onOpenJob: (_) {},
      ),
    );

    expect(find.text(soon.titleBn), findsOneWidget);
    expect(find.text(later.titleBn), findsOneWidget);
    expect(find.text(past.titleBn), findsNothing);
    expect(
      tester.getTopLeft(find.text(soon.titleBn)).dy,
      lessThan(tester.getTopLeft(find.text(later.titleBn)).dy),
    );
  });

  testWidgets('past deadlines appear only in the All scope', (tester) async {
    final repo = FakeJobRepository(readyState([soon, past]));
    await pumpScreen(
      tester,
      CalendarScreen(
        repository: repo,
        preferences: FakePreferences(),
        onOpenJob: (_) {},
      ),
    );

    expect(find.text(past.titleBn), findsNothing);
    await tester.tap(find.text('সব').first);
    await tester.pump();
    expect(find.text(past.titleBn), findsOneWidget);
  });

  testWidgets('jobs without deadlines are ignored', (tester) async {
    final result = makeJob(
      id: 'result-only',
      kind: JobKind.result,
      status: JobStatus.published,
      applicationEndDate: null,
      applicationEndAt: null,
      hasDeadline: false,
    );
    final repo = FakeJobRepository(readyState([result]));
    await pumpScreen(
      tester,
      CalendarScreen(
        repository: repo,
        preferences: FakePreferences(),
        onOpenJob: (_) {},
      ),
    );

    expect(find.text('সামনের কোনো শেষ তারিখ নেই'), findsOneWidget);
  });

  testWidgets('closed jobs keep a closed label', (tester) async {
    final repo = FakeJobRepository(readyState([past]));
    await pumpScreen(
      tester,
      CalendarScreen(
        repository: repo,
        preferences: FakePreferences(),
        onOpenJob: (_) {},
      ),
    );

    // Upcoming is empty, action switches to All.
    await tester.tap(find.text('সব').first);
    await tester.pump();
    expect(find.textContaining('বন্ধ হয়েছে'), findsOneWidget);
  });

  testWidgets('reminder bell marks enabled reminders read-only', (
    tester,
  ) async {
    final repo = FakeJobRepository(readyState([soon]));
    await pumpScreen(
      tester,
      CalendarScreen(
        repository: repo,
        preferences: FakePreferences(reminders: {soon.id}),
        onOpenJob: (_) {},
      ),
    );

    expect(find.byIcon(Icons.alarm_on), findsOneWidget);
    // No permission prompt is possible on this screen.
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('tapping a deadline opens the job', (tester) async {
    String? opened;
    final repo = FakeJobRepository(readyState([soon]));
    await pumpScreen(
      tester,
      CalendarScreen(
        repository: repo,
        preferences: FakePreferences(),
        onOpenJob: (id) => opened = id,
      ),
    );

    await tester.tap(find.text(soon.titleBn));
    await tester.pump();
    expect(opened, soon.id);
  });

  testWidgets('loading and error states render', (tester) async {
    final repo = FakeJobRepository(const JobFeedState(isLoading: true));
    await pumpScreen(
      tester,
      CalendarScreen(
        repository: repo,
        preferences: FakePreferences(),
        onOpenJob: (_) {},
      ),
    );
    expect(find.text('লোড হচ্ছে…'), findsOneWidget);

    final failing = FakeJobRepository(const JobFeedState(lastError: 'x'));
    await pumpScreen(
      tester,
      CalendarScreen(
        repository: failing,
        preferences: FakePreferences(),
        onOpenJob: (_) {},
      ),
    );
    expect(find.text('তথ্য লোড করা যায়নি'), findsOneWidget);
  });
  testWidgets('date-only month end stays on its named day and month', (
    tester,
  ) async {
    appLanguage.value = AppLang.en;
    final job = makeJob(applicationEndDate: '2099-12-31');
    await pumpScreen(
      tester,
      CalendarScreen(
        repository: FakeJobRepository(readyState([job])),
        preferences: FakePreferences(),
        onOpenJob: (_) {},
      ),
    );
    expect(find.text('Dec 2099'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    expect(find.text('Jan 2100'), findsNothing);
  });

  testWidgets('exact closing time uses its actual IST day and month', (
    tester,
  ) async {
    appLanguage.value = AppLang.en;
    final job = makeJob(
      applicationEndDate: '2099-12-31',
      applicationEndAt: DateTime.utc(2099, 12, 31, 19),
    );
    await pumpScreen(
      tester,
      CalendarScreen(
        repository: FakeJobRepository(readyState([job])),
        preferences: FakePreferences(),
        onOpenJob: (_) {},
      ),
    );
    expect(find.text('Jan 2100'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Dec 2099'), findsNothing);
  });
}
