import 'package:flutter/material.dart';

import '../../../contracts/job.dart';
import '../../../contracts/user_preferences.dart';
import '../../../design_system/karmopath_theme.dart';
import '../app_language.dart';
import '../formatting.dart';
import '../strings.dart';
import 'category_circle.dart';

/// White rounded job card matching the approved v2 home design.
///
/// Only feed values are rendered; nothing is invented. The bookmark writes
/// through [UserPreferences] and reflects the stored value.
class JobCard extends StatelessWidget {
  const JobCard({
    super.key,
    required this.job,
    required this.lang,
    required this.now,
    required this.preferences,
    required this.onTap,
  });

  final Job job;
  final AppLang lang;
  final DateTime now;
  final UserPreferences preferences;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final info = deadlineInfo(job, now);
    final status = deadlineLabel(
      info,
      job.kind,
      lang,
      endDateOnly: job.applicationEndAt == null ? job.applicationEndDate : null,
    );
    final urgent = info.closesSoon;
    final title = lang == AppLang.bn ? job.titleBn : job.titleEn;
    final districtText = job.districts.join(', ');
    final qualificationText = job.qualifications.isEmpty
        ? null
        : job.qualifications.first;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: KarmopathTheme.ink.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CategoryCircle(category: job.category),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (status != null) ...[
                            _StatusPill(
                              text: status,
                              urgent: urgent,
                              closed: info.isClosed || info.isWithdrawn,
                            ),
                            const SizedBox(height: 6),
                          ],
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                              color: KarmopathTheme.ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            job.organization,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: KarmopathTheme.ink.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _BookmarkButton(
                      job: job,
                      preferences: preferences,
                      lang: lang,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _MetaLine(icon: Icons.place_outlined, text: districtText),
                if (qualificationText != null) ...[
                  const SizedBox(height: 4),
                  _MetaLine(
                    icon: Icons.school_outlined,
                    text: qualificationText,
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 10, right: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          postedLabel(job.publishedAt, now, lang),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: KarmopathTheme.ink.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        kindLabel(job.kind, lang),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: KarmopathTheme.teal,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.text,
    required this.urgent,
    required this.closed,
  });

  final String text;
  final bool urgent;
  final bool closed;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    if (closed) {
      background = KarmopathTheme.ink.withValues(alpha: 0.08);
      foreground = KarmopathTheme.ink.withValues(alpha: 0.65);
    } else if (urgent) {
      background = KarmopathTheme.coral;
      foreground = Colors.white;
    } else {
      background = KarmopathTheme.teal.withValues(alpha: 0.10);
      foreground = KarmopathTheme.teal;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: KarmopathTheme.ink.withValues(alpha: 0.5)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: KarmopathTheme.ink.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

class _BookmarkButton extends StatelessWidget {
  const _BookmarkButton({
    required this.job,
    required this.preferences,
    required this.lang,
  });

  final Job job;
  final UserPreferences preferences;
  final AppLang lang;

  Future<void> _toggle(bool saved) async {
    try {
      await preferences.setSaved(job.id, !saved);
    } on Object {
      // Preferences storage failed: keep the previously rendered state.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: preferences.savedJobIds,
      builder: (context, savedIds, _) {
        final saved = savedIds.contains(job.id);
        return IconButton(
          onPressed: () => _toggle(saved),
          tooltip: saved ? K.unsave.inLang(lang) : K.save.inLang(lang),
          icon: Icon(
            saved ? Icons.bookmark : Icons.bookmark_border,
            color: saved
                ? KarmopathTheme.teal
                : KarmopathTheme.ink.withValues(alpha: 0.55),
          ),
        );
      },
    );
  }
}
