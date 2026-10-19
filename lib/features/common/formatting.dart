import '../../contracts/job.dart';
import 'app_language.dart';
import 'strings.dart';

/// Asia/Kolkata has no DST, so a fixed offset is exact for every date here.
const Duration istOffset = Duration(hours: 5, minutes: 30);

/// Deadline model used by every B screen. Comparisons are UTC-based.
///
/// Date-only values (`application_end_date`) are inclusive through the end of
/// that calendar day in Asia/Kolkata, per docs/CONTRACTS.md. An exact
/// `application_end_at` timestamp is used as supplied; no closing time is
/// ever invented for date-only deadlines.
class DeadlineInfo {
  const DeadlineInfo({
    required this.closesAtUtc,
    required this.isWithdrawn,
    required this.isClosed,
    required this.expired,
    required this.serverClosed,
    required this.remaining,
    required this.closesSoon,
  });

  /// Effective closing instant (UTC), null when the feed has no deadline.
  final DateTime? closesAtUtc;
  final bool isWithdrawn;

  /// Closed because of the feed status *or* because the deadline has passed.
  final bool isClosed;

  /// The deadline itself has passed: the feed's own scheduled close is known
  /// to have happened. Only this can be reported as "closed on {date}".
  final bool expired;

  /// The feed marked the job closed while its scheduled deadline is still in
  /// the future (early closure). No closure timestamp exists, so none is shown.
  final bool serverClosed;

  /// Time left until [closesAtUtc]; negative after the deadline; null unknown.
  final Duration? remaining;

  /// Open and closing within three days (urgency styling only).
  final bool closesSoon;

  bool get hasDeadline => closesAtUtc != null;
  bool get isOpen => !isClosed && !isWithdrawn;
}

/// Exclusive closing boundary for a date-only deadline.
///
/// The named IST day is inclusive, so the boundary is **00:00 IST of the next
/// day**, expressed in UTC: 2026-11-15 (inclusive) closes at
/// 2026-11-16T00:00 IST == 2026-11-15T18:30:00Z. The final instant of the day
/// (23:59:59.999999 IST) therefore remains open. This boundary is a comparison
/// rule only — it is never displayed as an official closing time.
DateTime istExclusiveNextDayUtc(String dateOnly) {
  final parts = dateOnly.split('-');
  if (parts.length != 3) {
    throw FormatException('Not a date-only value: $dateOnly');
  }
  final y = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  final d = int.parse(parts[2]);
  // DateTime.utc normalises overflow (e.g. day 32, month 13).
  return DateTime.utc(y, m, d).add(const Duration(days: 1)).subtract(istOffset);
}

DateTime? effectiveClosingUtc(Job job) {
  final exact = job.applicationEndAt;
  if (exact != null) return exact.toUtc();
  final dateOnly = job.applicationEndDate;
  if (dateOnly == null) return null;
  try {
    return istExclusiveNextDayUtc(dateOnly);
  } on FormatException {
    return null;
  }
}

DeadlineInfo deadlineInfo(Job job, DateTime now) {
  final closes = effectiveClosingUtc(job);
  final utcNow = now.toUtc();
  final expired = closes != null && !utcNow.isBefore(closes);
  final withdrawn = job.status == JobStatus.withdrawn;
  final serverClosed = job.status == JobStatus.closed && !withdrawn && !expired;
  final remaining = closes?.difference(utcNow);
  final closed = withdrawn || expired || serverClosed;
  return DeadlineInfo(
    closesAtUtc: closes,
    isWithdrawn: withdrawn,
    isClosed: closed,
    expired: expired,
    serverClosed: serverClosed,
    remaining: remaining,
    closesSoon:
        !closed &&
        remaining != null &&
        remaining <= const Duration(days: 3) &&
        remaining > Duration.zero,
  );
}

/// Short status/deadline label for cards. Returns null when nothing should be
/// shown (results and admit cards have no deadline of their own).
///
/// [endDateOnly] is the job's date-only deadline (`YYYY-MM-DD`) when the feed
/// supplied no exact timestamp; passing it keeps closed-date labels free of an
/// invented time of day.
String? deadlineLabel(
  DeadlineInfo info,
  JobKind kind,
  AppLang lang, {
  String? endDateOnly,
}) {
  if (info.isWithdrawn) return K.statusWithdrawn.inLang(lang);
  if (info.isClosed) {
    // Only a deadline that actually passed may be reported as a closure date.
    if (info.expired && info.closesAtUtc != null) {
      final when = endDateOnly != null
          ? formatDateOnly(endDateOnly, lang)
          : formatInstant(info.closesAtUtc!, lang);
      return lang == AppLang.bn ? '$when-এ বন্ধ হয়েছে' : 'Closed on $when';
    }
    // Early server closure: no closure timestamp exists, so none is claimed.
    return K.statusClosed.inLang(lang);
  }
  final remaining = info.remaining;
  if (remaining == null) {
    return kind == JobKind.recruitment ? K.deadlineUnknown.inLang(lang) : null;
  }
  final days = remaining.inDays;
  if (days >= 1) {
    return lang == AppLang.bn
        ? '${toBengaliDigits('$days')} দিনে শেষ হচ্ছে'
        : 'Closes in $days day${days == 1 ? '' : 's'}';
  }
  final hours = remaining.inHours;
  if (hours >= 1) {
    return lang == AppLang.bn
        ? '${toBengaliDigits('$hours')} ঘণ্টায় শেষ হচ্ছে'
        : 'Closes in $hours hour${hours == 1 ? '' : 's'}';
  }
  return lang == AppLang.bn
      ? '১ ঘণ্টারও কম সময় বাকি'
      : 'Closes in under an hour';
}

