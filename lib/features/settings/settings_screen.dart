import 'package:flutter/material.dart';

import '../../contracts/app_actions.dart';
import '../../contracts/job_repository.dart';
import '../../contracts/user_preferences.dart';
import '../../design_system/karmopath_theme.dart';
import '../common/app_language.dart';
import '../common/deadline_clock.dart';
import '../common/reminder_intent_state.dart';
import '../common/strings.dart';

/// Profile & settings: language, about, notification info and link stubs.
///
/// `actions` is part of the frozen constructor contract and is reserved for
/// captain-owned platform links; nothing here fabricates a URL or contact.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.actions,
    this.preferences,
    this.repository,
  });

  final AppActions actions;
  final UserPreferences? preferences;
  final JobRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLang>(
      valueListenable: appLanguage,
      builder: (context, lang, _) {
        return Scaffold(
          backgroundColor: KarmopathTheme.background,
          appBar: AppBar(
            backgroundColor: KarmopathTheme.background,
            surfaceTintColor: Colors.transparent,
            title: Text(
              K.profile.inLang(lang),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: KarmopathTheme.ink,
              ),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsCard(
                  title: K.language,
                  lang: lang,
                  icon: Icons.translate,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        K.languageHint.inLang(lang),
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: KarmopathTheme.ink.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<AppLang>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          selectedBackgroundColor: KarmopathTheme.teal
                              .withValues(alpha: 0.14),
                          selectedForegroundColor: KarmopathTheme.teal,
                          foregroundColor: KarmopathTheme.ink,
                        ),
                        segments: [
                          ButtonSegment(
                            value: AppLang.bn,
                            label: Text(K.bengali.inLang(AppLang.bn)),
                          ),
                          ButtonSegment(
                            value: AppLang.en,
                            label: Text(K.english.inLang(AppLang.bn)),
                          ),
                        ],
                        selected: {lang},
                        onSelectionChanged: (selection) {
                          appLanguage.value = selection.first;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  title: K.about,
                  lang: lang,
                  icon: Icons.info_outline,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: KarmopathTheme.coral,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'ক',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  K.appNameLatin,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: KarmopathTheme.ink,
                                  ),
                                ),
                                Text(
                                  K.tagline.inLang(lang),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: KarmopathTheme.ink.withValues(
                                      alpha: 0.65,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        K.aboutBody.inLang(lang),
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: KarmopathTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        K.disclaimerBn,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.5,
                          color: KarmopathTheme.ink.withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        K.disclaimerEn,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.5,
                          color: KarmopathTheme.ink.withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        K.accountNote.inLang(lang),
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: KarmopathTheme.teal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        K.versionNote.inLang(lang),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: KarmopathTheme.ink.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  title: K.notificationInfo,
                  lang: lang,
                  icon: Icons.notifications_none_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        K.notificationInfoBody.inLang(lang),
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: KarmopathTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _StoredRemindersSummaryRow(
                        lang: lang,
                        preferences: preferences,
                        repository: repository,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final entry in <(IconData, KText)>[
                        (Icons.privacy_tip_outlined, K.privacyPolicy),
                        (Icons.gavel_outlined, K.terms),
                        (Icons.support_agent_outlined, K.developerContact),
                        (Icons.report_outlined, K.correctionChannel),
                        (Icons.shop_outlined, K.playListing),
                      ])
                        ListTile(
                          enabled: false,
                          leading: Icon(entry.$1),
                          title: Text(entry.$2.inLang(lang)),
                          subtitle: Text(K.notAvailable.inLang(lang)),
                          trailing: const Icon(Icons.lock_outline, size: 18),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.lang,
    required this.icon,
    required this.child,
  });

  final KText title;
  final AppLang lang;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: KarmopathTheme.ink.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: KarmopathTheme.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.inLang(lang),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: KarmopathTheme.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _StoredRemindersSummaryRow extends StatelessWidget {
  const _StoredRemindersSummaryRow({
    required this.lang,
    required this.preferences,
    required this.repository,
  });

  final AppLang lang;
  final UserPreferences? preferences;
  final JobRepository? repository;

  @override
  Widget build(BuildContext context) {
    final prefs = preferences;
    if (prefs == null) {
      return _buildRow(reminderIds: const <String>{}, feedState: null);
    }
    return ValueListenableBuilder<Set<String>>(
      valueListenable: prefs.reminderJobIds,
      builder: (context, reminderIds, _) {
        final repo = repository;
        if (repo == null) {
          return _buildRow(reminderIds: reminderIds, feedState: null);
        }
        return ValueListenableBuilder<JobFeedState>(
          valueListenable: repo.state,
          builder: (context, feedState, _) =>
              _buildRow(reminderIds: reminderIds, feedState: feedState),
        );
      },
    );
  }

  Widget _buildRow({
    required Set<String> reminderIds,
    required JobFeedState? feedState,
  }) {
    final countText = K.storedReminderCount(reminderIds.length, lang);
    final subtitle = storedRemindersSummarySubtitle(
      reminderIds: reminderIds,
      jobs: feedState?.feed?.jobs,
      now: DeadlineClock.now(),
      lang: lang,
    );
    return Material(
      color: KarmopathTheme.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        // Tapping navigates nowhere (captain will wire later); no persistence.
        onTap: () {},
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: KarmopathTheme.ink.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  reminderIds.isEmpty
                      ? Icons.notifications_off_outlined
                      : Icons.alarm_on_outlined,
                  size: 18,
                  color: reminderIds.isEmpty
                      ? KarmopathTheme.ink.withValues(alpha: 0.55)
                      : KarmopathTheme.teal,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      countText,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: KarmopathTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: KarmopathTheme.ink.withValues(alpha: 0.70),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
