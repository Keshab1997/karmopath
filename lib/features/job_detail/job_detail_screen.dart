import 'package:flutter/material.dart';

import '../../contracts/app_actions.dart';
import '../../contracts/job.dart';
import '../../contracts/user_preferences.dart';
import '../../design_system/karmopath_theme.dart';
import '../common/app_language.dart';
import '../common/deadline_clock.dart';
import '../common/formatting.dart';
import '../common/palette.dart';
import '../common/reminder_controller.dart';
import '../common/strings.dart';
import '../common/widgets/category_circle.dart';
import '../common/widgets/state_views.dart';

/// Full job detail with structured sections, official links and reminder opt-in.
///
/// Contract constructor is fixed by docs/CONTRACTS.md.
class JobDetailScreen extends StatefulWidget {
  const JobDetailScreen({
    super.key,
    required this.job,
    required this.preferences,
    required this.actions,
  });

  final Job job;
  final UserPreferences preferences;
  final AppActions actions;

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  bool _reminderBusy = false;
  bool _saveBusy = false;
  late final DeadlineTicker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = DeadlineTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Job get job => widget.job;

  void _snack(KText message, AppLang lang) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message.inLang(lang))));
  }

  Future<void> _open(String rawUrl, AppLang lang) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      _snack(K.linkOpenFailed, lang);
      return;
    }
    try {
      await widget.actions.openExternal(uri);
    } on Object {
      _snack(K.linkOpenFailed, lang);
    }
  }

  Future<void> _toggleSaved(bool saved, AppLang lang) async {
    // One write at a time: a rapid second tap cannot show a success the
    // storage never confirmed.
    if (_saveBusy) return;
    setState(() => _saveBusy = true);
    try {
      await widget.preferences.setSaved(job.id, !saved);
    } on Object {
      // Saving error, not a reminder error; stored state is unchanged.
      if (mounted) _snack(saved ? K.removeFailed : K.saveFailed, lang);
    } finally {
      if (mounted) setState(() => _saveBusy = false);
    }
  }

  Future<void> _toggleReminder(bool enabled, AppLang lang) async {
    setState(() => _reminderBusy = true);
    final outcome = await setReminderIntent(
      preferences: widget.preferences,
      actions: widget.actions,
      jobId: job.id,
      enable: !enabled,
      deadline: deadlineInfo(job, DeadlineClock.now()),
      // Re-checked after the permission dialog returns: it may outlive the
      // deadline, and no enable intent may be written for a closed job.
      deadlineAt: (now) => deadlineInfo(job, now),
      now: DeadlineClock.now,
    );
    if (!mounted) return;
    setState(() => _reminderBusy = false);
    _snack(reminderOutcomeMessage(outcome), lang);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLang>(
      valueListenable: appLanguage,
      builder: (context, lang, _) => ListenableBuilder(
        listenable: _ticker,
        builder: (context, _) {
          final now = _ticker.now;
          _ticker.watch(deadlineWatchInstants([job], now));
          final info = deadlineInfo(job, now);
          final title = lang == AppLang.bn ? job.titleBn : job.titleEn;
          final summary = lang == AppLang.bn ? job.summaryBn : job.summaryEn;
          final howToApply = lang == AppLang.bn
              ? job.howToApplyBn
              : job.howToApplyEn;
          final ageNote = lang == AppLang.bn ? job.ageNoteBn : job.ageNoteEn;
          final closedForReminder = info.isClosed || info.isWithdrawn;
          final hasDeadline = info.hasDeadline;

          return Scaffold(
            backgroundColor: KarmopathTheme.background,
            appBar: AppBar(
              backgroundColor: KarmopathTheme.background,
              surfaceTintColor: Colors.transparent,
              title: Text(
                K.jobDetails.inLang(lang),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: KarmopathTheme.ink,
                ),
              ),
              actions: [
                ValueListenableBuilder<Set<String>>(
                  valueListenable: widget.preferences.savedJobIds,
                  builder: (context, savedIds, _) {
                    final saved = savedIds.contains(job.id);
                    return IconButton(
                      onPressed: _saveBusy
                          ? null
                          : () => _toggleSaved(saved, lang),
                      tooltip: saved
                          ? K.unsave.inLang(lang)
                          : K.save.inLang(lang),
                      icon: Icon(
                        saved ? Icons.bookmark : Icons.bookmark_border,
                        color: saved ? KarmopathTheme.teal : KarmopathTheme.ink,
                      ),
                    );
                  },
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                if (info.isWithdrawn)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: StatusBanner(
                      lang: lang,
                      text: K.withdrawnBanner,
                      color: const Color(0xFFB42318),
                      icon: Icons.block,
                    ),
                  )
                else if (info.isClosed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: StatusBanner(
                      lang: lang,
                      text: K.closedBanner,
                      color: const Color(0xFF8A5A00),
                      icon: Icons.event_busy,
                    ),
                  ),
                _Headline(job: job, lang: lang, info: info, title: title),
                const SizedBox(height: 16),
                _ActionPanel(
                  job: job,
                  lang: lang,
                  preferences: widget.preferences,
                  busy: _reminderBusy,
                  closedForReminder: closedForReminder,
                  hasDeadline: hasDeadline,
                  onReminder: _toggleReminder,
                ),
                const SizedBox(height: 16),
                _Section(
                  title: K.overview,
                  lang: lang,
                  icon: Icons.notes,
                  child: Text(
                    summary,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.55,
                      color: KarmopathTheme.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: K.eligibility,
                  lang: lang,
                  icon: Icons.verified_user_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LabelledList(
                        label: K.qualification,
                        lang: lang,
                        values: job.qualifications,
                      ),
                      const SizedBox(height: 10),
                      _FactRow(
                        icon: Icons.place_outlined,
                        label: K.district,
                        value: job.districts.join(', '),
                      ),
                      if (ageNote != null && ageNote.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _FactRow(
                          icon: Icons.cake_outlined,
                          label: K.ageNote,
                          value: ageNote,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: K.importantDates,
                  lang: lang,
                  icon: Icons.event_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FactRow(
                        icon: Icons.play_circle_outline,
                        label: K.applicationStart,
                        value: job.applicationStartDate == null
                            ? K.notSpecified.inLang(lang)
                            : formatDateOnly(job.applicationStartDate!, lang),
                      ),
                      const SizedBox(height: 8),
                      _FactRow(
                        icon: Icons.event_busy,
                        label: K.applicationEnd,
                        value: _deadlineText(job, info, lang),
                      ),
                      if (job.examDate != null) ...[
                        const SizedBox(height: 8),
                        _FactRow(
                          icon: Icons.edit_calendar_outlined,
                          label: K.examDate,
                          value: formatDateOnly(job.examDate!, lang),
                        ),
                      ],
                    ],
                  ),
                ),
                if (howToApply.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _Section(
                    title: K.application,
                    lang: lang,
                    icon: Icons.task_alt,
                    child: Text(
                      howToApply,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.55,
                        color: KarmopathTheme.ink,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _OfficialLinks(
                  job: job,
                  lang: lang,
                  onOpen: (url) => _open(url, lang),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: K.lastVerified,
                  lang: lang,
                  icon: Icons.verified_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatInstant(job.reviewedAt, lang),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: KarmopathTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        K.sourceUrlLabel.inLang(lang),
                        style: TextStyle(
                          fontSize: 12,
                          color: KarmopathTheme.ink.withValues(alpha: 0.6),
                        ),
                      ),
                      Text(
                        Uri.tryParse(job.sourceUrl)?.host ?? job.sourceUrl,
                        style: TextStyle(
                          fontSize: 12,
                          color: KarmopathTheme.teal.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: K.correction,
                  lang: lang,
                  icon: Icons.report_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.lock_outline, size: 18),
                        label: Text(
                          '${K.correction.inLang(lang)} · ${K.notAvailable.inLang(lang)}',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        K.correctionUnavailable.inLang(lang),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: KarmopathTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        K.correctionUnavailableHint.inLang(lang),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: KarmopathTheme.ink.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Disclaimer(lang: lang),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _deadlineText(Job job, DeadlineInfo info, AppLang lang) {
  final closes = info.closesAtUtc;
  if (closes != null && job.applicationEndAt != null) {
    return formatInstant(closes, lang);
  }
  if (job.applicationEndDate != null) {
    return formatDateOnly(job.applicationEndDate!, lang);
  }
  return K.deadlineUnknown.inLang(lang);
}

class _Headline extends StatelessWidget {
  const _Headline({
    required this.job,
    required this.lang,
    required this.info,
    required this.title,
  });

  final Job job;
  final AppLang lang;
  final DeadlineInfo info;
  final String title;

  @override
  Widget build(BuildContext context) {
    final status = deadlineLabel(
      info,
      job.kind,
      lang,
      endDateOnly: job.applicationEndAt == null ? job.applicationEndDate : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CategoryCircle(category: job.category, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _Pill(
                        text: kindLabel(job.kind, lang),
                        background: KarmopathTheme.teal.withValues(alpha: 0.12),
                        foreground: KarmopathTheme.teal,
                      ),
                      _Pill(
                        text: categoryLabel(job.category, lang),
                        background: CategoryVisual.backgroundFor(job.category),
                        foreground: CategoryVisual.foregroundFor(job.category),
                      ),
                      if (status != null)
                        _Pill(
                          text: status,
                          background: info.closesSoon
                              ? KPalette.coralStrong
                              : KarmopathTheme.ink.withValues(alpha: 0.08),
                          foreground: info.closesSoon
                              ? Colors.white
                              : KarmopathTheme.ink.withValues(alpha: 0.75),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 21,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: KarmopathTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    job.organization,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: KarmopathTheme.ink.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final district in job.districts)
              _Pill(
                text: district,
                icon: Icons.place_outlined,
                background: Colors.white,
                foreground: KarmopathTheme.ink.withValues(alpha: 0.8),
              ),
          ],
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String text;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.job,
    required this.lang,
    required this.preferences,
    required this.busy,
    required this.closedForReminder,
    required this.hasDeadline,
    required this.onReminder,
  });

  final Job job;
  final AppLang lang;
  final UserPreferences preferences;
  final bool busy;
  final bool closedForReminder;
  final bool hasDeadline;
  final Future<void> Function(bool enabled, AppLang lang) onReminder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: preferences.reminderJobIds,
      builder: (context, reminderIds, _) {
        final enabled = reminderIds.contains(job.id);
        // An existing intent can always be switched off; enabling needs a
        // supported deadline that has not passed.
        final blocked =
            busy || (!enabled && (closedForReminder || !hasDeadline));
        final String? unavailableText = enabled
            ? null
            : (!hasDeadline
                  ? K.reminderNoDeadlineMsg.inLang(lang)
                  : (closedForReminder
                        ? K.reminderClosedMsg.inLang(lang)
                        : null));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: blocked ? null : () => onReminder(enabled, lang),
              style: FilledButton.styleFrom(
                backgroundColor: enabled
                    ? KarmopathTheme.teal.withValues(alpha: 0.14)
                    : KarmopathTheme.teal,
                foregroundColor: enabled ? KarmopathTheme.teal : Colors.white,
                minimumSize: const Size(48, 50),
              ),
              icon: Icon(
                enabled ? Icons.alarm_on : Icons.alarm_add_outlined,
                size: 20,
              ),
              label: Text(
                enabled
                    ? K.reminderOn.inLang(lang)
                    : K.reminderOff.inLang(lang),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (unavailableText != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  unavailableText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: KarmopathTheme.ink.withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
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
            children: [
              Icon(icon, size: 18, color: KarmopathTheme.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.inLang(lang),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
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

class _LabelledList extends StatelessWidget {
  const _LabelledList({
    required this.label,
    required this.lang,
    required this.values,
  });

  final KText label;
  final AppLang lang;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.inLang(lang),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: KarmopathTheme.ink.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 4),
        if (values.isEmpty)
          Text(
            K.notSpecified.inLang(lang),
            style: const TextStyle(fontSize: 14, color: KarmopathTheme.ink),
          )
        else
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: KarmopathTheme.teal,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: KarmopathTheme.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final KText label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: KarmopathTheme.ink.withValues(alpha: 0.5)),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: KarmopathTheme.ink,
              ),
              children: [
                TextSpan(
                  text: '${label.inLang(appLanguage.value)}: ',
                  style: TextStyle(
                    color: KarmopathTheme.ink.withValues(alpha: 0.6),
                  ),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OfficialLinks extends StatelessWidget {
  const _OfficialLinks({
    required this.job,
    required this.lang,
    required this.onOpen,
  });

  final Job job;
  final AppLang lang;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: K.officialLinks,
      lang: lang,
      icon: Icons.link,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () => onOpen(job.noticeUrl),
            style: FilledButton.styleFrom(
              backgroundColor: KPalette.coralStrong,
              minimumSize: const Size(48, 48),
            ),
            icon: const Icon(Icons.description_outlined, size: 20),
            label: Text(K.openNotice.inLang(lang)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => onOpen(job.sourceUrl),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(K.openSource.inLang(lang)),
          ),
          if (job.applyUrl != null) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => onOpen(job.applyUrl!),
              style: FilledButton.styleFrom(
                backgroundColor: KarmopathTheme.teal,
                minimumSize: const Size(48, 48),
              ),
              icon: const Icon(Icons.arrow_outward, size: 20),
              label: Text(K.applyOnline.inLang(lang)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer({required this.lang});

  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KarmopathTheme.ink.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: KarmopathTheme.ink.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  K.about.inLang(lang),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: KarmopathTheme.ink.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
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
        ],
      ),
    );
  }
}
