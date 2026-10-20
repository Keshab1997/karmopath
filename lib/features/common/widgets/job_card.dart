import 'package:flutter/material.dart';

import '../../../contracts/job.dart';
import '../../../contracts/user_preferences.dart';
import '../../../design_system/karmopath_theme.dart';
import '../app_language.dart';
import '../formatting.dart';
import '../palette.dart';
import '../strings.dart';
import 'category_circle.dart';

/// White rounded job card matching the approved v2 home design.
///
/// Only feed values are rendered; nothing is invented. The bookmark writes
/// through [UserPreferences] and reflects the stored value.
class JobCard extends StatelessWidget {
  /// Eligibility lines a card shows before pointing at the detail page. Two
  /// keeps the card scannable; the count line makes the rest visible as a gap.
  static const int maxQualifications = 2;

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
    // A feed entry can list several eligibility routes (12th, or 10th + ITI,
    // plus the cultural qualification). Showing only the first hid the rest
    // behind no signal at all, so the card shows up to two lines and says how
    // many more the detail page holds.
    final shown = job.qualifications.take(maxQualifications).toList();
    final hidden = job.qualifications.length - shown.length;

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
                if (shown.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  for (var index = 0; index < shown.length; index++)
                    _MetaLine(
                      icon: index == 0 ? Icons.school_outlined : null,
                      text: shown[index],
                      maxLines: 2,
                    ),
                  if (hidden > 0)
                    _MetaLine(
                      icon: null,
                      text: K.moreQualifications(hidden, lang),
                      hint: true,
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
      // Small text on coral needs the darkened token (AA), not brand coral.
      background = KPalette.coralStrong;
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

/// One icon-led line in the card's meta block.
///
/// [maxLines] stays 1 for single-value lines (district) and grows to 2 for the
/// eligibility routes, which are long strings a feed supplies verbatim. A null
/// [icon] keeps the same left offset, so a continuation line aligns under the
/// first one instead of shifting left.
class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.text,
    this.icon,
    this.maxLines = 1,
    this.hint = false,
  });

  final IconData? icon;
  final String text;
  final int maxLines;
  final bool hint;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 16,
            color: KarmopathTheme.ink.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 6),
        ] else
          const SizedBox(width: 22),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: hint ? FontWeight.w600 : FontWeight.w400,
              color: KarmopathTheme.ink.withValues(
                alpha: hint ? 0.62 : 0.7,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BookmarkButton extends StatefulWidget {
  const _BookmarkButton({
    required this.job,
    required this.preferences,
    required this.lang,
  });

  final Job job;
  final UserPreferences preferences;
  final AppLang lang;

  @override
  State<_BookmarkButton> createState() => _BookmarkButtonState();
}

class _BookmarkButtonState extends State<_BookmarkButton> {
  bool _busy = false;

  Future<void> _toggle(bool saved) async {
    // Rapid taps while a write is in flight are ignored, so the second tap can
    // never report a success the storage did not confirm.
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.preferences.setSaved(widget.job.id, !saved);
    } on Object {
      if (!mounted) return;
      // Storage rejected the change: the stored state is unchanged, and the
      // user is told so in their language (never reminder copy).
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              (saved ? K.removeFailed : K.saveFailed).inLang(widget.lang),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: widget.preferences.savedJobIds,
      builder: (context, savedIds, _) {
        final saved = savedIds.contains(widget.job.id);
        return IconButton(
          onPressed: _busy ? null : () => _toggle(saved),
          tooltip: saved
              ? K.unsave.inLang(widget.lang)
              : K.save.inLang(widget.lang),
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
