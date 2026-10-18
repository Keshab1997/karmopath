import 'app_language.dart';

/// A bilingual UI string. Bengali is written first by design.
class KText {
  final String bn;
  final String en;
  const KText(this.bn, this.en);

  String inLang(AppLang lang) => lang == AppLang.bn ? bn : en;

  @override
  String toString() => '$bn / $en';
}

/// All user-visible copy used by worker B screens.
///
/// Nothing here is production data: job content always comes from the feed.
abstract final class K {
  // Product identity (docs/PRODUCT.md).
  static const appName = KText('কর্মপথ', 'Karmopath');
  static const appNameLatin = 'Karmopath';
  static const tagline = KText(
    'কোনো ডেডলাইন আর মিস নয়।',
    'Never miss a deadline.',
  );

  // Navigation / sections.
  static const home = KText('হোম', 'Home');
  static const saved = KText('সংরক্ষিত', 'Saved');
  static const calendar = KText('ক্যালেন্ডার', 'Calendar');
  static const settings = KText('সেটিংস', 'Settings');
  static const notifications = KText('নোটিফিকেশন', 'Notifications');
  static const latestOpportunities = KText(
    'সাম্প্রতিক সুযোগ',
    'Latest opportunities',
  );
  static const savedOpportunities = KText(
    'সংরক্ষিত সুযোগ',
    'Saved opportunities',
  );
  static const deadlines = KText('আবেদনের শেষ তারিখ', 'Application deadlines');
  static const searchHint = KText(
    'চাকরি, বিভাগ বা যোগ্যতা খুঁজুন',
    'Search jobs, district or qualification',
  );
  static const clearSearch = KText('সার্চ মুছুন', 'Clear search');
  static const all = KText('সব', 'All');
  static const clearFilters = KText('ফিল্টার মুছুন', 'Clear filters');

  // Hero.
  static const heroTitle = KText(
    'কোনো ডেডলাইন\nআর মিস নয়',
    'Never miss\na deadline',
  );
  static const heroSubtitle = KText(
    'পশ্চিমবঙ্গের সব চাকরির আপডেট',
    'Every WB job update',
  );

  // Job kinds.
  static const kindRecruitment = KText('নিয়োগ', 'Recruitment');
  static const kindResult = KText('ফলাফল', 'Result');
  static const kindAdmitCard = KText('অ্যাডমিট কার্ড', 'Admit card');

  // Categories.
  static const categoryPolice = KText('পুলিশ', 'Police');
  static const categoryRailway = KText('রেলওয়ে', 'Railway');
  static const categoryBanking = KText('ব্যাংকিং', 'Banking');
  static const categoryTeaching = KText('শিক্ষা', 'Teaching');
  static const categoryMedical = KText('চিকিৎসা', 'Medical');
  static const categoryOffice = KText('অফিস', 'Office');
  static const categoryOther = KText('অন্যান্য', 'Other');

  // Status / deadline.
  static const statusOpen = KText('আবেদন চলছে', 'Open');
  static const statusClosed = KText('বন্ধ', 'Closed');
  static const statusWithdrawn = KText('প্রত্যাহৃত', 'Withdrawn');
  static const statusPublished = KText('প্রকাশিত', 'Published');
  static const closingSoon = KText('শেষ হচ্ছে', 'Closing soon');
  static const deadlineUnknown = KText(
    'শেষ তারিখ ঘোষিত হয়নি',
    'Deadline not announced',
  );
  static const closedAlready = KText('আবেদনের সময় শেষ', 'Application closed');

  // Counts / labels. Bengali renders its own numerals.
  static String _num(int n, AppLang lang) {
    final raw = '$n';
    if (lang == AppLang.en) return raw;
    const digits = '০১২৩৪৫৬৭৮৯';
    return raw.split('').map((char) {
      final digit = int.tryParse(char);
      return digit == null ? char : digits[digit];
    }).join();
  }

  static String updatesCount(int n, AppLang lang) => lang == AppLang.bn
      ? '${_num(n, lang)}টি আপডেট'
      : '$n update${n == 1 ? '' : 's'}';

  static String savedCount(int n, AppLang lang) =>
      lang == AppLang.bn ? '${_num(n, lang)}টি সংরক্ষিত' : '$n saved';

