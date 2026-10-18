# Batch 7 — A/B pushed handoff reviewed, LOCAL candidate only

## Inputs and scope

Keshab reported that A and B pushed. Captain restored the existing login without a device flow, fetched their actual branches and reviewed source/tests, not just their reports:

- A: `origin/agent/A/b7-os-reconcile-20261018`, immutable head `85dca4c1c7b7aec9a4becd5493128d6268cec899`.
- B: `origin/agent/B/b7-notification-copy-20261018`, immutable head `d1a79a2e810188b095d45c6156ccd376e2823af7`.
- Both worker branches start at `80adedcae21629c5c6928f30f7852f6640539ec4` and match the Captain-issued two-worker briefs from this conversation exactly: A has three allowed paths; B has four. No unexpected dependency/shared-surface changes or credential literals were found.
- Their committed reports describe their pre-push local-only state. The heads above are now actually present remotely; the historical report wording was not silently rewritten.

Meanwhile fetched `origin/main` is `00e3b29ab44a20f517c0fdb2e071068edb13e4af`, with an additional three-worker dispatch, new native ports/tests, packages and Android prerequisites. This newer dispatch's A/B assignments differ from the two legacy briefs whose work was delivered here. **This review does not claim those newer A/B/C tasks are complete.** When asked about the plans, Keshab said he did not understand; no new public-push approval or API/ownership choice was inferred from that response.

Safest action taken: review the delivered two-worker work against its actual assigned scope, stage one reviewed squash at a time on a separate local branch based on the newly fetched main, and preserve the published main's other content byte-for-byte. Do not burden the owner with choosing implementation APIs or erase either line of work.

## Local reviewed candidate

Branch: `captain/review/b7-b-20261018`.

- A reviewed squash: `d949ea5` — pending-aware reconciliation on the same applier queue; stable-ID repair, known reservation-only orphan cancellation, no empty-list fallback on query failure, per-operation persistence/failures, global cancel-before-schedule order and an unknown pending-ID allocation collision guard. Existing `apply` / `applyDiff` code and public signatures are preserved.
- B reviewed squash: `07864fc` — pure Bengali/English content DTO/builder, exact approved body, verbatim full job ID/title and stable variants. No global language, time, permission, storage or scheduling effects.
- Captain fixed one test-only analyzer info: unused callback parameter `__` became the modern wildcard `_`. No behavior or worker production implementation changed.

No main fast-forward, remote push, PR, branch deletion or public upload occurred. Local `main` remains at `80adedc`; fetched `origin/main` was only read. The review candidate is NOT the production entrypoint or completed native integration.

## Actual gate evidence

| Command/check | Actual result |
|---|---|
| `python3 tool/preflight.py` | PASS |
| A focused `reminder_reconcile_test.dart` + existing `reminder_apply_test.dart` | 41 passed: 17 new + 24 existing regression tests |
| B focused `reminder_notification_content_test.dart` | 8 passed |
| `flutter test --reporter expanded` on latest fetched main + reviewed A/B candidate | 496 passed (471 existing foundation/port tests + 25 worker tests) |
| `flutter analyze` | Initially one test-only unnecessary-underscore info; fixed by Captain, then **No issues found** |
| A focused reconciliation file after that lint-only fix | 17 passed |
| Diff/scope/credential checks | PASS; exactly seven worker paths, plus this Captain report |

The 496-test full run preceded only the one-line test wildcard lint cleanup. The cleanup was rechecked with the affected 17 tests, full analyzer, preflight and diff checks; no second full-suite result is fabricated.

No Flutter build/Gradle, CI dispatch/wait, deployment, release, native device notification/permission/reboot/force-stop/delivery checks were run. Package resolution did not alter the published dependency/lock files. No broad reformat or unrelated code fix was introduced.

## Preserved work and next integration obligations

1. Captain's independent native foundation remains intact on `captain/b7-native-wiring-20261018` at `c66b15e`, with its own prior 508-test evidence. It has NOT yet been combined with this candidate. Do not add the two test counts or claim the combined native implementation has passed.
2. Preserve the fetched main's native ports, contracts/tests, Android resources, dependency pins (including `url_launcher`) and dispatch docs. When combining the older Captain foundation, reconcile its old icon name with the current `ic_stat_karmopath` resource/keep declaration; do not overwrite new main's shared files with an older snapshot.
3. Implement/review the real native binding using the now-available A/B helpers. B's content payload remains a full job ID; any namespace/identity envelope required by the published native boundary belongs to the Captain adapter, not an unauthorized change to B's API.
4. A's helper accepts IDs, not complete native payload identities. The final platform binding must guard managed/foreign/malformed payloads and reserved-ID conflicts using the published pending metadata ports before destructive operations. Plugin pending records are not independent evidence of live AlarmManager alarms; startup/force-stop/reboot repair still needs a safe strategy and device evidence. Do not call these pure tests proof of delivery.
5. Preserve an unloaded feed as unknown rather than an empty desired plan. Keep operational errors/retry truthful and verify current-language/copy replacement, cleanup and resume behavior in the final combined runtime. Any other arriving worker branch must be inspected/deduplicated, not overwritten or assumed merged.
6. Native entrypoint activation remains OFF pending explicit real feed URL approval and completion of integration/hardening gates. Web demo stays separate. Public push remains held under the owner's earlier explicit instruction; a report that workers pushed is not treated as permission for a Captain main push.
7. Before any later authorized main integration/push, fetch again, review changes since this immutable main base, gate the actual combined candidate, and never force-push or discard other work. Tags/releases, secrets/settings, workflows/CI and deployment retain their separate restrictions.
