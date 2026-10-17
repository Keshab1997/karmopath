# Web design preview
## Current hosting
GitHub Pages was already enabled and built when checked by captain: source `gh-pages` / root, HTTPS enforced. No Pages setting was changed in this setup.

Preview URL: https://keshab1997.github.io/karmopath/preview/main/
Preview hub: https://keshab1997.github.io/karmopath/

The existing URL returned HTTP 200, but currently serves the older foundation deployment. A new manual workflow run is required to publish the new UI. Do not interpret the URL check as validation of the new web bundle.

## Keshab: deploy when ready
1. Open https://github.com/Keshab1997/karmopath/actions/workflows/web-preview.yml
2. **Run workflow → Branch: main → Run workflow**.
3. After success, use the preview URL from that run's summary (main URL above).
4. Refresh the browser; if an old cached version appears use a private window or clear the site's cache.

Caller uses flutter-builder v1.15.0 and passes `KARMOPATH_PREVIEW=true`. It remains manual-only, GitHub-hosted, with no About-link changes. Captain has not dispatched it or run flutter build/gradlew locally.

## What the design preview contains
- Home, Saved, Calendar, Settings and sample job detail navigation using the actual Flutter feature widgets.
- Persistent visible DEMO banner on home and detail; all vacancy titles/organization labels explicitly say sample/demo. Example.org links are placeholders, never real application endpoints.
- Session-only bookmarks/cache. Refresh/reopen resets them; no browser persistence is claimed.
- No production network feed, notifications, permission grants, ads, admin drafts, credentials or external application links. Link actions fail safely; reminder permission returns false.
- Rolling dates only for demo layout. Demo reviewed timestamps are synthetic and must never be treated as verified official notices or copied into a production feed.

Without the compile-time define, main still selects the foundation app. This is intentionally a safe design-preview composition, NOT the production integration. To preview locally: `flutter run -d chrome --dart-define=KARMOPATH_PREVIEW=true`.

## Evidence and remaining gates
Two widget integration tests cover marked samples, session bookmarks, detail/reminder denial, calendar/settings navigation and 320px layout. Full analysis/tests are local checks only. Browser/WASM compilation, deployed visual fidelity, native Android behavior and actual reminder delivery are not established by them; inspect after owner dispatch. Production wiring remains a separate task.
