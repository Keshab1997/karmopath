import '../../contracts/app_actions.dart';
import '../../contracts/job_repository.dart';
import '../../contracts/user_preferences.dart';
import '../../features/common/app_language.dart';

/// Runtime dependencies are assembled by the captain, never by feature widgets.
/// The factory must initialize preferences before returning. No plugin/global
/// configuration or production URL is embedded in this container.
class AppRuntime {
  AppRuntime({
    required this.repository,
    required this.preferences,
    required this.actions,
    required this.readLanguage,
    required this.writeLanguage,
    required this._close,
  });
  final JobRepository repository;
  final UserPreferences preferences;
  final AppActions actions;
  final Future<AppLang> Function() readLanguage;
  final Future<void> Function(AppLang language) writeLanguage;
  final Future<void> Function() _close;
  Future<void>? _closing;
  Future<void> _pendingWrites = Future<void>.value();
  Future<void> persistLanguage(AppLang language) {
    if (_closing != null) {
      return Future<void>.error(StateError('Runtime is closing'));
    }
    final write = _pendingWrites.then((_) => writeLanguage(language));
    _pendingWrites = write.then<void>((_) {}, onError: (Object _) {});
    return write;
  }

  Future<void> close() => _closing ??= _pendingWrites.then((_) => _close());
}
