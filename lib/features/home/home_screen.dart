import 'package:flutter/material.dart';

import '../../contracts/job.dart';
import '../../contracts/job_repository.dart';
import '../../contracts/user_preferences.dart';
import '../../design_system/karmopath_theme.dart';
import '../common/app_language.dart';
import '../common/formatting.dart';
import '../common/strings.dart';
import '../common/widgets/category_circle.dart';
import '../common/widgets/job_card.dart';
import '../common/widgets/state_views.dart';

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

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
  }

  void _onSearchChanged() => setState(() {});

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  bool get _hasFilters =>
      _kind != null ||
      _category != null ||
      _closingSoonOnly ||
      _search.text.trim().isNotEmpty;

  void _clearFilters() {
    setState(() {
      _kind = null;
      _category = null;
      _closingSoonOnly = false;
      _search.clear();
    });
  }

  List<Job> _visibleJobs(JobFeedState state, DateTime now) {
    final jobs = state.feed?.jobs ?? const <Job>[];
    final query = _search.text.trim().toLowerCase();
    final filtered = jobs.where((job) {
      if (_kind != null && job.kind != _kind) return false;
      if (_category != null && job.category != _category) return false;
      if (_closingSoonOnly && !deadlineInfo(job, now).closesSoon) return false;
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
            final now = DateTime.now();
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
                    const SizedBox(height: 12),
                    if (reminderIds.isEmpty)
                      MessageView(
                        lang: lang,
                        icon: Icons.notifications_none_rounded,
                        title: K.noRemindersTitle,
                        body: K.noRemindersBody,
                      )
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
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
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.alarm_on_outlined,
                                  color: KarmopathTheme.teal,
                                ),
                                title: Text(
                                  byId[id] == null
                                      ? K.unavailableJob.inLang(lang)
                                      : (lang == AppLang.bn
                                            ? byId[id]!.titleBn
                                            : byId[id]!.titleEn),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: byId[id] == null
                                    ? null
                                    : Text(
                                        deadlineLabel(
                                              deadlineInfo(byId[id]!, now),
                                              byId[id]!.kind,
                                              lang,
                                              endDateOnly:
                                                  byId[id]!.applicationEndAt ==
                                                      null
                                                  ? byId[id]!.applicationEndDate
                                                  : null,
                                            ) ??
                                            kindLabel(byId[id]!.kind, lang),
                                      ),
                                onTap: () {
                                  Navigator.of(sheetContext).pop();
                                  widget.onOpenJob(id);
                                },
                              ),
                          ],
                        ),
                      ),
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
            child: ValueListenableBuilder<JobFeedState>(
              valueListenable: widget.repository.state,
              builder: (context, state, _) {
                final now = DateTime.now();
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
                            _category = _category == category ? null : category;
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
                          onKind: (kind) {
                            setState(() => _kind = _kind == kind ? null : kind);
                          },
                          onClosingSoon: () {
                            setState(
                              () => _closingSoonOnly = !_closingSoonOnly,
                            );
                          },
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
                                K.updatesCount(visible.length, lang),
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
                        KarmopathTheme.coral,
                        KarmopathTheme.coral.withValues(alpha: 0.94),
                        KarmopathTheme.coral.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.52, 0.92],
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

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.lang,
    required this.kind,
    required this.closingSoonOnly,
    required this.hasFilters,
    required this.onKind,
    required this.onClosingSoon,
    required this.onClear,
  });

  final AppLang lang;
  final JobKind? kind;
  final bool closingSoonOnly;
  final bool hasFilters;
  final ValueChanged<JobKind?> onKind;
  final VoidCallback onClosingSoon;
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
          }.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Chip(
                label: entry.value.inLang(lang),
                selected: kind == entry.key,
                onTap: () => onKind(entry.key),
              ),
            ),
          _Chip(
            label: K.closingSoon.inLang(lang),
            selected: closingSoonOnly,
            onTap: onClosingSoon,
            accent: KarmopathTheme.coral,
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

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = KarmopathTheme.teal,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? accent : Colors.white,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? accent
                    : KarmopathTheme.ink.withValues(alpha: 0.12),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : KarmopathTheme.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
