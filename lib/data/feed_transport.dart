/// Boundary for fetching the read-only public job feed.
///
/// The captain supplies the concrete HTTP adapter under `lib/app`; data-layer
/// code only ever depends on this interface so tests can inject a fake. A
/// transport failure (network error, HTTP error, timeout) is reported by
/// throwing; [CachedJobRepository] turns every failure into user-safe state
/// and never lets a broken payload replace the last known good feed.
abstract class FeedTransport {
  /// Returns the raw JSON document as text.
  ///
  /// The repository is responsible for strict validation before the document
  /// is used or cached; a transport must not pre-approve content.
  Future<String> fetch();
}
