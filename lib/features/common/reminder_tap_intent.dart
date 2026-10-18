/// Holds the latest validated job tap until navigation is ready.
///
/// This is an in-memory intent handoff, not a delivery receipt.
class ReminderTapIntentQueue {
  static final _invalidJobIdCharacter = RegExp(r'[^a-z0-9-]');

  String? _pendingJobId;

  bool get hasPending => _pendingJobId != null;

  String? get pendingJobId => _pendingJobId;

  /// Accepts only full contract-shaped slugs, without normalization.
  /// Invalid candidates leave any earlier pending intent unchanged.
  bool accept(String? candidateJobId) {
    if (candidateJobId == null ||
        candidateJobId.isEmpty ||
        candidateJobId.length > 100 ||
        _invalidJobIdCharacter.hasMatch(candidateJobId)) {
      return false;
    }
    _pendingJobId = candidateJobId;
    return true;
  }

  /// Retains the intent until ready, then returns and clears it exactly once.
  String? consume({required bool navigationReady}) {
    if (!navigationReady) return null;
    final jobId = _pendingJobId;
    _pendingJobId = null;
    return jobId;
  }

  void clear() {
    _pendingJobId = null;
  }
}
