import 'package:flutter/material.dart';

import '../../design_system/karmopath_theme.dart';
import '../../features/common/app_language.dart';
import 'app_runtime.dart';
import 'production_shell.dart';

/// A failed plugin/settings initialization is visible and retryable; it never
/// silently substitutes empty preferences or a fictional production feed.
class ProductionBootstrap extends StatefulWidget {
  const ProductionBootstrap({super.key, required this.createRuntime});
  final Future<AppRuntime> Function() createRuntime;
  @override
  State<ProductionBootstrap> createState() => _ProductionBootstrapState();
}

class _ProductionBootstrapState extends State<ProductionBootstrap> {
  AppRuntime? _runtime;
  bool _loading = true;
  bool _failed = false;
  int _attempt = 0;

  /// The startup failure as it happened. The headline alone cannot say which
  /// step failed (preferences, ledger, language or the notification plugin),
  /// and a device-only failure has no debugger attached, so the cause is kept
  /// and shown instead of being swallowed.
  Object? _failure;
  StackTrace? _failureStack;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final attempt = ++_attempt;
    AppRuntime? candidate;
    try {
      candidate = await widget.createRuntime();
      final language = await candidate.readLanguage();
      if (!mounted || attempt != _attempt) {
        await candidate.close();
        return;
      }
      appLanguage.value = language;
      setState(() {
        _runtime = candidate;
        _loading = false;
        _failed = false;
      });
    } catch (error, stack) {
      if (candidate != null) {
        try {
          await candidate.close();
        } catch (_) {}
      }
      if (!mounted || attempt != _attempt) return;
      // Print for logcat as well: the screen can be screenshotted, the log is
      // what a tethered device or a bug report needs.
      debugPrint('Karmopath startup failed: $error');
      debugPrintStack(stackTrace: stack);
      setState(() {
        _loading = false;
        _failed = true;
        _failure = error;
        _failureStack = stack;
      });
    }
  }

  @override
  void dispose() {
    _attempt++;
    final runtime = _runtime;
    if (runtime != null) {
      _closeQuietly(runtime);
    }
    super.dispose();
  }

  /// Short cause plus the first stack frames: enough to name the failing step
  /// without pasting an unbounded trace into the layout.
  String get _failureDetail {
    final error = _failure;
    if (error == null) return '';
    final stack = _failureStack?.toString().trimRight();
    if (stack == null || stack.isEmpty) return error.toString();
    final frames = stack.split('\n').take(12).join('\n');
    return '$error\n\n$frames';
  }

  Future<void> _closeQuietly(AppRuntime runtime) async {
    // Nothing can be rendered after disposal; the platform implementation must
    // make close best-effort and release clients/notifiers in its finally path.
    try {
      await runtime.close();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _runtime;
    if (runtime != null) return ProductionShell(runtime: runtime);
    return MaterialApp(
      title: 'Karmopath',
      theme: KarmopathTheme.light(),
      home: Scaffold(
        appBar: AppBar(title: const Text('Karmopath · কর্মপথ')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading) const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    _failed
                        ? 'অ্যাপের সংরক্ষিত সেটিংস খোলা যায়নি। আবার চেষ্টা করুন।\nCould not initialize saved settings. Please retry.'
                        : 'অ্যাপ প্রস্তুত হচ্ছে… / Preparing app…',
                    textAlign: TextAlign.center,
                  ),
                  if (_failed) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _failed = false;
                            _failure = null;
                            _failureStack = null;
                          });
                          _initialize();
                        },
                        child: const Text('আবার চেষ্টা / Retry'),
                      ),
                    ),
                    if (_failure != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              _failureDetail,
                              textAlign: TextAlign.left,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontFamily: 'monospace',
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
