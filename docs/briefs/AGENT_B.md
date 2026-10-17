# Worker B — batch 1
Status: BLOCKED until captain foundation exists and common base SHA is recorded. These docs alone are not dispatch authorization.
Repository: https://github.com/Keshab1997/karmopath.git (public).
Branch: `agent/B/screens-v1`
Read: README.md, AGENTS.md, docs/PRODUCT.md, DESIGN.md, ARCHITECTURE.md, CONTRACTS.md, ADMIN.md, POLICY.md, ACCEPTANCE.md.
Allowed writes ONLY: lib/features/**; test/features/**; docs/reports/B.md
Task: Build HomeScreen, JobDetailScreen, SavedScreen, CalendarScreen, SettingsScreen constructors exactly per CONTRACTS using shared tokens/assets. Match approved v2. Implement local search/filter, source links through AppActions, bookmarks/reminder intent and all empty/loading/error/offline states. English/Bengali widgets, no raster text. No production ads/login/FCM. Widget tests with fake contracts; return unknown job navigation to captain.
DO NOT TOUCH: every captain-owned path in AGENTS.md, other worker paths, root docs, dependencies, workflows/settings/secrets/generated files, main. Request integration if a missing shared contract/asset blocks you; do not create conflicting substitutes.
Gate: actual repository preflight; relevant tests only (C: python3 -m unittest discover -s tests/feed). Never flutter build, gradlew, CI dispatch, merge, tag or release. Report SDK/tool limitations honestly.
Delivery: commit and push only your branch; docs/reports/B.md must list scope, tests, remaining captain integration and five-line report per AGENTS.md. Do not alter root planning docs. No report of completion without actual code/tests.
