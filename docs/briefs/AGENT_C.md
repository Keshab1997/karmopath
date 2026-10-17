# Worker C — batch 1
Status: BLOCKED until captain foundation exists and common base SHA is recorded. These docs alone are not dispatch authorization.
Repository: https://github.com/Keshab1997/karmopath.git (public).
Branch: `agent/C/admin-v1`
Read: README.md, AGENTS.md, docs/PRODUCT.md, DESIGN.md, ARCHITECTURE.md, CONTRACTS.md, ADMIN.md, POLICY.md, ACCEPTANCE.md.
Allowed writes ONLY: admin/**; tools/feed/**; tests/feed/**; docs/reports/C.md
Task: Build dependency-free local HTML/CSS/JS admin with bilingual drafts/import/edit/preview/export and clear review confirmation. Build stdlib Python validate.py against CONTRACTS, field-path errors and nonzero failure exit. Unit tests via unittest. No network, actual publishing, auth theater, scraping or keys. Include local usage README under admin; demo fixtures labeled sample and never production feed.
DO NOT TOUCH: every captain-owned path in AGENTS.md, other worker paths, root docs, dependencies, workflows/settings/secrets/generated files, main. Request integration if a missing shared contract/asset blocks you; do not create conflicting substitutes.
Gate: actual repository preflight; relevant tests only (C: python3 -m unittest discover -s tests/feed). Never flutter build, gradlew, CI dispatch, merge, tag or release. Report SDK/tool limitations honestly.
Delivery: commit and push only your branch; docs/reports/C.md must list scope, tests, remaining captain integration and five-line report per AGENTS.md. Do not alter root planning docs. No report of completion without actual code/tests.