  static String reminderCount(int n, AppLang lang) => lang == AppLang.bn
      ? '${_num(n, lang)}টি রিমাইন্ডার চালু'
      : '$n reminder${n == 1 ? '' : 's'}';

  // Card / list semantics.
  // Filters (batch 2).
  static const districtFilter = KText('জেলা', 'District');
  static const qualificationFilter = KText('যোগ্যতা', 'Qualification');
  static const filtersTitle = KText('ফিল্টার', 'Filters');
  static const allDistricts = KText('সব জেলা', 'All districts');
  static const allQualifications = KText('সব যোগ্যতা', 'All qualifications');
  static const done = KText('সম্পন্ন', 'Done');
  static const noDistricts = KText(
    'এই ফিডে কোনো জেলার তথ্য নেই',
    'No districts in the current feed',
  );
  static const noQualifications = KText(
    'এই ফিডে কোনো যোগ্যতার তথ্য নেই',
    'No qualifications in the current feed',
  );
  static const facetSheetHint = KText(
    'একাধিক নির্বাচন করা যায়; অন্য ফিল্টারগুলোর সঙ্গে মিলিয়ে ফলাফল দেখানো হয়।',
    'You can pick more than one; results combine with the other filters.',
  );
  static String facetCount(int n, AppLang lang, KText base) =>
      n == 0 ? base.inLang(lang) : '${base.inLang(lang)} · ${_num(n, lang)}';

  static const save = KText('সংরক্ষণ করুন', 'Save');
  static const unsave = KText('সংরক্ষণ বাতিল', 'Remove from saved');
  static const openJob = KText('বিস্তারিত দেখুন', 'View details');
  static const unavailableJob = KText(
    'এই চাকরির তথ্য আর নেই',
    'This job is no longer available',
  );
  static const unavailableHint = KText(
    'ফিড আপডেটে এই এন্ট্রিটি নেই। আপনি এটি সংরক্ষিত তালিকা থেকে সরাতে পারেন।',
    'It is no longer in the current feed. You can remove it from your saved list.',
  );
  static const remove = KText('সরান', 'Remove');

  // Saved-list write failures. Deliberately worded differently from reminder
  // errors: the stored state did not change.
  static const saveFailed = KText(
    'সংরক্ষণ করা যায়নি। আগের অবস্থা অপরিবর্তিত আছে।',
    "Couldn't save this job. Your previous state is unchanged.",
  );
  static const removeFailed = KText(
    'সংরক্ষিত তালিকা থেকে সরানো যায়নি। আগের অবস্থা অপরিবর্তিত আছে।',
    "Couldn't remove this job from your saved list. Your previous state is unchanged.",
  );

  // Loading / empty / error / offline.
  static const loading = KText('লোড হচ্ছে…', 'Loading…');
  static const noJobsTitle = KText(
    'কোনো সুযোগ পাওয়া যায়নি',
    'No opportunities yet',
  );
  static const noJobsBody = KText(
    'প্রকাশিত, যাচাই করা বিজ্ঞপ্তি এখানে দেখা যাবে। পরে আবার চেষ্টা করুন।',
    'Human-reviewed notices will appear here once published. Try again later.',
  );
  static const noMatchesTitle = KText(
    'কোনো মিল পাওয়া যায়নি',
    'Nothing matches',
  );
  static const noMatchesBody = KText(
    'সার্চ বা ফিল্টার বদলে আবার দেখুন।',
    'Try a different search or clear the filters.',
  );
  static const noSavedTitle = KText(
    'সংরক্ষিত তালিকা খালি',
    'No saved jobs yet',
  );
  static const noSavedBody = KText(
    'যেকোনো চাকরিতে বুকমার্ক চাপলে সেটি এখানে দেখা যাবে।',
    'Tap the bookmark on any job and it will appear here.',
  );
  static const noDeadlinesTitle = KText(
    'সামনের কোনো শেষ তারিখ নেই',
    'No upcoming deadlines',
  );
  static const noDeadlinesBody = KText(
    'শেষ তারিখসহ নিয়োগ প্রকাশিত হলে ক্যালেন্ডারে দেখা যাবে।',
    'Recruitments with a closing date will appear here once published.',
  );
  static const errorTitle = KText('তথ্য লোড করা যায়নি', "Couldn't load data");
  static const errorBody = KText(
    'ইন্টারনেট বা ফিডে সমস্যা হতে পারে। আবার চেষ্টা করুন।',
    'Check your connection or try again in a moment.',
  );
  static const retry = KText('আবার চেষ্টা করুন', 'Try again');
  static const offlineTitle = KText('আপনি অফলাইনে', "You're offline");
  static const offlineBody = KText(
    'সর্বশেষ সংরক্ষিত তথ্য দেখানো হচ্ছে।',
    'Showing the last saved information.',
  );
  static const staleBanner = KText(
    'ফিড হালনাগাদ হয়নি। নিচে টেনে রিফ্রেশ করুন।',
    'Feed not refreshed. Pull down to refresh.',
  );
  static String lastUpdated(String when, AppLang lang) =>
      lang == AppLang.bn ? 'সর্বশেষ হালনাগাদ: $when' : 'Last updated: $when';

