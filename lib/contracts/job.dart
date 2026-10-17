enum JobKind { recruitment, result, admitCard }

enum JobCategory { police, railway, banking, teaching, medical, office, other }

enum JobStatus { open, closed, withdrawn, published }

class Job {
  final String id;
  final JobKind kind;
  final String titleBn;
  final String titleEn;
  final String organization;
  final JobCategory category;
  final List<String> districts;
  final List<String> qualifications;
  final JobStatus status;
  final String sourceUrl;
  final String noticeUrl;
  final DateTime reviewedAt;
  final DateTime publishedAt;
  final DateTime updatedAt;
  final String summaryBn;
  final String summaryEn;
  final String howToApplyBn;
  final String howToApplyEn;
  final int? vacancies;
  final String? applicationStartDate;
  final String? applicationEndDate;
  final DateTime? applicationEndAt;
  final String? examDate;
  final String? applyUrl;
  final String? ageNoteBn;
  final String? ageNoteEn;
  Job({
    required this.id,
    required this.kind,
    required this.titleBn,
    required this.titleEn,
    required this.organization,
    required this.category,
    required List<String> districts,
    required List<String> qualifications,
    required this.status,
    required this.sourceUrl,
    required this.noticeUrl,
    required this.reviewedAt,
    required this.publishedAt,
    required this.updatedAt,
    required this.summaryBn,
    required this.summaryEn,
    required this.howToApplyBn,
    required this.howToApplyEn,
    required this.vacancies,
    required this.applicationStartDate,
    required this.applicationEndDate,
    required this.applicationEndAt,
    required this.examDate,
    required this.applyUrl,
    required this.ageNoteBn,
    required this.ageNoteEn,
  }) : districts = List.unmodifiable(districts),
       qualifications = List.unmodifiable(qualifications);
  factory Job.fromJson(Map<String, dynamic> json) {
    return parseJob(json);
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind == JobKind.admitCard ? 'admit_card' : kind.name,
    'title_bn': titleBn,
    'title_en': titleEn,
    'organization': organization,
    'category': category.name,
    'districts': districts,
    'qualifications': qualifications,
    'status': status.name,
    'source_url': sourceUrl,
    'notice_url': noticeUrl,
    'reviewed_at': reviewedAt.toUtc().toIso8601String(),
    'published_at': publishedAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'summary_bn': summaryBn,
    'summary_en': summaryEn,
    'how_to_apply_bn': howToApplyBn,
    'how_to_apply_en': howToApplyEn,
    'vacancies': vacancies,
    'application_start_date': applicationStartDate,
    'application_end_date': applicationEndDate,
    'application_end_at': applicationEndAt?.toUtc().toIso8601String(),
    'exam_date': examDate,
    'apply_url': applyUrl,
    'age_note_bn': ageNoteBn,
    'age_note_en': ageNoteEn,
  };
}

String _text(Map<String, dynamic> j, String k, {bool empty = false}) {
  final v = j[k];
  if (v is! String || (!empty && v.trim().isEmpty)) {
    throw FormatException('Invalid $k');
  }
  return v;
}

DateTime _time(Map<String, dynamic> j, String k) {
  final v = _text(j, k);
  final d = DateTime.tryParse(v);
  if (!v.endsWith('Z') || d == null) throw FormatException('Invalid UTC $k');
  return d.toUtc();
}

String? _date(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v == null) return null;
  if (v is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) {
    throw FormatException('Invalid $k');
  }
  final d = DateTime.tryParse(v);
  if (d == null || d.toIso8601String().substring(0, 10) != v) {
    throw FormatException('Invalid $k');
  }
  return v;
}

String _url(Map<String, dynamic> j, String k) {
  final v = _text(j, k);
  final u = Uri.tryParse(v);
  if (u == null ||
      u.scheme != 'https' ||
      u.host.isEmpty ||
      u.userInfo.isNotEmpty) {
    throw FormatException('Invalid HTTPS $k');
  }
  return v;
}

List<String> _strings(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v is! List || v.any((e) => e is! String || e.trim().isEmpty)) {
    throw FormatException('Invalid $k');
  }
  return List<String>.from(v);
}

T _enum<T>(Object? value, Map<String, T> values, String key) {
  if (!values.containsKey(value)) throw FormatException('Invalid $key');
  return values[value] as T;
}

