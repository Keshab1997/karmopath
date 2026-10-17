/// Boundary for the last-known-good copy of the public feed.
///
/// The captain supplies the concrete file/preferences-backed adapter under
/// `lib/app`. The repository only writes a document here **after** the whole
/// document has passed contract validation, so whatever is stored can be
/// treated as previously valid rather than as trusted input.
abstract class FeedCache {
  /// Returns the raw JSON text written by [write], or `null` when nothing has
  /// been stored yet. Throwing is allowed; the repository treats a read
  /// failure exactly like a damaged cache and recovers from the network.
  Future<String?> read();

  /// Replaces the cached document with [raw].
  ///
  /// The repository only calls this with a fully validated payload. Throwing
  /// leaves the previous cached document untouched.
  Future<void> write(String raw);
}
