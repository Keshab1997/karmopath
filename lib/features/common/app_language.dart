import 'package:flutter/foundation.dart';

/// Worker B UI language. Bengali is the product default; English is fallback.
///
/// Kept inside `lib/features/**` (worker B ownership) so no captain-owned
/// shared surface changes are required. The captain may later replace this
/// with a user preference owned by the app shell.
enum AppLang { bn, en }

/// Process-wide selector for the currently rendered language.
///
/// Every B screen listens to this notifier, so switching language in Settings
/// updates all screens without any shared-state file outside B ownership.
final ValueNotifier<AppLang> appLanguage = ValueNotifier<AppLang>(AppLang.bn);
