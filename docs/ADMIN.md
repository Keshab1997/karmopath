# Owner admin — manual job posting
## Delivery
Separate local admin tool, not a hidden screen in the consumer Android app. Run local static preview bound to 127.0.0.1 on owner's PC; no public deployment planned. No login is implied: it is private by local access, not a secure multi-user service. If hosted remotely later, real authenticated server-side authorization is mandatory before writes.

## Workflow
1. Open admin/index.html locally. Create draft or import existing feed; validate imported data before replacing working state.
2. Fill both languages, kind, category, organization, district, qualifications, dates, summary/application steps and original official URLs. Unknown values remain null. Stable ID editable only before initial publication.
3. Save local draft; browser localStorage is convenient, NOT durable backup. Export drafts regularly. No credentials or private applicant information stored.
4. Preview card/detail; explicitly confirm that notice, eligibility and deadline were checked. Set reviewed timestamp through this action, never fake verification.
5. Export candidate feed. CLI validate, review diff, then captain publishes separately. UI must say Export candidate, not Published.
6. Edit existing ID for corrections/closures/withdrawal; preserve published_at, advance updated_at/reviewed_at on genuine review. Expired jobs visibly closed using date as well as status. Deletion requires confirmation and review.

## Security
Use textContent / safe DOM construction for imported strings; never innerHTML for user fields. Reject unsafe URLs, duplicate IDs, malformed timestamps and schema mismatches. No fetch-and-scrape of arbitrary URLs, no embedded remote HTML, no secrets, no browser GitHub token, no open publish API. Local imported text remains untrusted. Don't silently overwrite imported feed with empty/new feed. Candidate export includes reviewed records only; drafts stay separately exportable and outside feed schema.

## CLI
`python3 tools/feed/validate.py <candidate.json>`; exit 0 valid, nonzero with field-path errors invalid. No network and no writes to repo/feed in validator. Future publication command is captain-owned and not part of worker C.
