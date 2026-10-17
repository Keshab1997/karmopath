# Manual workflow callers
Source: Keshab1997/flutter-builder examples, v1.15.0 (resolved commit ae20ac39b0b12ea4633c93370e5e795026171f72 when installed). Release-tag references follow upstream examples; re-review upstream before changing pins.

All events are workflow_dispatch only; no push, PR or delete event runs a job automatically. Owner runs Actions → chosen workflow → Run workflow only when ready. No CI dispatched by captain or workers.

- ci.yml: formatting/analyze/test; no APK/AAB.
- widget-tests.yml: focused Flutter widget diagnostics.
- ui-screenshots.yml: web build screenshots; Flutter web support required; public artifact/image branch implications apply.
- manual-build.yml: APK/AAB artifact; signing requirements depend on selected format/configuration.
- web-preview.yml: web build and gh-pages branch write; owner must separately enable Pages. Does not change About link. Manual deployment deliberately replaces upstream automatic push behavior.
- preview-cleanup.yml: explicit manual branch-preview cleanup; main/master protected by reusable runner.
- publish-release.yml: signed Android release; draft default true, analysis/tests required, optional Play internal upload default false. Still creates tags/releases when run. Never dispatch without owner's release authorization. Release notes and Play secrets required for Play path.

No copied builder-maintenance workflows: installer-tests, smoke-test and bump-consumers belong to flutter-builder itself, not this consumer app. Call reusable workflows rather than copying their implementation, whose relative scripts belong upstream.

No secrets configured, settings changed or deployment performed. Inherit-secrets callers must never run untrusted branches with sensitive credentials. Public app source does not imply public admin drafts. No self-hosted runners here.