  // Job detail.
  static const jobDetails = KText('চাকরির বিবরণ', 'Job details');
  static const overview = KText('সারসংক্ষেপ', 'Summary');
  static const eligibility = KText('যোগ্যতা', 'Eligibility');
  static const importantDates = KText('গুরুত্বপূর্ণ তারিখ', 'Important dates');
  static const application = KText('আবেদন প্রক্রিয়া', 'How to apply');
  static const officialLinks = KText('সরকারি সূত্র', 'Official links');
  static const vacancies = KText('শূন্যপদ', 'Vacancies');
  static const district = KText('জেলা', 'District');
  static const qualification = KText('শিক্ষাগত যোগ্যতা', 'Qualification');
  static const ageNote = KText('বয়সসীমা', 'Age limits');
  static const applicationStart = KText('আবেদন শুরু', 'Applications open');
  static const applicationEnd = KText(
    'আবেদনের শেষ তারিখ',
    'Application deadline',
  );
  static const examDate = KText('পরীক্ষার তারিখ', 'Exam date');
  static const toBeAnnounced = KText('ঘোষিত হয়নি', 'Not announced');
  static const notSpecified = KText('উল্লেখ নেই', 'Not specified');
  static const openNotice = KText(
    'মূল বিজ্ঞপ্তি খুলুন',
    'Open original notice',
  );
  static const openSource = KText('সরকারি সূত্র দেখুন', 'Open official source');
  static const applyOnline = KText('অনলাইনে আবেদন করুন', 'Apply online');
  static const linkOpenFailed = KText(
    'লিঙ্ক খোলা যায়নি',
    'Could not open the link',
  );
  static const linkUnsafe = KText(
    'এই লিঙ্কটি নিরাপদ HTTPS ঠিকানা নয়, তাই খোলা হয়নি।',
    'This link is not a safe HTTPS address, so it was not opened.',
  );
  static const lastVerified = KText('সর্বশেষ যাচাই', 'Last verified');
  static const sourceUrlLabel = KText('সূত্র', 'Source');
  static const reminderOn = KText('রিমাইন্ডার চালু', 'Reminder on');
  static const reminderOff = KText('রিমাইন্ডার দিন', 'Remind me');
  static const reminderEnabledMsg = KText(
    'ডেডলাইনের ২৪ ঘণ্টা আগে রিমাইন্ডারের অনুরোধ সংরক্ষণ করা হয়েছে। এটি শুধু সংরক্ষিত অনুরোধ—নোটিফিকেশন পাঠানো নিশ্চিত নয়।',
    'Reminder request saved for 24 hours before the deadline. This is a saved request only—no notification is confirmed.',
  );
  static const reminderPolicyHelp = KText(
    'চালু করলে ডেডলাইনের ২৪ ঘণ্টা আগে একবার রিমাইন্ডারের অনুরোধ রাখা হয়, এবং শুধু তখনই যদি ওই সময় এখনো ভবিষ্যতে থাকে। পরে চালু করলে অতিরিক্ত কোনো বার্তা আসে না।',
    'If enabled, one reminder is requested 24 hours before the deadline, and only when that time is still ahead. Enabling later does not create a catch-up alert.',
  );
  static const reminderDisabledMsg = KText(
    'রিমাইন্ডারের অনুরোধ মুছে ফেলা হয়েছে।',
    'Reminder request removed.',
  );
  static const reminderDeniedMsg = KText(
    'নোটিফিকেশনের অনুমতি পাওয়া যায়নি, তাই কোনো রিমাইন্ডার সংরক্ষণ হয়নি।',
    'Notification permission was not granted, so no reminder was saved.',
  );
  static const reminderPermissionErrorMsg = KText(
    'অনুমতির অবস্থা যাচাই করা যায়নি, তাই কোনো রিমাইন্ডার সংরক্ষণ হয়নি।',
    'Notification permission could not be checked, so no reminder was saved.',
  );
  static const reminderFailedMsg = KText(
    'রিমাইন্ডারের অনুরোধ সংরক্ষণ করা যায়নি। আগের অবস্থা অপরিবর্তিত আছে।',
    'The reminder request could not be saved. Your previous state is unchanged.',
  );
  static const reminderTooLateMsg = KText(
    'ডেডলাইনের ২৪ ঘণ্টা আগের সময় পার হয়ে গেছে, তাই নতুন রিমাইন্ডারের অনুরোধ সংরক্ষণ করা হয়নি।',
    'The 24-hour reminder time before this deadline has passed, so no new reminder request was saved.',
  );
  static const reminderClosedMsg = KText(
    'সময় শেষ হওয়ায় নতুন রিমাইন্ডার চালু করা যাবে না।',
    'This opportunity has closed; new reminders are unavailable.',
  );
  static const reminderNoDeadlineMsg = KText(
    'এই আপডেটে কোনো আবেদনের শেষ তারিখ নেই, তাই রিমাইন্ডার দেওয়া যায় না।',
    'This update has no application deadline, so reminders are unavailable.',
  );
  // Stored reminder intents. Every label states that the request is stored
  // only; none of them claims a notification was scheduled, delivered or
  // missed, because the operating system state is not visible here.
  static const reminderStored = KText('সংরক্ষিত অনুরোধ', 'Stored request');
  static const reminderRowDuePassed = KText(
    'ডেডলাইনের ২৪ ঘণ্টা আগের সময় পেরিয়ে গেছে; নোটিফিকেশন এসেছিল কিনা তা জানা যায় না।',
    'The 24-hour reminder time has passed; whether a notification appeared is unknown.',
  );
  static const reminderRowClosed = KText(
    'শেষ তারিখ পেরিয়ে গেছে; নোটিফিকেশন এসেছিল কিনা তা জানা যায় না।',
    'The deadline has passed; whether a notification appeared is unknown.',
  );
  static const reminderRowWithdrawn = KText(
    'নিয়োগটি প্রত্যাহার করা হয়েছে; সংরক্ষিত অনুরোধটি এখনো তালিকায় আছে।',
    'This recruitment was withdrawn; the stored request is still listed.',
  );
  static const reminderRowUnavailable = KText(
    'চাকরিটি এখন ফিডে নেই; সংরক্ষিত অনুরোধটি এখনো তালিকায় আছে।',
    'This job is no longer in the feed; the stored request is still listed.',
  );
  static const reminderRowNoDeadline = KText(
    'এখন কোনো শেষ তারিখ নেই; অনুরোধটি শুধু সংরক্ষিত অবস্থায় আছে।',
    'There is no deadline for this update now; the request stays stored only.',
  );
  static const closedBanner = KText(
    'আবেদনের সময় শেষ। তথ্য রেফারেন্সের জন্য রাখা হয়েছে।',
    'The application window has closed. This page is kept for reference.',
  );
  static const withdrawnBanner = KText(
    'এই নিয়োগ প্রত্যাহার করা হয়েছে। আবেদন করবেন না।',
    'This recruitment has been withdrawn. Do not apply.',
  );
  static const correction = KText('সংশোধন জানান', 'Report a correction');
  static const correctionUnavailable = KText(
    'সংশোধনের চ্যানেল এখনো চালু হয়নি।',
    'The correction channel is not available yet.',
  );
  static const correctionUnavailableHint = KText(
    'লঞ্চের আগে ডেভেলপার যোগাযোগ ও সংশোধনের ঠিকানা যুক্ত হবে; কোনো ঠিকানা বানানো হয়নি।',
    'A real developer contact and correction address will be added before launch; none is invented here.',
  );
  static const disclaimerEn =
      'Karmopath is an independent information platform. It is not affiliated '
      'with, endorsed by, or representing any government entity. Verify '
      'eligibility and dates in the original official notice before applying.';
  static const disclaimerBn =
      'কর্মপথ একটি স্বাধীন তথ্যপ্ল্যাটফর্ম। এটি কোনো সরকারি সংস্থার সঙ্গে '
      'সংযুক্ত, অনুমোদিত বা প্রতিনিধিত্বকারী নয়। আবেদনের আগে মূল সরকারি '
      'বিজ্ঞপ্তিতে যোগ্যতা ও তারিখ যাচাই করুন।';

