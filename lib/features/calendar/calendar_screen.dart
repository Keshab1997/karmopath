import 'package:flutter/material.dart';

import '../../contracts/job.dart';
import '../../contracts/job_repository.dart';
import '../../contracts/user_preferences.dart';
import '../../design_system/karmopath_theme.dart';
import '../common/app_language.dart';
import '../common/deadline_clock.dart';
import '../common/formatting.dart';
import '../common/palette.dart';
import '../common/strings.dart';
import '../common/widgets/state_views.dart';

/// Deadline calendar grouped by IST month.
///
/// Constructor matches docs/CONTRACTS.md exactly (same arguments as Home).
/// Only jobs that actually carry a closing deadline appear; nothing is
/// inferred. The bell is a read-only indicator of reminders enabled from the
/// job page — enabling a reminder needs [AppActions], which this screen does
/// not receive, so no permission prompt is possible here.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.repository,
    required this.preferences,
    required this.onOpenJob,
  });

  final JobRepository repository;
  final UserPreferences preferences;
  final void Function(String) onOpenJob;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  bool _showAll = false;
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
              K.deadlines.inLang(lang),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: KarmopathTheme.ink,
              ),
            ),
          ),
          body: ListenableBuilder(
            listenable: _ticker,
            builder: (context, _) => ValueListenableBuilder<JobFeedState>(
              valueListenable: widget.repository.state,
              builder: (context, state, _) {
                return ValueListenableBuilder<Set<String>>(
                  valueListenable: widget.preferences.reminderJobIds,
                  builder: (context, reminderIds, _) {
                    // Expired deadlines move from Upcoming to All without a
                    // feed refresh, driven by the ticker or app resume.
                    final now = _ticker.now;
                    _ticker.watch(
                      deadlineWatchInstants(
                        state.feed?.jobs ?? const <Job>[],
                        now,
                      ),
                    );
                    return RefreshIndicator(
                      onRefresh: widget.repository.refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                        children: [
                          _ScopeFilter(
                            lang: lang,
                            showAll: _showAll,
                            onChanged: (value) =>
                                setState(() => _showAll = value),
                          ),
                          const SizedBox(height: 8),
                          if (state.isOffline && state.feed != null)
                            OfflineBanner(
                              lang: lang,
                              lastFeedUpdate: state.feed?.updatedAt,
                            )
                          else if (state.lastError != null &&
                              state.feed != null)
                            OfflineBanner(lang: lang, staleOnly: true),
                          Text(
                            K.calendarHint.inLang(lang),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: KarmopathTheme.ink.withValues(alpha: 0.62),
                            ),
                          ),
                          if (state.feed == null && state.isLoading)
                            LoadingView(lang: lang)
                          else if (state.feed == null &&
                              state.lastError != null)
                            MessageView(
                              lang: lang,
                              icon: Icons.cloud_off_outlined,
                              title: K.errorTitle,
                              body: K.errorBody,
                              actionLabel: K.retry,
                              onAction: widget.repository.refresh,
                              tone: KarmopathTheme.coral,
                            )
                          else
                            ..._entries(state, now, lang, reminderIds),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  List<Widget> _entries(
    JobFeedState state,
    DateTime now,
    AppLang lang,
    Set<String> reminderIds,
  ) {
    final jobs = (state.feed?.jobs ?? const <Job>[])
        .where((job) => effectiveClosingUtc(job) != null)
        .toList();
    final upcoming = <_CalendarEntry>[];
    final past = <_CalendarEntry>[];
    for (final job in jobs) {
      final closes = effectiveClosingUtc(job)!;
      final info = deadlineInfo(job, now);
      final entry = _CalendarEntry(job: job, closesAtUtc: closes, info: info);
      if (info.isClosed || info.isWithdrawn) {
        past.add(entry);
      } else {
        upcoming.add(entry);
      }
    }
    upcoming.sort((a, b) => a.closesAtUtc.compareTo(b.closesAtUtc));
    past.sort((a, b) => b.closesAtUtc.compareTo(a.closesAtUtc));

    final visible = _showAll
        ? <_CalendarEntry>[...upcoming, ...past]
        : upcoming;

    if (visible.isEmpty) {
      if (jobs.isEmpty) {
        return [
          MessageView(
            lang: lang,
            icon: Icons.event_available_outlined,
            title: K.noDeadlinesTitle,
            body: K.noDeadlinesBody,
          ),
        ];
      }
      return [
        MessageView(
          lang: lang,
          icon: Icons.event_busy_outlined,
          title: K.noDeadlinesTitle,
          body: K.noDeadlinesBody,
          actionLabel: K.allDeadlines,
          onAction: () => setState(() => _showAll = true),
        ),
      ];
    }

    final widgets = <Widget>[];
    String? currentMonth;
    for (final entry in visible) {
      final ist = _calendarDate(entry.job, entry.closesAtUtc);
      final month = formatMonthYear(ist, lang);
      if (month != currentMonth) {
        currentMonth = month;
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: widgets.isEmpty ? 12 : 18, bottom: 8),
            child: Text(
              month,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: KarmopathTheme.ink,
              ),
            ),
          ),
        );
      }
      widgets.add(
        _DeadlineTile(
          entry: entry,
          lang: lang,
          reminderEnabled: reminderIds.contains(entry.job.id),
          onOpen: () => widget.onOpenJob(entry.job.id),
        ),
      );
    }
    return widgets;
  }
}

class _CalendarEntry {
  const _CalendarEntry({
    required this.job,
    required this.closesAtUtc,
    required this.info,
  });

  final Job job;
  final DateTime closesAtUtc;
  final DeadlineInfo info;
}

class _ScopeFilter extends StatelessWidget {
  const _ScopeFilter({
    required this.lang,
    required this.showAll,
    required this.onChanged,
  });

  final AppLang lang;
  final bool showAll;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // Wrap instead of Row: at 2x text the two segments stack instead of
    // clipping their labels.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Segment(
          label: K.upcoming.inLang(lang),
          selected: !showAll,
          onTap: () => onChanged(false),
        ),
        _Segment(
          label: K.allDeadlines.inLang(lang),
          selected: showAll,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? KarmopathTheme.teal : Colors.white,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 96),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? KarmopathTheme.teal
                    : KarmopathTheme.ink.withValues(alpha: 0.12),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : KarmopathTheme.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeadlineTile extends StatelessWidget {
  const _DeadlineTile({
    required this.entry,
    required this.lang,
    required this.reminderEnabled,
    required this.onOpen,
  });

  final _CalendarEntry entry;
  final AppLang lang;
  final bool reminderEnabled;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final job = entry.job;
    final ist = _calendarDate(entry.job, entry.closesAtUtc);
    final closed = entry.info.isClosed || entry.info.isWithdrawn;
    final accent = closed
        ? KarmopathTheme.ink.withValues(alpha: 0.45)
        : (entry.info.closesSoon ? KPalette.coralStrong : KarmopathTheme.teal);
    final title = lang == AppLang.bn ? job.titleBn : job.titleEn;
    final label = deadlineLabel(
      entry.info,
      job.kind,
      lang,
      endDateOnly: job.applicationEndAt == null ? job.applicationEndDate : null,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: KarmopathTheme.ink.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    lang == AppLang.bn
                        ? toBengaliDigits('${ist.day}')
                        : '${ist.day}',
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
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
                          fontSize: 12,
                          color: KarmopathTheme.ink.withValues(alpha: 0.7),
                        ),
                      ),
                      if (label != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (reminderEnabled)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Tooltip(
                      message: K.reminderOn.inLang(lang),
                      child: const Icon(
                        Icons.alarm_on,
                        size: 20,
                        color: KarmopathTheme.teal,
                      ),
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

// A date-only deadline's exclusive boundary is next-day midnight; that is a
// comparison instant, not the date to print in the calendar.
DateTime _calendarDate(Job job, DateTime closesAtUtc) {
  if (job.applicationEndAt == null && job.applicationEndDate != null) {
    return DateTime.parse(job.applicationEndDate!);
  }
  return toIstWallClock(closesAtUtc);
}
