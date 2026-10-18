import 'package:flutter/material.dart';

import '../../../design_system/karmopath_theme.dart';
import '../app_language.dart';
import '../strings.dart';

/// Loading state for a cold start (no cached feed yet).
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, required this.lang, this.label = K.loading});

  final AppLang lang;
  final KText label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          Text(
            label.inLang(lang),
            textAlign: TextAlign.center,
            style: const TextStyle(color: KarmopathTheme.ink),
          ),
        ],
      ),
    );
  }
}

/// Empty, error and informational panel with an optional action.
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.lang,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.tone = KarmopathTheme.teal,
  });

  final AppLang lang;
  final IconData icon;
  final KText title;
  final KText body;
  final KText? actionLabel;
  final VoidCallback? onAction;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: tone, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            title.inLang(lang),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: KarmopathTheme.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body.inLang(lang),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: KarmopathTheme.ink.withValues(alpha: 0.7),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: KarmopathTheme.teal,
                minimumSize: const Size(48, 48),
              ),
              child: Text(actionLabel!.inLang(lang)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Offline / stale-feed banner. Never claims data is live.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    required this.lang,
    this.lastFeedUpdate,
    this.staleOnly = false,
  });

  final AppLang lang;

  /// UTC timestamp of the cached feed when known.
  final DateTime? lastFeedUpdate;

  /// True when the device is online but the last refresh failed.
  final bool staleOnly;

  @override
  Widget build(BuildContext context) {
    final updated = lastFeedUpdate;
    final subtitle = updated != null
        ? K.lastUpdated(_stamp(updated), lang)
        : (staleOnly ? K.staleBanner : K.offlineBody).inLang(lang);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1D6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 20,
            color: Color(0xFF8A5A00),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  staleOnly
                      ? K.staleBanner.inLang(lang)
                      : K.offlineTitle.inLang(lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF5B3D00),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF5B3D00),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _stamp(DateTime utc) {
    final ist = utc.toUtc().add(const Duration(hours: 5, minutes: 30));
    final hh = ist.hour % 12 == 0 ? 12 : ist.hour % 12;
    final mm = ist.minute.toString().padLeft(2, '0');
    final suffix = ist.hour < 12 ? 'AM' : 'PM';
    return '${ist.day}/${ist.month}, $hh:$mm $suffix';
  }
}

/// Status banner (closed / withdrawn) for detail and list headers.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.lang,
    required this.text,
    required this.color,
    required this.icon,
  });

  final AppLang lang;
  final KText text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text.inLang(lang),
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: KarmopathTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tile for a saved id that no longer exists in the current feed.
class UnavailableJobTile extends StatelessWidget {
  const UnavailableJobTile({
    super.key,
    required this.lang,
    required this.jobId,
    required this.onRemove,
  });

  final AppLang lang;
  final String jobId;

  /// Null while a removal write is in flight (disabled, no false success).
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KarmopathTheme.ink.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.help_outline,
                color: KarmopathTheme.ink.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  K.unavailableJob.inLang(lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: KarmopathTheme.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            K.unavailableHint.inLang(lang),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: KarmopathTheme.ink.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            jobId,
            style: TextStyle(
              fontSize: 11.5,
              fontFamily: 'monospace',
              color: KarmopathTheme.ink.withValues(alpha: 0.55),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(K.remove.inLang(lang)),
            ),
          ),
        ],
      ),
    );
  }
}
