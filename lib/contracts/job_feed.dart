import 'job.dart';

class JobFeed {
  final int schemaVersion;
  final DateTime updatedAt;
  final List<Job> jobs;
  JobFeed({
    required this.schemaVersion,
    required this.updatedAt,
    required List<Job> jobs,
  }) : jobs = List.unmodifiable(jobs);
  factory JobFeed.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] is! int ||
        json['schema_version'] != 1 ||
        json['jobs'] is! List) {
      throw const FormatException('Invalid feed schema');
    }
    final raw = json['updated_at'];
    final date = raw is String ? DateTime.tryParse(raw) : null;
    if (date == null || !(raw as String).endsWith('Z')) {
      throw const FormatException('Invalid feed updated_at');
    }
    final jobs = (json['jobs'] as List).map((j) {
      if (j is! Map<String, dynamic>) {
        throw const FormatException('Invalid job');
      }
      return Job.fromJson(j);
    }).toList();
    if (jobs.map((j) => j.id).toSet().length != jobs.length) {
      throw const FormatException('Duplicate IDs');
    }
    return JobFeed(schemaVersion: 1, updatedAt: date.toUtc(), jobs: jobs);
  }
  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'jobs': jobs.map((j) => j.toJson()).toList(),
  };
}
