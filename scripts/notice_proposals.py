#!/usr/bin/env python3
"""Turn live notice links into notice-only card proposals for a human to approve.

This is the read-only half of the pipeline in docs/REAL_DATA_RUNBOOK.md. It
exists because discovery records a listing page on its first run and never
reports those links again, so the notices already sitting on an official board
have no path into the feed except a human writing an issue by hand.

What it does:
  * Reads a candidate list (``scripts/discover_notices.py --report-candidates``
    output, a discovery ``--out`` file, or a hand-curated JSON list) and prints
    one proposal per live link.
  * Builds each card with ``scripts/publish_notice.build_job``, so a proposal is
    byte-for-byte the card the ``approve-notice`` publisher would write. The
    card is a preview: it is never merged into ``feed/jobs.json``.
  * Links already in the feed, or on a host the source does not allow, are
    reported as skipped instead of being proposed twice.
  * Re-parses the generated issue body with the publisher's own parser, so an
    approved issue cannot publish something other than the previewed card.
  * Writes ``gh issue create`` commands, which is how a proposal reaches the
    review queue. Opening an issue is not a verification: the human still has to
    open the notice and add ``approve-notice``.

It never writes to the feed and never applies a label. The publication gate
stays exactly where docs/CONTRACTS.md puts it.

Usage:
  python3 scripts/notice_proposals.py \
      --candidates candidates.json --sources ops/notice_sources.json \
      --seen ops/notice_seen.json --feed feed/jobs.json \
      --out docs/proposals/notice-only-batch.json \
      --issues-out docs/proposals/notice-only-batch.sh --limit 8
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import discover_notices as dn  # noqa: E402 - shared seen-file reader
import publish_notice as pn  # noqa: E402 - shared card builder, not a duplicate

# GitHub rejects long issue titles, and the card title comes from the issue
# title, so the cap is applied here and flagged instead of failing at approval.
MAX_TITLE = 200

ISSUE_BODY = (
    "{title}\n\n"
    "- Source listing: {source}\n"
    "- Notice link: {url}\n\n"
    "Human steps before any feed change:\n"
    "1. Open the notice and confirm it is on an official site.\n"
    "2. Record last date, vacancy, eligibility and apply link from the notice "
    "itself.\n"
    "3. Only then add or update the job in the feed draft "
    "(docs/REAL_DATA_RUNBOOK.md).\n\n"
    "This proposal was generated offline by scripts/notice_proposals.py from a "
    "listing page captured on {captured_on}. It is not a verification. The card "
    "preview says eligibility, vacancies and dates were not checked."
)


class ProposalError(ValueError):
    """The candidate list is not usable."""


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise ProposalError(f"cannot read {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise ProposalError(f"{path} is not valid JSON: {error}") from error


def load_candidates(path: Path) -> list[dict]:
    """Accept a discovery report, a candidate report or a bare curated list."""
    raw = load_json(path)
    if isinstance(raw, dict):
        for key in ("candidates", "new", "items", "notices"):
            if isinstance(raw.get(key), list):
                raw = raw[key]
                break
    if not isinstance(raw, list):
        raise ProposalError(
            f"{path} must be a JSON list, or an object with a "
            "'candidates'/'new'/'items'/'notices' list"
        )
    items: list[dict] = []
    for index, entry in enumerate(raw):
        if not isinstance(entry, dict):
            raise ProposalError(f"{path}: item {index} is not an object")
        url = entry.get("url") or entry.get("notice_url")
        title = entry.get("title") or entry.get("title_en")
        source = entry.get("source") or entry.get("source_name")
        if not isinstance(url, str) or not url.strip():
            raise ProposalError(f"{path}: item {index} has no 'url'")
        if not isinstance(title, str) or not title.strip():
            raise ProposalError(f"{path}: item {index} has no 'title'")
        if not isinstance(source, str) or not source.strip():
            raise ProposalError(f"{path}: item {index} has no 'source'")
        items.append(
            {
                "url": url.strip(),
                "title": title.strip(),
                "source": " ".join(source.split()),
                "seen_on": entry.get("seen_on"),
                "is_new": entry.get("is_new"),
            }
        )
    return items


def clean_url(url: str) -> str:
    """Encode spaces and drop the fragment, the way the publisher will."""
    parts = urlsplit(url.strip())
    return pn.encode_url_spaces(
        urlunsplit((parts.scheme, parts.netloc, parts.path, parts.query, ""))
    )


def feed_notice_urls(path: Path | None) -> dict[str, str]:
    """{notice_url: id} for a feed, read-only. Missing file means an empty feed."""
    if path is None or not path.exists():
        return {}
    feed = load_json(path)
    if not isinstance(feed, dict) or not isinstance(feed.get("jobs"), list):
        raise ProposalError(f"{path} is not a feed object with a jobs array")
    out: dict[str, str] = {}
    for job in feed["jobs"]:
        if isinstance(job, dict) and isinstance(job.get("notice_url"), str):
            out[pn.encode_url_spaces(job["notice_url"])] = str(job.get("id", "?"))
    return out


def cap_title(title: str, limit: int = MAX_TITLE) -> tuple[str, bool]:
    """Trim at a word boundary, without inventing or re-wording anything."""
    if len(title) <= limit:
        return title, False
    head = title[:limit]
    trimmed = head.rsplit(" ", 1)[0] if " " in head else head
    return trimmed.rstrip(" ,;:-·"), True


def sha_now(raw: str | None) -> datetime:
    if raw is None:
        return datetime.now(timezone.utc)
    try:
        return datetime.strptime(raw, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError as error:
        raise ProposalError(f"--now must be YYYY-MM-DDTHH:MM:SSZ, got {raw!r}") from error


def build_proposals(
    candidates: list[dict],
    sources: list[dict],
    *,
    now: datetime,
    feed_urls: dict[str, str],
    only_new: bool,
    max_title: int,
    seen: dict[str, str] | None = None,
) -> tuple[list[dict], list[dict]]:
    """Build one preview per usable candidate.

    ``seen`` is the discovery seen-map, used to flag links a daily run has
    already reported. A candidate that carries its own flag is never overtyped.
    """
    seen = seen or {}
    proposals: list[dict] = []
    skipped: list[dict] = []
    seen_urls: set[str] = set()
    for entry in candidates:
        url = clean_url(entry["url"])
        if url in seen_urls:
            skipped.append({"url": url, "source": entry["source"], "reason": "duplicate-in-input"})
            continue
        seen_urls.add(url)
        if entry.get("is_new") is None:
            entry = {**entry, "seen_on": seen.get(url), "is_new": url not in seen}
        if url in feed_urls:
            skipped.append(
                {
                    "url": url,
                    "source": entry["source"],
                    "reason": f"already-in-feed as {feed_urls[url]}",
                }
            )
            continue
        if only_new and entry.get("is_new") is False:
            skipped.append(
                {
                    "url": url,
                    "source": entry["source"],
                    "reason": f"already-reported-on {entry.get('seen_on')}",
                }
            )
            continue
        try:
            source = pn.source_by_name(sources, entry["source"])
            allowed = source.get("allowed_domains")
            if not isinstance(allowed, list) or not allowed:
                raise ProposalError(f"source {entry['source']!r} has no allowed_domains")
            if not pn.host_allowed(url, [str(d).lower() for d in allowed]):
                raise ProposalError(
                    "notice link host is not on the approved domain for "
                    f"{entry['source']!r}: {(urlsplit(url).hostname or '')}"
                )
            title, truncated = cap_title(pn.clean_title(entry["title"]), max_title)
            notice = {
                "title": title,
                "url": url,
                "source_name": entry["source"],
                "source_url": source["url"],
            }
            card = pn.build_job(notice, now)
        except (ProposalError, pn.NoticeError, KeyError) as error:
            skipped.append({"url": url, "source": entry["source"], "reason": str(error)})
            continue
        body = ISSUE_BODY.format(
            title=title,
            source=entry["source"],
            url=url,
            captured_on=now.date().isoformat(),
        )
        proposals.append(
            {
                "id": card["id"],
                "url": url,
                "source": entry["source"],
                "seen_on": entry.get("seen_on"),
                "is_new": entry.get("is_new"),
                "title_truncated": truncated,
                "card": card,
                "issue": {"title": f"{pn.TITLE_PREFIX}{title}", "body": body},
            }
        )
    return proposals, skipped


def selfcheck(proposals: list[dict], sources: list[dict], now: datetime) -> None:
    """Publishing the issue must produce exactly the previewed card."""
    for proposal in proposals:
        parsed = pn.parse_issue(proposal["issue"], sources)
        rebuilt = pn.build_job(parsed, now)
        if rebuilt != proposal["card"]:
            raise ProposalError(
                f"round trip differs for {proposal['url']}: the approved issue "
                "would not publish the previewed card"
            )


def guard_output(path: Path) -> None:
    resolved = path.resolve()
    if resolved.parent == (ROOT / "feed").resolve() or resolved == (
        ROOT / "feed" / "jobs.json"
    ).resolve():
        raise ProposalError(
            f"refusing to write {resolved}: feed/jobs.json is written only by the "
            "approve-notice publisher (docs/REAL_DATA_RUNBOOK.md)"
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--candidates", type=Path, required=True)
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--seen", type=Path)
    parser.add_argument("--feed", type=Path)
    parser.add_argument("--out", type=Path, help="proposal document (never a live feed)")
    parser.add_argument(
        "--feed-preview",
        type=Path,
        help="feed-shaped preview for tools/feed/validate.py, in docs/proposals/",
    )
    parser.add_argument("--issues-out", type=Path, help="shell script of gh issue create calls")
    parser.add_argument("--limit", type=int, default=10)
    parser.add_argument("--max-title", type=int, default=MAX_TITLE)
    parser.add_argument(
        "--only-new",
        action="store_true",
        help="drop links a discovery run already reported",
    )
    parser.add_argument("--now", help="UTC timestamp for reproducible previews")
    args = parser.parse_args(argv)

    try:
        now = sha_now(args.now)
        candidates = load_candidates(args.candidates)
        sources = pn.load_sources(args.sources)
        feed_urls = feed_notice_urls(args.feed)
        seen = dn.load_seen(args.seen) if args.seen else None
        proposals, skipped = build_proposals(
            candidates,
            sources,
            now=now,
            feed_urls=feed_urls,
            only_new=args.only_new,
            max_title=args.max_title,
            seen=seen,
        )
        usable = len(proposals)
        proposals = proposals[: args.limit]
        dropped = usable - len(proposals)
        selfcheck(proposals, sources, now)
        stamp = now.strftime("%Y-%m-%dT%H:%M:%SZ")

        if args.out:
            guard_output(args.out)
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_text(
                json.dumps(
                    {
                        "kind": "karmopath-notice-proposals",
                        "generated_at": stamp,
                        "note": (
                            "Previews of notice-only cards, built by the same "
                            "code as the approve-notice publisher. Not a feed, "
                            "not a verification, not published."
                        ),
                        "total_candidates": len(candidates),
                        "total_usable": usable,
                        "limit": args.limit,
                        "not_proposed_this_batch": dropped,
                        "proposals": proposals,
                        "skipped": skipped,
                    },
                    ensure_ascii=False,
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
        if args.feed_preview:
            guard_output(args.feed_preview)
            args.feed_preview.parent.mkdir(parents=True, exist_ok=True)
            args.feed_preview.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "updated_at": stamp,
                        "jobs": [item["card"] for item in proposals],
                    },
                    ensure_ascii=False,
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )
        if args.issues_out:
            guard_output(args.issues_out)
            args.issues_out.parent.mkdir(parents=True, exist_ok=True)
            lines = [
                "#!/usr/bin/env bash",
                "# Opens one issue per proposal, then confirms the notice-review",
                "# label actually landed. Reviewing and labelling stays a human",
                "# act: this never applies 'approve-notice' and never edits",
                "# feed/jobs.json.",
                "#",
                "# The check is not ceremony. publish-notice.yml only runs for an",
                "# issue carrying BOTH notice-review and approve-notice, and a",
                "# token that may create issues cannot always edit labels - so a",
                "# silently unlabelled issue looks approved in the tracker and can",
                "# never be published.",
                "set -uo pipefail",
                "MISSING=()",
                "",
            ]
            for item in proposals:
                lines.append(
                    "created=$(gh issue create "
                    f"--title {json.dumps(item['issue']['title'])} "
                    "--body-file /dev/stdin <<'KARMOPATH_ISSUE_BODY'\n"
                    f"{item['issue']['body']}\nKARMOPATH_ISSUE_BODY\n"
                    '    ) || exit 1\n'
                    'number=${created##*/}\n'
                    'if ! gh issue edit "$number" --add-label notice-review >/dev/null 2>&1; then\n'
                    '  MISSING+=("$number")\n'
                    "fi"
                )
            lines += [
                "",
                'if [ ${#MISSING[@]} -gt 0 ]; then',
                '  echo "Issues created without the notice-review label: ${MISSING[*]}" >&2',
                '  echo "With a token that can write labels, run:" >&2',
                '  echo "  gh issue edit ${MISSING[*]} --add-label notice-review" >&2',
                "  exit 1",
                "fi",
                'echo "All issues created and labelled notice-review."',
            ]
            args.issues_out.write_text("\n".join(lines) + "\n", encoding="utf-8")
            args.issues_out.chmod(0o755)
    except (ProposalError, pn.NoticeError, OSError) as error:
        print(f"[error] {error}", file=sys.stderr)
        return 2

    print(f"[info] {len(proposals)} proposal(s), {len(skipped)} skipped")
    if dropped:
        print(
            f"[warn] {dropped} usable link(s) not proposed: --limit {args.limit}. "
            "Re-run with a higher --limit or --out per source."
        )
    for item in proposals:
        print(
            f"  - {item['id']} [{item['source']}] "
            f"{'new' if item['is_new'] else 'seen:' + str(item['seen_on'])} "
            f"{item['card']['title_en'][:70]}"
        )
    for item in skipped:
        print(f"  x skipped ({item['reason']}): {item['url'][:80]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
