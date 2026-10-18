# Batch 7 — concrete plugin wiring, reboot reconciliation and native activation (captain-owned)

## Starting point
Batch 6 (apply orchestrator, surface badges, publish checklist) squash-integrated as `574f7c0` on top of `4ca4156`. Immutable base: `574f7c0`. Captain verified 452 Flutter + 60 Python + 34 Node pass, analyzer clean. No build/release/publication.

**Batch 7 is captain-owned:** select `flutter_local_notifications` (or equivalent) with Android 13+ permission handling, wire `ReminderStateStore` + `ReminderApplier` + concrete `ReminderPlatform` in `lib/app/**` composition, add startup reconciliation against OS pending list, boot-receiver reschedule, language/variant change trigger, and finally-safe `SharedPreferences`/`Cache`/`HttpClient` init with retry. Keep web demo isolated. Only after explicit feed URL approval, activate native entrypoint and request release checks (policy/privacy/ads/testers). No keys/payment needed until owner provides them.

No parallel worker assignment for Batch 7 — captain integrates directly. Future worker batches will resume on `lib/features` polish and feed content once plugin wiring is proven on device.

