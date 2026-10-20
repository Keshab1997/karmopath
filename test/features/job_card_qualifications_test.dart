import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/features/common/app_language.dart';
import 'package:karmopath/features/common/strings.dart';
import 'package:karmopath/features/common/widgets/job_card.dart';
import 'package:karmopath/features/home/home_screen.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => appLanguage.value = AppLang.bn);
  tearDown(() => appLanguage.value = AppLang.bn);

  final clock = DateTime.utc(2026, 10, 20, 5, 40);

  Widget card(Job job) => MaterialApp(
    home: Scaffold(
      body: JobCard(
        job: job,
        lang: AppLang.bn,
        now: clock,
        preferences: FakePreferences(),
        onTap: () {},
      ),
    ),
  );

  Widget home(FakeJobRepository repo) => HomeScreen(
    repository: repo,
    preferences: FakePreferences(),
    onOpenJob: (_) {},
  );

  testWidgets('both routes show, not only the first', (tester) async {
    final job = makeJob(
      qualifications: const [
        'Higher Secondary (12th) with 50% marks, or 10th + ITI/NAC',
        'Degree/Diploma in the applied discipline',
      ],
    );
    await pumpScreen(tester, card(job));

    expect(find.text(job.qualifications[0]), findsOneWidget);
    expect(find.text(job.qualifications[1]), findsOneWidget);
    // Nothing was left out, so the card must not claim a remainder.
    expect(find.text(K.moreQualifications(1, AppLang.bn)), findsNothing);
    expect(find.byIcon(Icons.school_outlined), findsOneWidget);
  });

  testWidgets('a long route gets two lines, not one cut line', (tester) async {
    final job = makeJob(
      qualifications: const [
        'Higher Secondary (12th) with 50% marks in the aggregate from a '
            'recognised board',
      ],
    );
    await pumpScreen(tester, card(job), surfaceSize: const Size(320, 720));

    final rendered = tester.widget<Text>(find.text(job.qualifications.first));
    expect(rendered.maxLines, 2);
    expect(rendered.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a third route is counted, not dropped', (tester) async {
    final job = makeJob(
      qualifications: const [
        'First route',
        'Second route',
        'Third route',
      ],
    );
    await pumpScreen(tester, card(job));

    expect(find.text('First route'), findsOneWidget);
    expect(find.text('Second route'), findsOneWidget);
    expect(find.text('Third route'), findsNothing);
    expect(find.text('আরও ১টি যোগ্যতার শর্ত'), findsOneWidget);
  });

  testWidgets('a notice with no eligibility shows no line', (tester) async {
    final job = makeJob(
      kind: JobKind.notice,
      status: JobStatus.published,
      qualifications: const [],
      vacancies: null,
      hasDeadline: false,
    );
    await pumpScreen(tester, card(job));

    expect(find.byIcon(Icons.school_outlined), findsNothing);
    expect(find.textContaining('যোগ্যতার শর্ত'), findsNothing);
    // The district line keeps its icon offset, so nothing shifts left.
    expect(find.text('Kolkata'), findsOneWidget);
  });

  testWidgets('the heading counts the cards shown', (tester) async {
    final only = makeJob(id: 'one', qualifications: const ['Madhyamik pass']);
    await pumpScreen(tester, home(FakeJobRepository(readyState([only]))));

    expect(find.text('সাম্প্রতিক সুযোগ'), findsOneWidget);
    expect(find.text('১টি সুযোগ'), findsOneWidget);
    // The hero subtitle also says "আপডেট", so this checks the count phrase:
    // a total of the feed must not read as "N updates".
    expect(find.textContaining('টি আপডেট'), findsNothing);

    final both = [only, makeJob(id: 'two')];
    await pumpScreen(tester, home(FakeJobRepository(readyState(both))));
    expect(find.text('২টি সুযোগ'), findsOneWidget);
  });

  test('the card caps eligibility lines at two', () {
    expect(JobCard.maxQualifications, 2);
  });
}