  // Notification sheet.
  static const noRemindersTitle = KText(
    'কোনো রিমাইন্ডার চালু নেই',
    'No reminders enabled',
  );
  static const noRemindersBody = KText(
    'চাকরির পাতায় রিমাইন্ডার চালু করলে এখানে দেখা যাবে।',
    'Enable a reminder from any job page and it will appear here.',
  );
  static const reminderSheetNote = KText(
    'রিমাইন্ডার শুধু আপনি যেসব চাকরিতে চালু করেছেন সেগুলোর জন্য। কোনো পড়া না পড়া গণনা নেই।',
    'Reminders exist only for jobs you enable. There are no unread counts.',
  );
  static const reminderSheetPolicy = KText(
    'প্রতিটি চালু করা ডেডলাইনের ২৪ ঘণ্টা আগে একবার অনুরোধ রাখা হয়, যদি সেই সময় ভবিষ্যতে থাকে।',
    'Each enabled deadline gets one request 24 hours before it, when that time is still ahead.',
  );
  static const close = KText('বন্ধ করুন', 'Close');

  // Calendar.
  static const upcoming = KText('সামনের', 'Upcoming');
  static const allDeadlines = KText('সব', 'All');
  static const past = KText('পুরোনো', 'Past');
  static const calendarHint = KText(
    'শেষ তারিখের আগে রিমাইন্ডার চালু থাকলে ক্যালেন্ডারে ঘণ্টা দেখাবে।',
    'A bell marks deadlines where you enabled a reminder.',
  );

