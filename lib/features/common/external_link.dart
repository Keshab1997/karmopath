import '../../contracts/app_actions.dart';

/// Why a URL was refused before it ever reached [AppActions].
enum LinkRejection {
  /// Empty, unparseable, relative or otherwise not an absolute URL.
  malformed,

  /// Whitespace or control characters (never a real feed URL).
  unsafeCharacters,

  /// Anything other than `https`, including `http`, `javascript`, `data`, …
  notHttps,

  /// No host component.
  missingHost,

  /// Embedded `user:pass@` credentials must never be launched.
  embeddedCredentials,

  /// Fragments have no meaning for a feed link and can mask a redirect.
  fragment,
}

/// Outcome of [validateExternalLink].
class LinkCheck {
  const LinkCheck._(this.uri, this.rejection);

  const LinkCheck.valid(Uri uri) : this._(uri, null);
  const LinkCheck.invalid(LinkRejection reason) : this._(null, reason);

  /// Parsed URL when accepted; null when rejected.
  final Uri? uri;

  /// Rejection reason when refused; null when accepted.
  final LinkRejection? rejection;

  bool get isValid => uri != null && rejection == null;
}

final RegExp _forbiddenCharacters = RegExp(r'[\s\u0000-\u001F\u007F]');

/// Parses one feed-supplied link at the widget boundary.
///
/// The rules mirror docs/CONTRACTS.md (absolute HTTPS URL, nonempty host, no
/// embedded credentials) and add the fragment and whitespace checks that the
/// contract implies but the plain constructor does not enforce. Nothing is
/// normalised or repaired: an unsafe URL is refused, never rewritten.
LinkCheck validateExternalLink(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty || trimmed.length != rawUrl.length) {
    return trimmed.isEmpty
        ? const LinkCheck.invalid(LinkRejection.malformed)
        : const LinkCheck.invalid(LinkRejection.unsafeCharacters);
  }
  if (_forbiddenCharacters.hasMatch(rawUrl)) {
    return const LinkCheck.invalid(LinkRejection.unsafeCharacters);
  }
  final uri = Uri.tryParse(rawUrl);
  // `Uri.isAbsolute` is false whenever a fragment is present, so test the
  // scheme directly; fragments are rejected explicitly further down.
  if (uri == null || uri.scheme.isEmpty) {
    return const LinkCheck.invalid(LinkRejection.malformed);
  }
  if (uri.scheme != 'https') {
    return const LinkCheck.invalid(LinkRejection.notHttps);
  }
  if (uri.host.isEmpty) {
    return const LinkCheck.invalid(LinkRejection.missingHost);
  }
  if (uri.userInfo.isNotEmpty) {
    return const LinkCheck.invalid(LinkRejection.embeddedCredentials);
  }
  if (uri.hasFragment) {
    return const LinkCheck.invalid(LinkRejection.fragment);
  }
  return LinkCheck.valid(uri);
}

/// Result of asking the platform to open a link.
enum LinkOpenStatus {
  /// [AppActions.openExternal] completed without throwing.
  opened,

  /// Refused locally; [AppActions] was never called.
  invalid,

  /// The launcher threw, synchronously or asynchronously.
  failed,

  /// An identical launch is already pending; this tap was ignored.
  duplicate,
}

/// Serialises external launches per URL and turns every failure into a value.
///
/// - Validation happens before [AppActions] is touched.
/// - A pending URL cannot be launched twice by rapid taps.
/// - Synchronous *and* asynchronous launcher failures are caught, so a caller
///   never sees an uncaught exception and can report truthfully.
/// - The guard holds no widget state, so completing after a screen is disposed
///   is safe; the caller decides whether anything may still be shown.
class ExternalLinkGuard {
  final Set<String> _pending = <String>{};

  bool isPending(String rawUrl) => _pending.contains(rawUrl);

  /// Marks [rawUrl] pending and runs the launch.
  ///
  /// Returns [LinkOpenStatus.duplicate] without calling [AppActions] when the
  /// same URL is already in flight.
  Future<LinkOpenStatus> open({
    required AppActions actions,
    required String rawUrl,
  }) async {
    final check = validateExternalLink(rawUrl);
    if (!check.isValid) return LinkOpenStatus.invalid;
    if (!_pending.add(rawUrl)) return LinkOpenStatus.duplicate;
    try {
      await actions.openExternal(check.uri!);
      return LinkOpenStatus.opened;
    } on Object {
      return LinkOpenStatus.failed;
    } finally {
      _pending.remove(rawUrl);
    }
  }
}
