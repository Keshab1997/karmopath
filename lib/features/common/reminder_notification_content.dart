import '../../contracts/job.dart';
import 'app_language.dart';
import 'strings.dart';

/// Content only; native delivery and scheduling belong to the app adapter.
class ReminderNotificationContent {
  const ReminderNotificationContent({
    required this.title,
    required this.body,
    required this.payload,
    required this.payloadVariant,
  });

  final String title;
  final String body;
  final String payload;
  final String payloadVariant;
}

/// Stable language/copy identity for native adapter reconciliation.
String reminderNotificationVariant(AppLang language) => switch (language) {
  AppLang.bn => 'bn@reminder-v1',
  AppLang.en => 'en@reminder-v1',
};

/// Builds content from the explicit language without reading global state.
ReminderNotificationContent buildReminderNotificationContent({
  required Job job,
  required AppLang language,
}) => ReminderNotificationContent(
  title: language == AppLang.bn ? job.titleBn : job.titleEn,
  body: K.reminderNotificationBody.inLang(language),
  payload: job.id,
  payloadVariant: reminderNotificationVariant(language),
);
