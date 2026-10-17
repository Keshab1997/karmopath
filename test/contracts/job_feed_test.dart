import 'package:flutter_test/flutter_test.dart';
import 'package:karmopath/contracts/job_feed.dart';

void main() {
  test('empty feed round trips', () {
    final f = JobFeed.fromJson({
      'schema_version': 1,
      'updated_at': '2026-01-01T00:00:00Z',
      'jobs': [],
    });
    expect(JobFeed.fromJson(f.toJson()).jobs, isEmpty);
  });
  test('unknown schema fails', () {
    expect(
      () => JobFeed.fromJson({
        'schema_version': 2,
        'updated_at': '2026-01-01T00:00:00Z',
        'jobs': [],
      }),
      throwsFormatException,
    );
  });
}
