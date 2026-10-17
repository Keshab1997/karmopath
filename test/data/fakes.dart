import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:karmopath/contracts/job_repository.dart';
import 'package:karmopath/data/feed_cache.dart';
import 'package:karmopath/data/feed_transport.dart';
import 'package:karmopath/data/preferences_store.dart';

/// A transport whose answer is supplied per test; counts calls so concurrency
/// behaviour can be asserted.
class FakeTransport implements FeedTransport {
  FakeTransport(this._fetch);

  FakeTransport.json(String raw) : _fetch = (() async => raw);

  FakeTransport.failing(Object error) : _fetch = (() async => throw error);

  final Future<String> Function() _fetch;
  int calls = 0;

  @override
  Future<String> fetch() {
    calls++;
    return _fetch();
  }
}

/// A transport whose next answer is swapped between refreshes: a [String] is
/// returned as the payload, anything else is thrown as the transport error.
class SwitchTransport implements FeedTransport {
  SwitchTransport(this.next);

  Object next;
  int calls = 0;

  @override
  Future<String> fetch() async {
    calls++;
    final value = next;
    if (value is String) return value;
    throw value;
  }
}

/// In-memory cache with injectable read/write failures.
class FakeCache implements FeedCache {
  FakeCache({this.stored});

  String? stored;
  int reads = 0;
  int writes = 0;
  Object? readError;
  Object? writeError;

  @override
  Future<String?> read() async {
    reads++;
    final failure = readError;
    if (failure != null) throw failure;
    return stored;
  }

  @override
  Future<void> write(String raw) async {
    writes++;
    final failure = writeError;
    if (failure != null) throw failure;
    stored = raw;
  }
}

/// In-memory preference store with per-key read failures and a shared write
/// failure switch, mirroring a platform store that can fail without warning.
class FakePreferencesStore implements PreferencesStore {
  FakePreferencesStore({Map<String, List<String>>? initial})
    : data = {...?initial};

  final Map<String, List<String>> data;
  final Map<String, Object> readErrors = {};
  final Map<String, int> readCounts = {};
  final Map<String, int> writeCounts = {};
  final List<String> writeKeys = [];
  Object? writeError;

  @override
  Future<List<String>?> readStrings(String key) async {
    readCounts[key] = (readCounts[key] ?? 0) + 1;
    final failure = readErrors[key];
    if (failure != null) throw failure;
    final value = data[key];
    return value == null ? null : List<String>.of(value);
  }

  @override
  Future<void> writeStrings(String key, List<String> values) async {
    writeCounts[key] = (writeCounts[key] ?? 0) + 1;
    writeKeys.add(key);
    final failure = writeError;
    if (failure != null) throw failure;
    data[key] = List<String>.of(values);
  }
}

/// A contract-valid job. Timestamps stay in the past and the open recruitment
/// keeps an inclusive end date, as the frozen schema requires.
Map<String, dynamic> jobJson({
  String id = 'wb-police-constable-2026',
  String kind = 'recruitment',
  String status = 'open',
  String titleBn = 'পশ্চিমবঙ্গ পুলিশ কনস্টেবল নিয়োগ',
  String titleEn = 'West Bengal Police constable recruitment',
  String applicationEndDate = '2026-01-31',
}) => <String, dynamic>{
  'id': id,
  'kind': kind,
  'title_bn': titleBn,
  'title_en': titleEn,
  'organization': 'West Bengal Police Recruitment Board',
  'category': 'police',
  'districts': ['West Bengal'],
  'qualifications': ['Madhyamik'],
  'status': status,
  'source_url': 'https://example.org/source',
  'notice_url': 'https://example.org/notice',
  'reviewed_at': '2026-01-01T00:00:00Z',
  'published_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
  'summary_bn': 'নমুনা সারসংক্ষেপ।',
  'summary_en': 'Sample summary.',
  'how_to_apply_bn': '',
  'how_to_apply_en': '',
  'vacancies': 100,
  'application_start_date': '2026-01-01',
  'application_end_date': applicationEndDate,
  'application_end_at': null,
  'exam_date': null,
  'apply_url': null,
  'age_note_bn': null,
  'age_note_en': null,
};

/// Encodes a feed envelope; [schemaVersion] and [jobs] are overridable so tests
/// can express unknown-schema and duplicate-id payloads.
String feedJson({
  Object schemaVersion = 1,
  List<Map<String, dynamic>>? jobs,
  String updatedAt = '2026-01-01T00:00:00Z',
}) => jsonEncode({
  'schema_version': schemaVersion,
  'updated_at': updatedAt,
  'jobs': jobs ?? [jobJson()],
});

/// Records every state a repository publishes, in order.
class StateRecorder {
  StateRecorder(ValueListenable<JobFeedState> listenable)
    : _source = listenable {
    _source.addListener(_record);
  }

  final ValueListenable<JobFeedState> _source;
  final List<JobFeedState> states = <JobFeedState>[];

  void _record() => states.add(_source.value);

  void dispose() => _source.removeListener(_record);

  List<JobFeedState> get loadingStates =>
      states.where((s) => s.isLoading).toList();

  JobFeedState get last => states.last;
}