  // Settings.
  static const profile = KText('প্রোফাইল ও সেটিংস', 'Profile & settings');
  static const language = KText('ভাষা', 'Language');
  static const languageHint = KText(
    'অ্যাপের ভাষা বদলান। চাকরির তথ্য দুই ভাষাতেই থাকে।',
    'Change the app language. Job data is published in both languages.',
  );
  static const bengali = KText('বাংলা', 'Bengali');
  static const english = KText('English', 'English');
  static const about = KText('অ্যাপ সম্পর্কে', 'About');
  static const aboutBody = KText(
    'স্বাধীন, বাংলা-প্রথম চাকরির তথ্যপ্ল্যাটফর্ম। প্রতিটি এন্ট্রি মানব-যাচাই করা এবং মূল সরকারি বিজ্ঞপ্তির লিঙ্কসহ।',
    'An independent, Bengali-first job information platform. Every entry is human-reviewed and links to its original official notice.',
  );
  static const notificationInfo = KText('নোটিফিকেশন', 'Notifications');
  static const notificationInfoBody = KText(
    'রিমাইন্ডার শুধু যেসব চাকরিতে আপনি চালু করেছেন সেগুলোর জন্য। প্ল্যাটফর্মভিত্তিক সময়সূচি অ্যাপ শেলের দায়িত্ব।',
    'Reminders are opt-in per job. Platform scheduling is provided by the app shell.',
  );
  static const moreLinks = KText('আরও', 'More');
  static const privacyPolicy = KText('প্রাইভেসি পলিসি', 'Privacy policy');
  static const terms = KText('শর্তাবলি', 'Terms of use');
  static const developerContact = KText(
    'ডেভেলপার যোগাযোগ',
    'Developer contact',
  );
  static const correctionChannel = KText(
    'সংশোধনের মাধ্যম',
    'Correction channel',
  );
  static const playListing = KText('Play Store পেজ', 'Play Store listing');
  static const notAvailable = KText('এখনো চালু হয়নি', 'Not available yet');
  static const accountNote = KText(
    'এই অ্যাপে কোনো লগইন, অ্যাকাউন্ট বা ব্যক্তিগত তথ্য লাগে না।',
    'Karmopath needs no login, account or personal data.',
  );
  static const versionNote = KText(
    'সংস্করণ ও বিল্ড তথ্য অ্যাপ শেল থেকে আসবে।',
    'Version and build info come from the app shell.',
  );
}
