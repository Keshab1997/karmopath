import 'dart:convert';

import 'package:flutter/material.dart';

import '../../contracts/app_actions.dart';
import '../../contracts/job.dart';
import '../../data/cached_job_repository.dart';
import '../../data/feed_cache.dart';
import '../../data/feed_transport.dart';
import '../../data/local_user_preferences.dart';
import '../../data/preferences_store.dart';
import '../../design_system/karmopath_theme.dart';
import '../../features/home/home_screen.dart';
import '../../features/saved/saved_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/job_detail/job_detail_screen.dart';

/// Explicitly selected by KARMOPATH_PREVIEW=true. No production network,
/// persistent storage, platform permissions, ads or publisher credentials.
class KarmopathPreviewApp extends StatefulWidget {
  const KarmopathPreviewApp({super.key});
  @override
  State<KarmopathPreviewApp> createState() => _KarmopathPreviewAppState();
}

class _KarmopathPreviewAppState extends State<KarmopathPreviewApp> {
  late final LocalUserPreferences preferences;
  late final CachedJobRepository repository;
  final actions = _PreviewActions();
  final navigatorKey = GlobalKey<NavigatorState>();
  int tab = 0;
  @override
  void initState() {
    super.initState();
    preferences = LocalUserPreferences(store: _SessionStore());
    repository = CachedJobRepository(
      transport: _DemoTransport(),
      cache: _SessionCache(),
    );
    _load();
  }

  Future<void> _load() async {
    await preferences.initialize();
    await repository.refresh();
  }

  @override
  void dispose() {
    repository.dispose();
    preferences.dispose();
    super.dispose();
  }

  void _openJob(String id) {
    final jobs = repository.state.value.feed?.jobs ?? <Job>[];
    final matches = jobs.where((job) => job.id == id);
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => matches.isEmpty
            ? Scaffold(
                appBar: AppBar(title: const Text('Unavailable')),
                body: const Center(child: Text('Sample no longer available.')),
              )
            : JobDetailScreen(
                job: matches.first,
                preferences: preferences,
                actions: actions,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    title: 'Karmopath · Design preview',
    theme: KarmopathTheme.light(),
    builder: (context, child) => Column(
      children: [
        Material(
          color: const Color(0xFFFFE7C2),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  'DEMO · নমুনা তথ্য, বাস্তব চাকরি নয়। Saved: এই session-এ। Links/reminders বন্ধ।',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: const Color(0xFF513000)),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: child ?? const SizedBox.shrink()),
      ],
    ),
    home: Scaffold(
      body: IndexedStack(
        index: tab,
        children: [
          HomeScreen(
            repository: repository,
            preferences: preferences,
            onOpenJob: _openJob,
          ),
          SavedScreen(
            repository: repository,
            preferences: preferences,
            onOpenJob: _openJob,
          ),
          CalendarScreen(
            repository: repository,
            preferences: preferences,
            onOpenJob: _openJob,
          ),
          SettingsScreen(actions: actions),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Saved',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Settings',
          ),
        ],
      ),
    ),
  );
}

class _PreviewActions implements AppActions {
  @override
  Future<void> openExternal(Uri uri) async => throw UnsupportedError(
    'External actions are disabled in design preview.',
  );
  @override
  Future<bool> requestReminderPermission() async => false;
}

class _SessionStore implements PreferencesStore {
  final Map<String, List<String>> values = {};
  @override
  Future<List<String>?> readStrings(String key) async =>
      values[key] == null ? null : List.of(values[key]!);
  @override
  Future<void> writeStrings(String key, List<String> items) async {
    values[key] = List.of(items);
  }
}

class _SessionCache implements FeedCache {
  String? raw;
  @override
  Future<String?> read() async => raw;
  @override
  Future<void> write(String value) async {
    raw = value;
  }
}

class _DemoTransport implements FeedTransport {
  @override
  Future<String> fetch() async {
    final now = DateTime.now().toUtc();
    final ist = now.add(const Duration(hours: 5, minutes: 30));
    final entries = <Map<String, dynamic>>[];
    final samples = [
      ('office', 'অফিস অ্যাসিস্ট্যান্ট · নমুনা', 'Office Assistant · DEMO', 3),
      ('railway', 'রেল টেকনিশিয়ান · নমুনা', 'Railway Technician · DEMO', 7),
      (
        'banking',
        'ব্যাঙ্ক অ্যাসিস্ট্যান্ট · নমুনা',
        'Bank Assistant · DEMO',
        12,
      ),
    ];
    for (final (category, bn, en, days) in samples) {
      final reviewed = now.subtract(const Duration(hours: 1)).toIso8601String();
      entries.add({
        'id': 'demo-$category',
        'kind': 'recruitment',
        'category': category,
        'title_bn': bn,
        'title_en': en,
        'organization': 'DEMO · বাস্তব নিয়োগ নয়',
        'districts': ['West Bengal'],
        'qualifications': ['Graduate · sample only'],
        'status': 'open',
        'source_url': 'https://example.org/demo',
        'notice_url': 'https://example.org/demo',
        'reviewed_at': reviewed,
        'published_at': reviewed,
        'updated_at': now.toIso8601String(),
        'summary_bn':
            'শুধু ডিজাইন দেখানোর নমুনা। এটি বাস্তব চাকরির বিজ্ঞপ্তি নয়।',
        'summary_en': 'Design sample only. This is not a real vacancy or verified recruitment notice.',
        'how_to_apply_bn': 'এই নমুনায় আবেদন করা যাবে না।',
        'how_to_apply_en': 'Do not apply. Sample only.',
        'vacancies': null,
        'application_start_date': null,
        'application_end_date': ist
            .add(Duration(days: days))
            .toIso8601String()
            .substring(0, 10),
        'application_end_at': null,
        'exam_date': null,
        'apply_url': null,
        'age_note_bn': null,
        'age_note_en': null,
      });
    }
    return jsonEncode({
      'schema_version': 1,
      'updated_at': now.toIso8601String(),
      'jobs': entries,
    });
  }
}
