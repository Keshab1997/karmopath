import 'package:karmopath/contracts/job.dart';

/// Builders for planner tests.
///
/// Deliberately explicit about the two deadline shapes the contract allows:
/// an exact UTC `applicationEndAt` and a date-only `applicationEndDate`
/// (inclusive through its Asia/Kolkata day).
Job job({
  String id = 'wb-police-constable-2026',
  JobKind kind = JobKind.recruitment,
  JobStatus status = JobStatus.open,
  String titleBn = 'পশ্চিমবঙ্গ পুলিশ কনস্টেবল নিয়োগ ২০২৬',
  String titleEn = 'West Bengal Police constable recruitment 2026',
  String organization = 'West Bengal Police Recruitment Board',
  String? endDate,
  DateTime? endAt,
}) {
  return Job(
    id: id,
    kind: kind,
    titleBn: titleBn,
    titleEn: titleEn,
    organization: organization,
    category: JobCategory.police,
    districts: const ['West Bengal'],
    qualifications: const ['Madhyamik'],
    status: status,
    sourceUrl: 'https://example.org/source',
    noticeUrl: 'https://example.org/notice',
    reviewedAt: DateTime.utc(2026, 1, 1),
    publishedAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    summaryBn: 'নমুনা সারসংক্ষেপ।',
    summaryEn: 'Sample summary.',
    howToApplyBn: '',
    howToApplyEn: '',
    vacancies: 100,
    applicationStartDate: '2026-01-01',
    applicationEndDate: endDate,
    applicationEndAt: endAt,
    examDate: null,
    applyUrl: null,
    ageNoteBn: null,
    ageNoteEn: null,
  );
}

/// A job whose deadline is an exact UTC instant (authoritative over date-only).
Job exactDeadlineJob({
  String id = 'wb-police-constable-2026',
  DateTime? closesAt,
  JobStatus status = JobStatus.open,
  JobKind kind = JobKind.recruitment,
  String titleBn = 'পশ্চিমবঙ্গ পুলিশ কনস্টেবল নিয়োগ ২০২৬',
  String titleEn = 'West Bengal Police constable recruitment 2026',
  String? endDate,
}) => job(
  id: id,
  kind: kind,
  status: status,
  titleBn: titleBn,
  titleEn: titleEn,
  endAt: closesAt,
  endDate: endDate,
);

/// A job whose deadline is date-only, inclusive through its IST day.
Job dateOnlyJob({
  String id = 'wb-health-recruitment-2026',
  required String endDate,
  JobStatus status = JobStatus.open,
  JobKind kind = JobKind.recruitment,
  String titleBn = 'স্বাস্থ্য দপ্তর নিয়োগ ২০২৬',
  String titleEn = 'Health department recruitment 2026',
}) => job(
  id: id,
  kind: kind,
  status: status,
  titleBn: titleBn,
  titleEn: titleEn,
  endDate: endDate,
);
