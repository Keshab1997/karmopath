import '../../contracts/job.dart';
import 'app_language.dart';
import 'formatting.dart';
import 'reminder_controller.dart';
import 'strings.dart';

/// What a *stored* reminder intent can truthfully say about itself right now.
///
/// A stored intent is a saved request, nothing more. The app cannot see the
/// operating system's notification state, so no label here may claim that an
/// alert was scheduled, delivered or missed. The state is derived from the
/// job's **current** fields and the current clock; a stale stored id is kept
/// as-is until the user turns it off.
enum StoredReminderState {
  /// Reminder instant is still ahead: the request is stored and still applies.
  pending,

  /// Job is open, but the 24-hour instant has passed. No catch-up alert.
  duePassed,

  /// Deadline passed or the feed reports the job closed.
  closed,

  /// The recruitment was withdrawn.
  withdrawn,

  /// The job is no longer in the feed, so its current state is unknown.
  unavailable,

  /// The job no longer carries a deadline (e.g. corrected to a result).
  noDeadline,
}

/// Classifies a stored intent. [info] is null when the job is not in the feed.
StoredReminderState storedReminderState({
  DeadlineInfo? info,
  required DateTime now,
}) {
  if (info == null) return StoredReminderState.unavailable;
  if (info.isWithdrawn) return StoredReminderState.withdrawn;
  if (info.isClosed) return StoredReminderState.closed;
  final closes = info.closesAtUtc;
  if (closes == null) return StoredReminderState.noDeadline;
  if (!now.toUtc().isBefore(reminderDueAtUtc(closes))) {
    return StoredReminderState.duePassed;
  }
  return StoredReminderState.pending;
}

/// Truthful one-line description of [state] for a stored row or panel.
///
/// Returns null for [StoredReminderState.pending]; callers show the ordinary
/// deadline label there, qualified with [K.reminderStored].
KText? storedReminderMessage(StoredReminderState state) => switch (state) {
  StoredReminderState.pending => null,
  StoredReminderState.duePassed => K.reminderRowDuePassed,
  StoredReminderState.closed => K.reminderRowClosed,
  StoredReminderState.withdrawn => K.reminderRowWithdrawn,
  StoredReminderState.unavailable => K.reminderRowUnavailable,
  StoredReminderState.noDeadline => K.reminderRowNoDeadline,
};

/// Subtitle for one row of the home reminder sheet.
///
/// A row always describes a *stored request*. Its second line states the
/// job's current situation in plain words; when the reminder is still ahead it
/// shows the ordinary deadline label qualified with [K.reminderStored], never
/// a scheduling or delivery promise.
String reminderRowSubtitle({
  required Job? job,
  required DateTime now,
  required AppLang lang,
}) {
  if (job == null) return K.reminderRowUnavailable.inLang(lang);
  final info = deadlineInfo(job, now);
  final message = storedReminderMessage(
    storedReminderState(info: info, now: now),
  );
  if (message != null) return message.inLang(lang);
  final label =
      deadlineLabel(
        info,
        job.kind,
        lang,
        endDateOnly: job.applicationEndAt == null
            ? job.applicationEndDate
            : null,
      ) ??
      kindLabel(job.kind, lang);
  return '${K.reminderStored.inLang(lang)} · $label';
}
