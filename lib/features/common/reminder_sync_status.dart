import 'package:flutter/material.dart';

import 'app_language.dart';
import 'strings.dart';

enum ReminderSyncUiPhase { idle, syncing, failed }

/// Displays reconciliation status only; the caller owns runtime work and retry.
class ReminderSyncStatusBanner extends StatelessWidget {
  const ReminderSyncStatusBanner({
    super.key,
    required this.phase,
    required this.language,
    required this.onRetry,
  });

  final ReminderSyncUiPhase phase;
  final AppLang language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (phase == ReminderSyncUiPhase.idle) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isSyncing = phase == ReminderSyncUiPhase.syncing;
    final message = (isSyncing ? K.reminderSyncChecking : K.reminderSyncFailed)
        .inLang(language);

    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Announce the status once, including the indeterminate progress.
            // Keep retry outside this node so it remains a separate action.
            Semantics(
              container: true,
              liveRegion: true,
              label: message,
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isSyncing) ...[
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!isSyncing) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onRetry,
                child: Text(K.retry.inLang(language)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
