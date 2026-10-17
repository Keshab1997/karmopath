import 'package:flutter/material.dart';

import '../../contracts/job.dart';
import '../../contracts/job_repository.dart';
import '../../contracts/user_preferences.dart';
import '../../design_system/karmopath_theme.dart';
import '../common/app_language.dart';
import '../common/strings.dart';
import '../common/widgets/job_card.dart';
import '../common/widgets/state_views.dart';

/// Saved jobs resolved against the current feed.
///
/// Saved ids that disappeared from the feed are shown as unavailable instead
/// of crashing (docs/CONTRACTS.md) and can be removed.
class SavedScreen extends StatelessWidget {
  const SavedScreen({
    super.key,
    required this.repository,
    required this.preferences,
    required this.onOpenJob,
  });

  final JobRepository repository;
  final UserPreferences preferences;
  final void Function(String) onOpenJob;

  Future<void> _remove(String jobId) async {
    try {
      await preferences.setSaved(jobId, false);
    } on Object {
      // Keep the rendered list stable if local storage rejects the write.
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
          body: ValueListenableBuilder<JobFeedState>(
            valueListenable: repository.state,
            builder: (context, state, _) {
              return ValueListenableBuilder<Set<String>>(
                valueListenable: preferences.savedJobIds,
                builder: (context, savedIds, _) {
                  final now = DateTime.now();
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
                      savedIds.where((id) => byId[id] == null).toList()..sort();

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
                      onAction: repository.refresh,
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
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: OfflineBanner(
                              lang: lang,
                              lastFeedUpdate: state.feed?.updatedAt,
                            ),
                          )
                        else if (state.lastError != null && state.feed != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: OfflineBanner(lang: lang, staleOnly: true),
                          ),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: repository.refresh,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                              children: [
                                for (final job in resolved)
                                  JobCard(
                                    job: job,
                                    lang: lang,
                                    now: now,
                                    preferences: preferences,
                                    onTap: () => onOpenJob(job.id),
                                  ),
                                for (final id in unavailable)
                                  UnavailableJobTile(
                                    lang: lang,
                                    jobId: id,
                                    onRemove: () => _remove(id),
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
                      onRefresh: repository.refresh,
                      child: body,
                    ),
                  );
                },
              );
            },
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
