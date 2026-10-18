import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/app_actions.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/contracts/job_feed.dart';
import 'package:karmopath/contracts/job_repository.dart';
import 'package:karmopath/contracts/user_preferences.dart';
import 'package:karmopath/design_system/karmopath_theme.dart';

/// In-memory JobRepository driven entirely by the test.
class FakeJobRepository implements JobRepository {
  FakeJobRepository(JobFeedState initial) : state = ValueNotifier(initial);

  @override
  final ValueNotifier<JobFeedState> state;

  int refreshCalls = 0;

  /// When set, [refresh] replaces the state once (simulates a live refresh).
  JobFeedState? nextState;

  @override
  Future<void> refresh() async {
    refreshCalls += 1;
    final next = nextState;
    if (next != null) state.value = next;
  }

  @override
  Future<void> dispose() async {
    state.dispose();
  }
}

class FakePreferences implements UserPreferences {
  FakePreferences({
    Set<String>? saved,
    Set<String>? reminders,
    this.throwOnWrite = false,
    this.writeDelay = Duration.zero,
  }) : savedJobIds = ValueNotifier(<String>{...?saved}),
       reminderJobIds = ValueNotifier(<String>{...?reminders});

  /// Simulates a failed local store write.
  final bool throwOnWrite;

  /// Simulates a slow store so rapid-tap guards can be tested.
  final Duration writeDelay;

  @override
  final ValueNotifier<Set<String>> savedJobIds;

  @override
  final ValueNotifier<Set<String>> reminderJobIds;

  final List<(String, bool)> savedCalls = [];
  final List<(String, bool)> reminderCalls = [];

  @override
  Future<void> setSaved(String jobId, bool saved) async {
    if (writeDelay > Duration.zero) await Future<void>.delayed(writeDelay);
    if (throwOnWrite) throw StateError('storage unavailable');
    savedCalls.add((jobId, saved));
    final next = <String>{...savedJobIds.value};
    saved ? next.add(jobId) : next.remove(jobId);
    savedJobIds.value = next;
  }

  @override
  Future<void> setReminder(String jobId, bool enabled) async {
    if (throwOnWrite) throw StateError('storage unavailable');
    reminderCalls.add((jobId, enabled));
    final next = <String>{...reminderJobIds.value};
    enabled ? next.add(jobId) : next.remove(jobId);
    reminderJobIds.value = next;
  }
}

class FakeActions implements AppActions {
  FakeActions({
    this.permission = true,
    this.permissionThrows = false,
    this.openDelay = Duration.zero,
    this.openThrowsAsync = false,
    this.openThrowsSync = false,
    this.permissionDelay = Duration.zero,
  });

  bool permission;

  /// Simulates an unavailable/failed permission channel.
  bool permissionThrows;

  /// Simulates a slow platform launcher so rapid taps can be tested.
  Duration openDelay;

  /// Simulates a launcher that fails after its future is awaited.
  bool openThrowsAsync;

  /// Simulates a launcher that throws before returning a future.
  bool openThrowsSync;

  /// Simulates a slow permission dialog.
  Duration permissionDelay;

  int permissionRequests = 0;
  final List<Uri> opened = [];

  @override
  Future<void> openExternal(Uri uri) async {
    if (openThrowsSync) throw StateError('launcher unavailable (sync)');
    if (openDelay > Duration.zero) await Future<void>.delayed(openDelay);
    if (openThrowsAsync) throw StateError('launcher unavailable (async)');
    opened.add(uri);
  }

  @override
  Future<bool> requestReminderPermission() async {
    permissionRequests += 1;
    if (permissionDelay > Duration.zero) {
      await Future<void>.delayed(permissionDelay);
    }
    if (permissionThrows) throw StateError('permission channel unavailable');
    return permission;
  }
}

DateTime utcNow() => DateTime.now().toUtc();

/// ISO date (YYYY-MM-DD) for a UTC instant, used for date-only fields.
String dateOnly(DateTime utc) => utc.toIso8601String().substring(0, 10);

/// Builds a schema-valid [Job] without going through JSON parsing.
Job makeJob({
  String id = 'wb-police-constable-2026',
  JobKind kind = JobKind.recruitment,
  String titleBn = 'ডব্লিউবি পুলিশ কনস্টেবল নিয়োগ ২০২৬',
  String titleEn = 'WB Police Constable Recruitment 2026',
  String organization = 'West Bengal Police Recruitment Board',
  JobCategory category = JobCategory.police,
  List<String> districts = const ['Kolkata'],
  List<String> qualifications = const ['Madhyamik pass'],
  JobStatus status = JobStatus.open,
  String? applicationStartDate,
  String? applicationEndDate,
  DateTime? applicationEndAt,
  bool hasDeadline = true,
  String? examDate,
  int? vacancies = 1200,
  String? applyUrl,
  String summaryBn = 'মূল বিজ্ঞপ্তি অনুযায়ী নিয়োগ।',
  String summaryEn = 'Recruitment as per the original notice.',
  String howToApplyBn = 'অনলাইনে আবেদন করুন।',
  String howToApplyEn = 'Apply online.',
  DateTime? publishedAt,
  DateTime? reviewedAt,
  DateTime? updatedAt,
}) {
  final now = utcNow();
  final published = publishedAt ?? now.subtract(const Duration(hours: 2));
  final reviewed = reviewedAt ?? now.subtract(const Duration(hours: 1));
  return Job(
    id: id,
    kind: kind,
    titleBn: titleBn,
    titleEn: titleEn,
    organization: organization,
    category: category,
    districts: districts,
    qualifications: qualifications,
    status: status,
    sourceUrl: 'https://wbp.example.gov.in/notice-$id',
    noticeUrl: 'https://wbp.example.gov.in/notice-$id.pdf',
    reviewedAt: reviewed,
    publishedAt: published,
    updatedAt: updatedAt ?? now,
    summaryBn: summaryBn,
    summaryEn: summaryEn,
    howToApplyBn: howToApplyBn,
    howToApplyEn: howToApplyEn,
    vacancies: vacancies,
    applicationStartDate:
        applicationStartDate ?? dateOnly(now.subtract(const Duration(days: 3))),
    applicationEndDate: hasDeadline
        ? (applicationEndDate ?? dateOnly(now.add(const Duration(days: 10))))
        : null,
    applicationEndAt: applicationEndAt,
    examDate: examDate,
    applyUrl: applyUrl,
    ageNoteBn: '১৮–২৭ বছর',
    ageNoteEn: '18–27 years',
  );
}

JobFeed makeFeed(List<Job> jobs) =>
    JobFeed(schemaVersion: 1, updatedAt: utcNow(), jobs: jobs);

JobFeedState readyState(List<Job> jobs) => JobFeedState(feed: makeFeed(jobs));

/// Mounts a screen with the real theme, as the app shell would.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Size? surfaceSize,
  double textScale = 1.0,
}) async {
  if (surfaceSize != null) {
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: KarmopathTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: screen,
    ),
  );
  await tester.pump();
}

/// Scrolls the first (outer) scrollable until [finder] is visible.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    280,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}
