import 'package:flutter/material.dart';

import '../../contracts/job.dart';
import '../../contracts/job_repository.dart';
import '../../contracts/user_preferences.dart';
import '../../design_system/karmopath_theme.dart';
import '../common/app_language.dart';
import '../common/deadline_clock.dart';
import '../common/strings.dart';
import '../common/widgets/job_card.dart';
import '../common/widgets/state_views.dart';

/// Saved jobs resolved against the current feed.
///
/// Saved ids that disappeared from the feed are shown as unavailable instead
/// of crashing (docs/CONTRACTS.md) and can be removed.
class SavedScreen extends StatefulWidget {
  const SavedScreen({
    super.key,
    required this.repository,
    required this.preferences,
    required this.onOpenJob,
  });

  final JobRepository repository;
  final UserPreferences preferences;
  final void Function(String) onOpenJob;

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  final Set<String> _pendingRemovals = <String>{};
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

  Future<void> _remove(String jobId, AppLang lang) async {
    // Ignore repeat taps while the write is in flight: no false success.
    if (!_pendingRemovals.add(jobId)) return;
    setState(() {});
    try {
      await widget.preferences.setSaved(jobId, false);
    } on Object {
      if (!mounted) return;
      // Storage rejected the write, so the id stays saved; say so truthfully.
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(K.removeFailed.inLang(lang))));
    } finally {
      _pendingRemovals.remove(jobId);
      if (mounted) setState(() {});
    }
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
              K.savedOpportunities.inLang(lang),
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
                  valueListenable: widget.preferences.savedJobIds,
                  builder: (context, savedIds, _) {
                    final now = _ticker.now;
                    _ticker.watch(
                      deadlineWatchInstants(
                        state.feed?.jobs ?? const <Job>[],
                        now,
                      ),
                    );
                    final byId = <String, Job>{
                      for (final job in state.feed?.jobs ?? const <Job>[])
                        job.id: job,
                    };
                    final resolved =
                        savedIds.map((id) => byId[id]).whereType<Job>().toList()
                          ..sort(
                            (a, b) => b.publishedAt.compareTo(a.publishedAt),
                          );
                    final unavailable =
                        savedIds.where((id) => byId[id] == null).toList()
                          ..sort();

                    final Widget body;
                    if (state.feed == null && state.isLoading) {
                      body = LoadingView(lang: lang);
                    } else if (state.feed == null && state.lastError != null) {
                      body = MessageView(
                        lang: lang,
                        icon: Icons.cloud_off_outlined,
                        title: K.errorTitle,
                        body: K.errorBody,
                        actionLabel: K.retry,
                        onAction: widget.repository.refresh,
                        tone: KarmopathTheme.coral,
                      );
                    } else if (savedIds.isEmpty) {
                      body = MessageView(
                        lang: lang,
                        icon: Icons.bookmark_border,
                        title: K.noSavedTitle,
                        body: K.noSavedBody,
                      );
                    } else {
                      body = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                            child: Text(
                              K.savedCount(savedIds.length, lang),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: KarmopathTheme.teal,
                              ),
                            ),
                          ),
                          if (state.isOffline && state.feed != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: OfflineBanner(
                                lang: lang,
                                lastFeedUpdate: state.feed?.updatedAt,
                              ),
                            )
                          else if (state.lastError != null &&
                              state.feed != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: OfflineBanner(lang: lang, staleOnly: true),
                            ),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: widget.repository.refresh,
                              child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  28,
                                ),
                                children: [
                                  for (final job in resolved)
                                    JobCard(
                                      job: job,
                                      lang: lang,
                                      now: now,
                                      preferences: widget.preferences,
                                      onTap: () => widget.onOpenJob(job.id),
                                    ),
                                  for (final id in unavailable)
                                    UnavailableJobTile(
                                      lang: lang,
                                      jobId: id,
                                      onRemove: _pendingRemovals.contains(id)
                                          ? null
                                          : () => _remove(id, lang),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return SafeArea(
                      top: false,
                      child: _RefreshableBody(
                        onRefresh: widget.repository.refresh,
                        child: body,
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
}

/// Wraps non-scrollable states so the page keeps pull-to-refresh everywhere.
class _RefreshableBody extends StatelessWidget {
  const _RefreshableBody({required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: child is LoadingView || child is MessageView
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [child],
            )
          : child,
    );
  }
}
