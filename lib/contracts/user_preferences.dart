import 'package:flutter/foundation.dart';

abstract class UserPreferences {
  ValueListenable<Set<String>> get savedJobIds;
  ValueListenable<Set<String>> get reminderJobIds;
  Future<void> setSaved(String jobId, bool saved);
  Future<void> setReminder(String jobId, bool enabled);
}
