/// Holds the latest validated job tap until navigation is ready.
///
/// This is an in-memory intent handoff, not a delivery receipt. Listeners are
/// notified only when a valid tap is accepted or a pending tap is consumed.
class ReminderTapIntentQueue {
  static final _invalidJobIdCharacter = RegExp(r'[^a-z0-9-]');

  final _listeners = <void Function()>[];
  String? _pendingJobId;

  bool get hasPending => _pendingJobId != null;

  String? get pendingJobId => _pendingJobId;

  void addListener(void Function() listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

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
    _notifyListeners();
    return true;
  }

  /// Retains the intent until ready, then returns and clears it exactly once.
  String? consume({required bool navigationReady}) {
    if (!navigationReady) return null;
    final jobId = _pendingJobId;
    if (jobId == null) return null;
    _pendingJobId = null;
    _notifyListeners();
    return jobId;
  }

  void clear() {
    if (_pendingJobId == null) return;
    _pendingJobId = null;
    _notifyListeners();
  }

  void _notifyListeners() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }
}
