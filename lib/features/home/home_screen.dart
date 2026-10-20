import 'package:flutter/material.dart';

import '../../contracts/job.dart';
import '../../contracts/job_repository.dart';
import '../../contracts/user_preferences.dart';
import '../../design_system/karmopath_theme.dart';
import '../common/app_language.dart';
import '../common/deadline_clock.dart';
import '../common/formatting.dart';
import '../common/palette.dart';
import '../common/reminder_intent_state.dart';
import '../common/strings.dart';
import '../common/widgets/category_circle.dart';
import '../common/widgets/job_card.dart';
import '../common/widgets/state_views.dart';

/// Unique district values in the current feed, sorted for stable chips.
List<String> availableDistricts(List<Job> jobs) {
  final values = <String>{for (final job in jobs) ...job.districts};
  final list = values.toList()..sort();
  return list;
}

/// Unique qualification values in the current feed, sorted for stable chips.
List<String> availableQualifications(List<Job> jobs) {
  final values = <String>{for (final job in jobs) ...job.qualifications};
  final list = values.toList()..sort();
  return list;
}

/// Home feed: header, search, illustrated hero, category strip, filters, cards.
///
/// Contract constructor is fixed by docs/CONTRACTS.md; the captain owns routes.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.preferences,
    required this.onOpenJob,
  });

  final JobRepository repository;
  final UserPreferences preferences;
  final void Function(String) onOpenJob;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _search = TextEditingController();
  JobKind? _kind;
  JobCategory? _category;
  bool _closingSoonOnly = false;
  final Set<String> _districts = <String>{};
  final Set<String> _qualifications = <String>{};
  late final DeadlineTicker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = DeadlineTicker();
    _search.addListener(_onSearchChanged);
    widget.repository.state.addListener(_onFeedChanged);
  }

  void _onSearchChanged() => setState(() {});

  /// Selections come from the current feed, so a refresh can remove values.
  /// Stale picks are dropped instead of silently filtering everything out.
  void _onFeedChanged() {
    if (!mounted) return;
    if (_pruneSelections()) setState(() {});
  }

  bool _pruneSelections() {
    final jobs = widget.repository.state.value.feed?.jobs ?? const <Job>[];
    final districts = availableDistricts(jobs);
    final qualifications = availableQualifications(jobs);
    final beforeDistricts = _districts.length;
    final beforeQualifications = _qualifications.length;
    _districts.removeWhere((value) => !districts.contains(value));
    _qualifications.removeWhere((value) => !qualifications.contains(value));
    return beforeDistricts != _districts.length ||
        beforeQualifications != _qualifications.length;
  }

  @override
  void dispose() {
    widget.repository.state.removeListener(_onFeedChanged);
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _ticker.dispose();
    super.dispose();
  }

  bool get _hasFilters =>
      _kind != null ||
      _category != null ||
      _closingSoonOnly ||
      _districts.isNotEmpty ||
      _qualifications.isNotEmpty ||
      _search.text.trim().isNotEmpty;

  void _clearFilters() {
    setState(() {
      _kind = null;
      _category = null;
      _closingSoonOnly = false;
      _districts.clear();
      _qualifications.clear();
      _search.clear();
    });
  }

  Future<void> _openFacetSheet({
    required String facetKey,
    required AppLang lang,
  }) async {
    final jobs = widget.repository.state.value.feed?.jobs ?? const <Job>[];
    final isDistrict = facetKey == 'district';
    final options = isDistrict
        ? availableDistricts(jobs)
        : availableQualifications(jobs);
    final selected = isDistrict ? _districts : _qualifications;
    if (options.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: KarmopathTheme.background,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void toggle(String value) {
              setState(() {
                if (!selected.remove(value)) selected.add(value);
              });
              setSheetState(() {});
            }

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.72,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  // Whole sheet scrolls: at 2x text on a 320px screen the
                  // fixed rows alone can exceed the sheet height.
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (isDistrict
                                  ? K.districtFilter
                                  : K.qualificationFilter)
                              .inLang(lang),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: KarmopathTheme.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          K.facetSheetHint.inLang(lang),
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: KarmopathTheme.ink.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () {
                                  setState(selected.clear);
                                  setSheetState(() {});
                                },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          child: Text(
                            (isDistrict ? K.allDistricts : K.allQualifications)
                                .inLang(lang),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final option in options)
                              HomeFilterChip(
                                label: option,
                                selected: selected.contains(option),
                                onTap: () => toggle(option),
                                accent: KarmopathTheme.teal,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            child: Text(K.done.inLang(lang)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Job> _visibleJobs(JobFeedState state, DateTime now) {
    final jobs = state.feed?.jobs ?? const <Job>[];
    final query = _search.text.trim().toLowerCase();
    final filtered = jobs.where((job) {
      if (_kind != null && job.kind != _kind) return false;
      if (_category != null && job.category != _category) return false;
      if (_closingSoonOnly && !deadlineInfo(job, now).closesSoon) return false;
      if (_districts.isNotEmpty && !job.districts.any(_districts.contains)) {
        return false;
      }
      if (_qualifications.isNotEmpty &&
          !job.qualifications.any(_qualifications.contains)) {
        return false;
      }
      if (query.isNotEmpty) {
        final haystack = <String>[
          job.titleBn,
          job.titleEn,
          job.organization,
          ...job.districts,
          ...job.qualifications,
          categoryLabel(job.category, AppLang.bn),
          categoryLabel(job.category, AppLang.en),
        ].join(' ').toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();
    filtered.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return filtered;
  }

  void _openNotificationSheet(AppLang lang) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: KarmopathTheme.background,
      builder: (sheetContext) {
        return ValueListenableBuilder<Set<String>>(
          valueListenable: widget.preferences.reminderJobIds,
          builder: (context, reminderIds, _) {
            final feed = widget.repository.state.value.feed;
            final byId = <String, Job>{
              for (final job in feed?.jobs ?? const <Job>[]) job.id: job,
            };
            final now = _ticker.now;
            return SafeArea(
              child: ConstrainedBox(
                // Keeps the sheet usable at 2x text: content scrolls instead
                // of overflowing a fixed-height bottom sheet.
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.85,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          K.notifications.inLang(lang),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: KarmopathTheme.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          K.reminderSheetNote.inLang(lang),
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: KarmopathTheme.ink.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          K.reminderSheetPolicy.inLang(lang),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: KarmopathTheme.ink.withValues(alpha: 0.66),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (reminderIds.isEmpty)
                          MessageView(
                            lang: lang,
                            icon: Icons.notifications_none_rounded,
                            title: K.noRemindersTitle,
                            body: K.noRemindersBody,
                          )
                        else ...[
                          Text(
                            K.reminderCount(reminderIds.length, lang),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: KarmopathTheme.teal,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final id in reminderIds)
                            _ReminderRow(
                              title: byId[id] == null
                                  ? K.unavailableJob.inLang(lang)
                                  : (lang == AppLang.bn
                                        ? byId[id]!.titleBn
                                        : byId[id]!.titleEn),
                              subtitle: reminderRowSubtitle(
                                job: byId[id],
                                now: now,
                                lang: lang,
                              ),
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                widget.onOpenJob(id);
                              },
                            ),
                        ],
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            child: Text(K.close.inLang(lang)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLang>(
      valueListenable: appLanguage,
      builder: (context, lang, _) {
        return Scaffold(
          backgroundColor: KarmopathTheme.background,
          body: SafeArea(
            child: ListenableBuilder(
              listenable: _ticker,
              builder: (context, _) => ValueListenableBuilder<JobFeedState>(
                valueListenable: widget.repository.state,
                builder: (context, state, _) {
                  // Deadline UI recomputes on ticker ticks and app resume,
                  // not only when a new feed arrives.
                  final now = _ticker.now;
                  _ticker.watch(
                    deadlineWatchInstants(
                      state.feed?.jobs ?? const <Job>[],
                      now,
                    ),
                  );
                  final visible = _visibleJobs(state, now);
                  return RefreshIndicator(
                    onRefresh: widget.repository.refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 28),
                      children: [
                        _Header(
                          lang: lang,
                          onNotifications: () => _openNotificationSheet(lang),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                          child: _SearchField(
                            controller: _search,
                            lang: lang,
                            onClear: () => _search.clear(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _HeroBanner(lang: lang),
                        ),
                        const SizedBox(height: 18),
                        _CategoryStrip(
                          lang: lang,
                          selected: _category,
                          onSelect: (category) {
                            setState(() {
                              _category = _category == category
                                  ? null
                                  : category;
                            });
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: _FilterRow(
                            lang: lang,
                            kind: _kind,
                            closingSoonOnly: _closingSoonOnly,
                            hasFilters: _hasFilters,
                            districtCount: _districts.length,
                            qualificationCount: _qualifications.length,
                            districtsAvailable: availableDistricts(
                              state.feed?.jobs ?? const <Job>[],
                            ).isNotEmpty,
                            qualificationsAvailable: availableQualifications(
                              state.feed?.jobs ?? const <Job>[],
                            ).isNotEmpty,
                            onKind: (kind) {
                              setState(
                                () => _kind = _kind == kind ? null : kind,
                              );
                            },
                            onClosingSoon: () {
                              setState(
                                () => _closingSoonOnly = !_closingSoonOnly,
                              );
                            },
                            onDistrict: () => _openFacetSheet(
                              facetKey: 'district',
                              lang: lang,
                            ),
                            onQualification: () => _openFacetSheet(
                              facetKey: 'qualification',
                              lang: lang,
                            ),
                            onClear: _clearFilters,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Text(
                                  K.latestOpportunities.inLang(lang),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: KarmopathTheme.ink,
                                  ),
                                ),
                              ),
                              if (state.feed != null)
                                Text(
                                  K.opportunitiesCount(visible.length, lang),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: KarmopathTheme.teal.withValues(
                                      alpha: 0.9,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (state.isOffline && state.feed != null)
                                OfflineBanner(
                                  lang: lang,
                                  lastFeedUpdate: state.feed?.updatedAt,
                                )
                              else if (state.lastError != null &&
                                  state.feed != null)
                                OfflineBanner(lang: lang, staleOnly: true),
                              _body(state, now, lang, visible),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _body(
    JobFeedState state,
    DateTime now,
    AppLang lang,
    List<Job> visible,
  ) {
    if (state.feed == null) {
      if (state.isLoading) return LoadingView(lang: lang);
      if (state.lastError != null) {
        return MessageView(
          lang: lang,
          icon: Icons.cloud_off_outlined,
          title: K.errorTitle,
          body: K.errorBody,
          actionLabel: K.retry,
          onAction: widget.repository.refresh,
          tone: KarmopathTheme.coral,
        );
      }
      // First launch without network or feed: useful empty state, not an error.
      return MessageView(
        lang: lang,
        icon: Icons.inbox_outlined,
        title: K.noJobsTitle,
        body: K.noJobsBody,
        actionLabel: K.retry,
        onAction: widget.repository.refresh,
      );
    }
    final feed = state.feed!;
    if (feed.jobs.isEmpty) {
      return MessageView(
        lang: lang,
        icon: Icons.inbox_outlined,
        title: K.noJobsTitle,
        body: K.noJobsBody,
        actionLabel: K.retry,
        onAction: widget.repository.refresh,
      );
    }
    if (visible.isEmpty) {
      return MessageView(
        lang: lang,
        icon: Icons.search_off,
        title: K.noMatchesTitle,
        body: K.noMatchesBody,
        actionLabel: K.clearFilters,
        onAction: _clearFilters,
      );
    }
    return Column(
      children: [
        for (final job in visible)
          JobCard(
            job: job,
            lang: lang,
            now: now,
            preferences: widget.preferences,
            onTap: () => widget.onOpenJob(job.id),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.lang, required this.onNotifications});

  final AppLang lang;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  K.appNameLatin,
                  style: TextStyle(
                    fontSize: 27,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: KarmopathTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${K.appName.inLang(lang)} · ${K.tagline.inLang(lang)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: KarmopathTheme.teal.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onNotifications,
            tooltip: K.notifications.inLang(lang),
            iconSize: 26,
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: KarmopathTheme.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.lang,
    required this.onClear,
  });

  final TextEditingController controller;
  final AppLang lang;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: K.searchHint.inLang(lang),
        hintStyle: TextStyle(
          fontSize: 13.5,
          color: KarmopathTheme.ink.withValues(alpha: 0.45),
        ),
        prefixIcon: Icon(
          Icons.search,
          color: KarmopathTheme.ink.withValues(alpha: 0.5),
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: onClear,
                tooltip: K.clearSearch.inLang(lang),
                icon: const Icon(Icons.close, size: 20),
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: KarmopathTheme.ink.withValues(alpha: 0.06),
          ),
        ),
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.lang});

  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    // Height follows the text so large accessibility scales never clip the
    // Bengali headline; a 132px floor keeps the banner compact on 320px.
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: double.infinity,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 132),
          child: Stack(
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  child: Image.asset(
                    KarmopathTheme.heroAsset,
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    errorBuilder: (context, error, stack) =>
                        const ColoredBox(color: KarmopathTheme.coral),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        KPalette.coralStrong,
                        KPalette.coralStrong.withValues(alpha: 0.94),
                        KarmopathTheme.coral.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.52, 0.78],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      K.heroTitle.inLang(lang),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      K.heroSubtitle.inLang(lang),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
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

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.lang,
    required this.selected,
    required this.onSelect,
  });

  final AppLang lang;
  final JobCategory? selected;
  final ValueChanged<JobCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final category in JobCategory.values)
            _CategoryButton(
              category: category,
              label: categoryLabel(category, lang),
              selected: selected == category,
              onTap: () => onSelect(category),
            ),
        ],
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.category,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final JobCategory category;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: SizedBox(
            width: 64,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? KarmopathTheme.teal
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: CategoryCircle(category: category, size: 50),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? KarmopathTheme.teal
                        : KarmopathTheme.ink.withValues(alpha: 0.75),
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

/// Reminder line inside the notification sheet. Grows with large text instead
/// of overflowing like a fixed-height ListTile.
class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.alarm_on_outlined, color: KarmopathTheme.teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KarmopathTheme.ink,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: KarmopathTheme.ink.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.lang,
    required this.kind,
    required this.closingSoonOnly,
    required this.hasFilters,
    required this.districtCount,
    required this.qualificationCount,
    required this.districtsAvailable,
    required this.qualificationsAvailable,
    required this.onKind,
    required this.onClosingSoon,
    required this.onDistrict,
    required this.onQualification,
    required this.onClear,
  });

  final AppLang lang;
  final JobKind? kind;
  final bool closingSoonOnly;
  final bool hasFilters;
  final int districtCount;
  final int qualificationCount;
  final bool districtsAvailable;
  final bool qualificationsAvailable;
  final ValueChanged<JobKind?> onKind;
  final VoidCallback onClosingSoon;
  final VoidCallback onDistrict;
  final VoidCallback onQualification;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in <JobKind?, KText>{
            null: K.all,
            JobKind.recruitment: K.kindRecruitment,
            JobKind.result: K.kindResult,
            JobKind.admitCard: K.kindAdmitCard,
            JobKind.notice: K.kindNotice,
          }.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: HomeFilterChip(
                label: entry.value.inLang(lang),
                selected: kind == entry.key,
                onTap: () => onKind(entry.key),
              ),
            ),
          HomeFilterChip(
            label: K.closingSoon.inLang(lang),
            selected: closingSoonOnly,
            onTap: onClosingSoon,
            accent: KPalette.coralStrong,
          ),
          if (districtsAvailable)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: HomeFilterChip(
                label: K.facetCount(districtCount, lang, K.districtFilter),
                selected: districtCount > 0,
                onTap: onDistrict,
                icon: Icons.place_outlined,
              ),
            ),
          if (qualificationsAvailable)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: HomeFilterChip(
                label: K.facetCount(
                  qualificationCount,
                  lang,
                  K.qualificationFilter,
                ),
                selected: qualificationCount > 0,
                onTap: onQualification,
                icon: Icons.school_outlined,
              ),
            ),
          if (hasFilters) ...[
            const SizedBox(width: 4),
            TextButton(
              onPressed: onClear,
              child: Text(K.clearFilters.inLang(lang)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shared pill used by the filter row and the facet sheets: at least 48dp
/// tall so it stays a valid touch target at any text scale.
class HomeFilterChip extends StatelessWidget {
  const HomeFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = KarmopathTheme.teal,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : KarmopathTheme.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? accent : Colors.white,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? accent
                    : KarmopathTheme.ink.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: foreground),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: foreground,
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
