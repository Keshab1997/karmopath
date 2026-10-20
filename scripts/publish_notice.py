#!/usr/bin/env python3
"""Turn an approved notice-review issue into one notice-only feed card.

The discovery workflow never publishes to the app feed. A human opens the
notice, checks that it is on an official site, and adds the ``approve-notice``
label. Only then does this script run (from ``publish-notice.yml``).

What it guarantees:
  * The notice link must be on a domain approved in ``ops/notice_sources.json``
    for the named source. A hand-written issue cannot smuggle in another site.
  * The card carries no vacancies, deadline, eligibility or apply link. It
    links to the original notice and says in both languages that those details
    were not checked here.
  * Running the same approval twice is idempotent: the job id is derived from
    the notice URL, so a second run reports ``already-published`` and does not
    duplicate or rewrite the entry.
  * The resulting feed is validated offline before it is written.

Usage:
  python3 scripts/publish_notice.py \
      --issue issue.json --sources ops/notice_sources.json --feed feed/jobs.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

ROOT = Path(__file__).resolve().parents[1]

TITLE_PREFIX = "[notice] "
LINK_RE = re.compile(r"^- Notice link:\s*(https://.+?)\s*$", re.MULTILINE)
SOURCE_RE = re.compile(r"^- Source listing:\s*(.+?)\s*$", re.MULTILINE)
TRAILING_PDF_RE = re.compile(r"(?:\.pdf)+\s*$", re.IGNORECASE)

SUMMARY_BN = (
    "সরকারি সাইটে প্রকাশিত বিজ্ঞপ্তি। যোগ্যতা, শূন্যপদ ও শেষ তারিখ "
    "এই কার্ডে যাচাই করা হয়নি — মূল বিজ্ঞপ্তি দেখুন।"
)
SUMMARY_EN = (
    "Official notice published on the source site. Eligibility, vacancies "
    "and the last date have not been checked for this card — read the "
    "original notice."
)
HOW_TO_APPLY_BN = "আবেদনের নিয়ম ও শেষ তারিখ মূল বিজ্ঞপ্তিতে দেখুন।"
HOW_TO_APPLY_EN = "See the original notice for how to apply and the last date."


class NoticeError(ValueError):
    """The issue is not safe or complete enough to publish."""


def encode_url_spaces(url: str) -> str:
    """Percent-encode literal spaces so the URL is valid and launchable.

    Official listing pages link PDFs whose filenames contain spaces. Browsers
    encode them automatically; a feed URL must do it explicitly because the
    validator rejects whitespace and the app's launcher expects a clean URI.
    """
    parts = urlsplit(url)
    return urlunsplit(
        (
            parts.scheme,
            parts.netloc,
            parts.path.replace(" ", "%20"),
            parts.query.replace(" ", "%20"),
            parts.fragment.replace(" ", "%20"),
        )
    )


def clean_title(raw: str) -> str:
    """Turn listing anchor text into a card title without inventing words."""
    title = " ".join(raw.replace("\u00a0", " ").split())
    title = TRAILING_PDF_RE.sub("", title).strip(" .")
    if not title:
        raise NoticeError("issue title is empty after removing '[notice] '")
    return title


def load_sources(path: Path) -> list[dict]:
    config = json.loads(path.read_text(encoding="utf-8"))
    sources = config.get("sources")
    if not isinstance(sources, list) or not sources:
        raise NoticeError(f"{path} has no sources")
    return sources


def source_by_name(sources: list[dict], name: str) -> dict:
    for source in sources:
        if source.get("name") == name:
            return source
    names = ", ".join(sorted(str(s.get("name")) for s in sources))
    raise NoticeError(f"unknown source {name!r}; approved sources are: {names}")


def host_allowed(url: str, allowed_domains: list[str]) -> bool:
    host = (urlsplit(url).hostname or "").lower()
    return any(host == d or host.endswith("." + d) for d in allowed_domains)


def parse_issue(issue: dict, sources: list[dict]) -> dict:
    """Return {title, url, source_name, source_url} or raise NoticeError."""
    raw_title = issue.get("title")
    if not isinstance(raw_title, str) or not raw_title.startswith(TITLE_PREFIX):
        raise NoticeError("issue title must start with '[notice] '")
    title = clean_title(raw_title[len(TITLE_PREFIX) :])

    body = issue.get("body")
    if not isinstance(body, str):
        raise NoticeError("issue body is missing")

    links = LINK_RE.findall(body)
    if len(links) != 1:
        raise NoticeError("issue body must contain exactly one '- Notice link:' line")
    url = encode_url_spaces(links[0].strip())
    parts = urlsplit(url)
    if parts.scheme != "https" or not parts.hostname:
        raise NoticeError("notice link must be an absolute HTTPS URL")
    if parts.username is not None or parts.password is not None:
        raise NoticeError("notice link must not contain credentials")
    if parts.fragment:
        raise NoticeError("notice link must not contain a fragment")

    names = SOURCE_RE.findall(body)
    if len(names) != 1:
        raise NoticeError("issue body must contain exactly one '- Source listing:' line")
    source_name = " ".join(names[0].split())
    source = source_by_name(sources, source_name)

    allowed = source.get("allowed_domains")
    if not isinstance(allowed, list) or not allowed:
        raise NoticeError(f"source {source_name!r} has no allowed_domains")
    if not host_allowed(url, [str(d).lower() for d in allowed]):
        raise NoticeError(
            f"notice link host is not allowed for {source_name!r}: {parts.hostname}"
        )

    source_url = source.get("url")
    if not isinstance(source_url, str) or urlsplit(source_url).scheme != "https":
        raise NoticeError(f"source {source_name!r} has no approved HTTPS listing URL")

    return {
        "title": title,
        "url": url,
        "source_name": source_name,
        "source_url": source_url,
    }


def notice_id(url: str) -> str:
    """Stable id from the notice URL, never from a mutable title."""
    digest = hashlib.sha256(url.encode("utf-8")).hexdigest()[:16]
    return f"notice-{digest}"


def infer_category(source_name: str) -> str:
    """Presentation category from the approved source, not from the notice text."""
    name = source_name.lower()
    if "police" in name:
        return "police"
    if "railway" in name or "rrc" in name:
        return "railway"
    # The app has had a banking chip since batch 1 and the publisher could
    # never fill it: without this branch every IBPS/cooperative-bank card
    # landed in "other" and the category filter stayed permanently empty.
    if "banking" in name or "bank" in name or "ibps" in name:
        return "banking"
    if "school service" in name or "teacher" in name:
        return "teaching"
    if "health" in name or "medical" in name:
        return "medical"
    if "public service commission" in name:
        return "office"
    return "other"


def build_job(notice: dict, now: datetime) -> dict:
    stamp = now.astimezone(timezone.utc).replace(microsecond=0).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    return {
        "id": notice_id(notice["url"]),
        "kind": "notice",
        "title_bn": notice["title"],
        "title_en": notice["title"],
        "organization": notice["source_name"],
        "category": infer_category(notice["source_name"]),
        "districts": ["West Bengal"],
        "qualifications": [],
        "status": "published",
        "source_url": notice["source_url"],
        "notice_url": notice["url"],
        "reviewed_at": stamp,
        "published_at": stamp,
        "updated_at": stamp,
        "summary_bn": SUMMARY_BN,
        "summary_en": SUMMARY_EN,
        "how_to_apply_bn": HOW_TO_APPLY_BN,
        "how_to_apply_en": HOW_TO_APPLY_EN,
        "vacancies": None,
        "application_start_date": None,
        "application_end_date": None,
        "application_end_at": None,
        "exam_date": None,
        "apply_url": None,
        "age_note_bn": None,
        "age_note_en": None,
    }


def load_feed(path: Path, now: datetime) -> dict:
    if not path.exists():
        return {
            "schema_version": 1,
            "updated_at": now.astimezone(timezone.utc)
            .replace(microsecond=0)
            .strftime("%Y-%m-%dT%H:%M:%SZ"),
            "jobs": [],
        }
    feed = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(feed, dict) or not isinstance(feed.get("jobs"), list):
        raise NoticeError(f"{path} is not a feed object with a jobs array")
    return feed


def upsert(feed: dict, job: dict) -> str:
    """Add the job unless its URL/id is already present. Returns the outcome."""
    for existing in feed["jobs"]:
        if not isinstance(existing, dict):
            continue
        if existing.get("id") == job["id"] or existing.get("notice_url") == job["notice_url"]:
            return "already-published"
    feed["jobs"].append(job)
    return "added"


def validate_feed(feed: dict, now: datetime) -> None:
    sys.path.insert(0, str(ROOT / "tools" / "feed"))
    import validate  # noqa: PLC0415 - local import keeps the script dependency-free

    errors = validate.validate_feed(feed, now)
    if errors:
        raise NoticeError("feed validation failed:\n- " + "\n- ".join(errors))


def write_feed(path: Path, feed: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(feed, ensure_ascii=False, indent=2) + "\n"
    path.write_text(text, encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--issue", type=Path, required=True, help="gh issue view --json output")
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--feed", type=Path, required=True)
    parser.add_argument(
        "--now",
        help="UTC timestamp for tests, e.g. 2026-10-19T12:00:00Z (default: now)",
    )
    args = parser.parse_args(argv)

    try:
        now = (
            datetime.strptime(args.now, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            if args.now
            else datetime.now(timezone.utc)
        )
        issue = json.loads(args.issue.read_text(encoding="utf-8"))
        if not isinstance(issue, dict):
            raise NoticeError("issue JSON must be an object")
        sources = load_sources(args.sources)
        notice = parse_issue(issue, sources)
        job = build_job(notice, now)
        feed = load_feed(args.feed, now)
        outcome = upsert(feed, job)
        if outcome == "added":
            feed["updated_at"] = (
                now.astimezone(timezone.utc).replace(microsecond=0).strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                )
            )
            validate_feed(feed, now)
            write_feed(args.feed, feed)
    except (NoticeError, OSError, json.JSONDecodeError) as error:
        print(f"[error] {error}", file=sys.stderr)
        return 2

    print(f"[info] {outcome}: {job['id']} -> {args.feed}")
    print(f"[info] notice_url: {job['notice_url']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
