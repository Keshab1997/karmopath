import 'package:url_launcher/url_launcher.dart';

/// Injectable boundary for opening a validated public HTTPS link in the
/// platform's external application. A false platform result is a real failure,
/// never a silent success.
typedef ExternalUriLauncher = Future<bool> Function(
  Uri uri, {
  required LaunchMode mode,
});

Future<void> launchExternalHttpsUri(
  Uri uri, {
  ExternalUriLauncher? launcher,
}) async {
  if (uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      RegExp(r'\s').hasMatch(uri.toString())) {
    throw ArgumentError.value(uri, 'uri', 'public HTTPS link required');
  }

  final open = launcher ?? _launchWithSystemHandler;
  if (!await open(uri, mode: LaunchMode.externalApplication)) {
    throw StateError('No external application opened the HTTPS link');
  }
}

Future<bool> _launchWithSystemHandler(Uri uri, {required LaunchMode mode}) =>
    launchUrl(uri, mode: mode);