Job parseJob(Map<String, dynamic> j) {
  final requiredKeys = <String>{
    'id',
    'kind',
    'title_bn',
    'title_en',
    'organization',
    'category',
    'districts',
    'qualifications',
    'status',
    'source_url',
    'notice_url',
    'reviewed_at',
    'published_at',
    'updated_at',
    'summary_bn',
    'summary_en',
    'how_to_apply_bn',
    'how_to_apply_en',
    'vacancies',
    'application_start_date',
    'application_end_date',
    'application_end_at',
    'exam_date',
    'apply_url',
    'age_note_bn',
    'age_note_en',
  };
  if (!requiredKeys.every(j.containsKey)) {
    throw const FormatException('Missing job keys');
  }
  final id = _text(j, 'id');
  if (!RegExp(r'^[a-z0-9-]{1,100}$').hasMatch(id)) {
    throw const FormatException('Invalid id');
  }
  final count = j['vacancies'];
  if (count != null && (count is! int || count < 0)) {
    throw const FormatException('Invalid vacancies');
  }
  final job = Job(
    id: _text(j, 'id'),
    kind: _enum(j['kind'], {
      'recruitment': JobKind.recruitment,
      'result': JobKind.result,
      'admit_card': JobKind.admitCard,
    }, 'kind'),
    titleBn: _text(j, 'title_bn'),
    titleEn: _text(j, 'title_en'),
    organization: _text(j, 'organization'),
    category: _enum(j['category'], {
      'police': JobCategory.police,
      'railway': JobCategory.railway,
      'banking': JobCategory.banking,
      'teaching': JobCategory.teaching,
      'medical': JobCategory.medical,
      'office': JobCategory.office,
      'other': JobCategory.other,
    }, 'category'),
    districts: _strings(j, 'districts'),
    qualifications: _strings(j, 'qualifications'),
    status: _enum(j['status'], {
      'open': JobStatus.open,
      'closed': JobStatus.closed,
      'withdrawn': JobStatus.withdrawn,
      'published': JobStatus.published,
    }, 'status'),
    sourceUrl: _url(j, 'source_url'),
    noticeUrl: _url(j, 'notice_url'),
    reviewedAt: _time(j, 'reviewed_at'),
    publishedAt: _time(j, 'published_at'),
    updatedAt: _time(j, 'updated_at'),
    summaryBn: _text(j, 'summary_bn'),
    summaryEn: _text(j, 'summary_en'),
    howToApplyBn: _text(j, 'how_to_apply_bn', empty: true),
    howToApplyEn: _text(j, 'how_to_apply_en', empty: true),
    vacancies: count as int?,
    applicationStartDate: _date(j, 'application_start_date'),
    applicationEndDate: _date(j, 'application_end_date'),
    applicationEndAt: j['application_end_at'] == null
        ? null
        : _time(j, 'application_end_at'),
    examDate: _date(j, 'exam_date'),
    applyUrl: j['apply_url'] == null ? null : _url(j, 'apply_url'),
    ageNoteBn: j['age_note_bn'] == null
        ? null
        : _text(j, 'age_note_bn', empty: true),
    ageNoteEn: j['age_note_en'] == null
        ? null
        : _text(j, 'age_note_en', empty: true),
  );
  if (job.updatedAt.isBefore(job.publishedAt) ||
      job.reviewedAt.isAfter(job.updatedAt)) {
    throw const FormatException('Invalid timestamp order');
  }
  final maxTime = DateTime.now().toUtc().add(const Duration(minutes: 5));
  if (job.reviewedAt.isAfter(maxTime) || job.publishedAt.isAfter(maxTime)) {
    throw const FormatException('Future timestamp');
  }
  if (job.applicationStartDate != null &&
      job.applicationEndDate != null &&
      job.applicationStartDate!.compareTo(job.applicationEndDate!) > 0) {
    throw const FormatException('Invalid application dates');
  }
  if (job.kind == JobKind.recruitment &&
      job.status == JobStatus.open &&
      job.applicationEndDate == null) {
    throw const FormatException('Open recruitment needs deadline');
  }
  if (job.kind != JobKind.recruitment &&
      (job.status == JobStatus.open || job.status == JobStatus.closed)) {
    throw const FormatException('Invalid update status');
  }
  return job;
}
