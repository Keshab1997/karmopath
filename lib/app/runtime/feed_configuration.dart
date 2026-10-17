/// No URL is guessed: production deployment must supply a reviewed public feed.
class FeedConfiguration {
  FeedConfiguration(String raw) : uri = _parse(raw);
  final Uri uri;
  static Uri _parse(String raw) {
    final value = raw.trim();
    final uri = Uri.tryParse(value);
    if (value.isEmpty ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        RegExp(r'\s').hasMatch(value)) {
      throw const FormatException(
        'A public HTTPS feed URL without credentials or fragment is required.',
      );
    }
    return uri;
  }
}
