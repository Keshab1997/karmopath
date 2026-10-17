# Worker A — batch 1
Status: ready against the common base recorded in docs/DISPATCH_BATCH_1.md. Read that setup first; do not use an older docs-only commit.
Repository: https://github.com/Keshab1997/karmopath.git (public).
Branch: `agent/A/data-v1`
Read: README.md, AGENTS.md, docs/PRODUCT.md, DESIGN.md, ARCHITECTURE.md, CONTRACTS.md, ADMIN.md, POLICY.md, ACCEPTANCE.md.
Allowed writes ONLY: lib/data/**; test/data/**; docs/reports/A.md
Task: Implement CachedJobRepository and LocalUserPreferences exactly per CONTRACTS. Inject transport/cache/store; validate before cache commit, preserve previous good state, prevent concurrent refresh races, recover corrupted cache, expose useful state. Persist immutable set snapshots and handle storage errors truthfully. Test refresh success/failure/corruption and saved/reminder persistence with fakes.
DO NOT TOUCH: every captain-owned path in AGENTS.md, other worker paths, root docs, dependencies, workflows/settings/secrets/generated files, main. Request integration if a missing shared contract/asset blocks you; do not create conflicting substitutes.
Gate: actual repository preflight; relevant tests only (C: python3 -m unittest discover -s tests/feed). Never flutter build, gradlew, CI dispatch, merge, tag or release. Report SDK/tool limitations honestly.
Delivery: commit and push only your branch; docs/reports/A.md must list scope, tests, remaining captain integration and five-line report per AGENTS.md. Do not alter root planning docs. No report of completion without actual code/tests.