const List<String> _monthsEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const List<String> _monthsBn = [
  'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', //
  'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর',
];

const String _bnDigits = '০১২৩৪৫৬৭৮৯';

String toBengaliDigits(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    final digit = int.tryParse(char);
    if (digit != null && digit >= 0 && digit <= 9) {
      out.write(_bnDigits[digit]);
    } else {
      out.write(char);
    }
  }
  return out.toString();
}

String _localizeDigits(String value, AppLang lang) =>
    lang == AppLang.bn ? toBengaliDigits(value) : value;

/// UTC instant rendered on the IST wall clock, e.g. `15 Nov 2026, 6:30 PM IST`.
String formatInstant(DateTime utc, AppLang lang) {
  final ist = utc.toUtc().add(istOffset);
  final hour12 = ist.hour % 12 == 0 ? 12 : ist.hour % 12;
  final minute = ist.minute.toString().padLeft(2, '0');
  final suffix = ist.hour < 12 ? 'AM' : 'PM';
  if (lang == AppLang.bn) {
    final time =
        '${toBengaliDigits('$hour12')}:${toBengaliDigits(minute)} $suffix';
    return '${toBengaliDigits('${ist.day}')} ${_monthsBn[ist.month - 1]} '
        '${toBengaliDigits('${ist.year}')}, $time IST';
  }
  return '${ist.day} ${_monthsEn[ist.month - 1]} ${ist.year}, '
      '$hour12:$minute $suffix IST';
}

/// Date-only feed value (`YYYY-MM-DD`) shown without any timezone shift.
String formatDateOnly(String dateOnly, AppLang lang) {
  final date = DateTime.tryParse(dateOnly);
  if (date == null) return _localizeDigits(dateOnly, lang);
  if (lang == AppLang.bn) {
    return '${toBengaliDigits('${date.day}')} ${_monthsBn[date.month - 1]} '
        '${toBengaliDigits('${date.year}')}';
  }
  return '${date.day} ${_monthsEn[date.month - 1]} ${date.year}';
}

String formatMonthYear(DateTime istWallClock, AppLang lang) {
  if (lang == AppLang.bn) {
    return '${_monthsBn[istWallClock.month - 1]} '
        '${toBengaliDigits('${istWallClock.year}')}';
  }
  return '${_monthsEn[istWallClock.month - 1]} ${istWallClock.year}';
}

/// IST wall-clock view of a UTC instant (safe to read year/month/day).
DateTime toIstWallClock(DateTime utc) => utc.toUtc().add(istOffset);

String postedLabel(DateTime publishedAt, DateTime now, AppLang lang) {
  final elapsed = now.toUtc().difference(publishedAt.toUtc());
  if (elapsed.isNegative || elapsed.inMinutes < 1) {
    return lang == AppLang.bn ? 'এইমাত্র প্রকাশিত' : 'Posted just now';
  }
  if (elapsed.inMinutes < 60) {
    final m = elapsed.inMinutes;
    return lang == AppLang.bn
        ? '${toBengaliDigits('$m')} মিনিট আগে প্রকাশিত'
        : 'Posted ${m}m ago';
  }
  if (elapsed.inHours < 24) {
    final h = elapsed.inHours;
    return lang == AppLang.bn
        ? '${toBengaliDigits('$h')} ঘণ্টা আগে প্রকাশিত'
        : 'Posted ${h}h ago';
  }
  if (elapsed.inDays < 30) {
    final d = elapsed.inDays;
    return lang == AppLang.bn
        ? '${toBengaliDigits('$d')} দিন আগে প্রকাশিত'
        : 'Posted ${d}d ago';
  }
  final date = formatInstant(publishedAt, lang);
  return lang == AppLang.bn ? '$date-এ প্রকাশিত' : 'Posted on $date';
}

String kindLabel(JobKind kind, AppLang lang) => switch (kind) {
  JobKind.recruitment => K.kindRecruitment.inLang(lang),
  JobKind.result => K.kindResult.inLang(lang),
  JobKind.admitCard => K.kindAdmitCard.inLang(lang),
  JobKind.notice => K.kindNotice.inLang(lang),
};

String categoryLabel(JobCategory category, AppLang lang) => switch (category) {
  JobCategory.police => K.categoryPolice.inLang(lang),
  JobCategory.railway => K.categoryRailway.inLang(lang),
  JobCategory.banking => K.categoryBanking.inLang(lang),
  JobCategory.teaching => K.categoryTeaching.inLang(lang),
  JobCategory.medical => K.categoryMedical.inLang(lang),
  JobCategory.office => K.categoryOffice.inLang(lang),
  JobCategory.other => K.categoryOther.inLang(lang),
};

String? vacanciesLabel(int? vacancies, AppLang lang) {
  if (vacancies == null) return null;
  if (lang == AppLang.bn) return '${toBengaliDigits('$vacancies')}টি শূন্যপদ';
  return '$vacancies opening${vacancies == 1 ? '' : 's'}';
}
