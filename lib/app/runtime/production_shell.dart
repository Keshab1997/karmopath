import 'dart:async';

import 'package:flutter/material.dart';

import '../../contracts/job_repository.dart';
import '../../design_system/karmopath_theme.dart';
import '../../features/common/app_language.dart';
import '../../features/common/strings.dart';
import '../../features/home/home_screen.dart';
import '../../features/saved/saved_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/job_detail/job_detail_screen.dart';
import 'app_runtime.dart';

/// Production composition, with all platform resources externally injected.
/// ProductionBootstrap owns runtime disposal. This shell never requests a
/// credential, publishes content or falls back to demo jobs.
class ProductionShell extends StatefulWidget {
  const ProductionShell({super.key, required this.runtime});
  final AppRuntime runtime;
  @override
  State<ProductionShell> createState() => _ProductionShellState();
}

class _ProductionShellState extends State<ProductionShell>
    with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appLanguage.addListener(_languageChanged);
    // Refresh is asynchronous so cache hydration can be rendered immediately.
    unawaited(_initialRefresh());
  }

  Future<void> _initialRefresh() async {
    try {
      await widget.runtime.repository.refresh();
    } catch (_) {
      _notify(
        'তথ্য আপডেট করা যায়নি। আবার চেষ্টা করুন। / Could not refresh jobs. Please retry.',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_resumed());
  }

  Future<void> _resumed() async {
    try {
      await widget.runtime.resumed();
    } catch (_) {
      _notify(
        'রিমাইন্ডারের অবস্থা যাচাই করা যায়নি। / Could not check reminders. Please retry.',
      );
    }
  }

  void _languageChanged() {
    final selected = appLanguage.value;
    unawaited(_saveLanguage(selected));
  }

  Future<void> _saveLanguage(AppLang selected) async {
    try {
      await widget.runtime.persistLanguage(selected);
    } catch (_) {
      _notify(
        'ভাষা এইবার বদলেছে, কিন্তু সংরক্ষণ হয়নি। / Language changed for this session but could not be saved.',
      );
    }
  }

  void _notify(String text) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messenger.currentState?.showSnackBar(SnackBar(content: Text(text)));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appLanguage.removeListener(_languageChanged);
    super.dispose();
  }

  void _openJob(String id) {
    _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => _LiveJobDetail(id: id, runtime: widget.runtime),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLang>(
    valueListenable: appLanguage,
    builder: (context, lang, _) => MaterialApp(
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
      title: 'Karmopath',
      theme: KarmopathTheme.light(),
      home: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            HomeScreen(
              repository: widget.runtime.repository,
              preferences: widget.runtime.preferences,
              onOpenJob: _openJob,
            ),
            SavedScreen(
              repository: widget.runtime.repository,
              preferences: widget.runtime.preferences,
              onOpenJob: _openJob,
            ),
            CalendarScreen(
              repository: widget.runtime.repository,
              preferences: widget.runtime.preferences,
              onOpenJob: _openJob,
            ),
            SettingsScreen(
              actions: widget.runtime.actions,
              preferences: widget.runtime.preferences,
              repository: widget.runtime.repository,
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) => setState(() => _tab = value),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: K.home.inLang(lang),
            ),
            NavigationDestination(
              icon: const Icon(Icons.bookmark_border),
              selectedIcon: const Icon(Icons.bookmark),
              label: K.saved.inLang(lang),
            ),
            NavigationDestination(
              icon: const Icon(Icons.calendar_month_outlined),
              label: K.calendar.inLang(lang),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              label: K.settings.inLang(lang),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LiveJobDetail extends StatelessWidget {
  const _LiveJobDetail({required this.id, required this.runtime});
  final String id;
  final AppRuntime runtime;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLang>(
    valueListenable: appLanguage,
    builder: (context, lang, _) => ValueListenableBuilder<JobFeedState>(
      valueListenable: runtime.repository.state,
      builder: (context, state, _) {
        final matches = state.feed?.jobs.where((job) => job.id == id);
        if (matches == null || matches.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text(K.jobDetails.inLang(lang))),
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.feed == null
                            ? (lang == AppLang.bn
                                  ? 'তথ্য এখন লোড করা যায়নি।'
                                  : 'Job information is not loaded.')
                            : K.unavailableJob.inLang(lang),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      if (state.isLoading)
                        const CircularProgressIndicator()
                      else
                        FilledButton(
                          onPressed: runtime.repository.refresh,
                          child: Text(K.retry.inLang(lang)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        final stale = state.isOffline || state.lastError != null;
        return Column(
          children: [
            if (stale)
              Material(
                color: const Color(0xFFFFF1D6),
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        lang == AppLang.bn
                            ? 'সংরক্ষিত তথ্য দেখছেন। আবেদন করার আগে মূল বিজ্ঞপ্তি যাচাই করুন।'
                            : 'Showing saved information. Verify the original notice before applying.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: JobDetailScreen(
                job: matches.first,
                preferences: runtime.preferences,
                actions: runtime.actions,
              ),
            ),
          ],
        );
      },
    ),
  );
}
