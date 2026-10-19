# Manual workflow callers
Source: Keshab1997/flutter-builder examples, v1.15.0 (resolved commit ae20ac39b0b12ea4633c93370e5e795026171f72 when installed). Release-tag references follow upstream examples; re-review upstream before changing pins.

All workflows are manual (`workflow_dispatch`) except `publish-notice.yml`, which runs on an `issues: labeled` event. No push, PR or delete event runs a job automatically. Owner runs Actions → chosen workflow → Run workflow only when ready. No CI dispatched by captain or workers.

- `publish-notice.yml`: runs when a `notice-review` issue receives the `approve-notice` label. Re-checks the link against `ops/notice_sources.json`, appends one notice-only card to `feed/jobs.json`, validates it offline, pushes to `main`, then comments on and closes the issue. This is the only path that writes the public feed.
- ci.yml: formatting/analyze/test; no APK/AAB.
- widget-tests.yml: focused Flutter widget diagnostics.
- ui-screenshots.yml: web build screenshots; Flutter web support required; public artifact/image branch implications apply.
- manual-build.yml: APK/AAB artifact; signing requirements depend on selected format/configuration.
- web-preview.yml: web build and gh-pages branch write; Pages was already enabled when checked; see WEB_PREVIEW.md. Does not change About link. Manual deployment deliberately replaces upstream automatic push behavior.
- preview-cleanup.yml: explicit manual branch-preview cleanup; main/master protected by reusable runner.
- publish-release.yml: signed Android release; draft default true, analysis/tests required, optional Play internal upload default false. Still creates tags/releases when run. Never dispatch without owner's release authorization. Release notes and Play secrets required for Play path.

No copied builder-maintenance workflows: installer-tests, smoke-test and bump-consumers belong to flutter-builder itself, not this consumer app. Call reusable workflows rather than copying their implementation, whose relative scripts belong upstream.

No secrets configured, settings changed or new deployment performed by captain. Existing Pages hosting is enabled. Web builds now select safe demo UI by default; see WEB_PREVIEW.md. Inherit-secrets callers must never run untrusted branches with sensitive credentials. Public app source does not imply public admin drafts. No self-hosted runners here.
