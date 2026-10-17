import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job.dart';
import 'package:karmopath/contracts/job_feed.dart';

Map<String, dynamic> sample() => Map<String, dynamic>.from(
  (jsonDecode(File('test/fixtures/sample_feed.json').readAsStringSync())['jobs']
              as List)
          .first
      as Map,
);
void main() {
  test('sample model round trips and list is immutable', () {
    final j = Job.fromJson(sample());
    expect(Job.fromJson(j.toJson()).toJson(), j.toJson());
    expect(() => j.districts.add('Elsewhere'), throwsUnsupportedError);
  });
  final cases = <String, Map<String, dynamic>>{
    'bad url': {'source_url': 'javascript:alert(1)'},
    'bad enum': {'category': 'unknown'},
    'negative vacancy': {'vacancies': -1},
    'fractional vacancy': {'vacancies': 1.5},
    'impossible date': {'application_end_date': '2026-02-30'},
    'inverted dates': {'application_start_date': '2026-02-01'},
    'missing deadline': {'application_end_date': null},
    'missing Bengali': {'title_bn': ''},
    'future review': {'reviewed_at': '2099-01-01T00:00:00Z'},
    'result cannot be open': {'kind': 'result'},
  };
  for (final entry in cases.entries) {
    test(entry.key, () {
      expect(
        () => Job.fromJson({...sample(), ...entry.value}),
        throwsFormatException,
      );
    });
  }
  test('duplicate ID rejected', () {
    final j = sample();
    expect(
      () => JobFeed.fromJson({
        'schema_version': 1,
        'updated_at': '2026-01-01T00:00:00Z',
        'jobs': [j, j],
      }),
      throwsFormatException,
    );
  });
  test('missing nullable key is invalid', () {
    final j = sample()..remove('apply_url');
    expect(() => Job.fromJson(j), throwsFormatException);
  });
}
