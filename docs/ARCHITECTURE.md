# Architecture and cost boundaries
## Client
Flutter Android. Captain chooses/pins dependencies and implements app composition. Data flow: public read-only JSON -> strict validation -> repository/cache -> UI. Worker B consumes contracts, never imports worker A implementation. App gets no GitHub, Gemini, publisher or FCM server credentials.

## Publishing
Public source repository for code and reviewed documentation. Admin drafts stay local and outside git; only intentionally public sanitized feed may be deployed to a free static host (GitHub Pages candidate). Private raw.githubusercontent.com is NOT a public CDN; never put a private-repo token in the app. Public feed is a separate deployment approval, not authorized by this docs batch. Client feed URL remains configurable until provisioned.

Manual MVP: local admin form -> validated JSON export -> captain review -> atomic publication of entire feed. Public app has no admin section or secret gestures. Owner admin is a separate local browser tool. Draft export is not publication.

Later automation: scheduled fetch -> extraction -> draft queue -> human verification -> publish; a failed fetch retains last good feed and alerts owner. Four WB official hosts timed out from both sandbox and GitHub-hosted runners. Do not assume GitHub can fetch them. Indian self-hosted runner is unverified until owner tests; if adopted it must live in a SEPARATE PRIVATE ingestion repository, never this public repository. Never run untrusted PR code on owner PC. Available alternative sources do not waive official-source review/copyright requirements. Automation is not MVP worker scope.

FCM server sending requires secure server-side authorization and a registered project. Gemini optional for future extraction; neither key needed for manual MVP. Local reminders do not require FCM. Avoid promising exactly-on-time background execution on Android.

## Costs
Design targets ₹0 monthly using free tiers, own PC and static feed; no guaranteed unlimited bandwidth/availability. Play enrollment is US$25 one-time; INR/tax/exchange amount varies. Tester access, device/internet, optional domains/VPS are owner costs if needed. No paid billing or infrastructure activation without approval. Ads revenue not guaranteed.
