#!/usr/bin/env python3
"""Find NEW notice links on approved official listing pages.

This script only discovers. It never writes to the app feed and never claims a
notice was reviewed. A human checks each reported notice and decides what, if
anything, goes into the feed (see docs/REAL_DATA_RUNBOOK.md).

Behaviour:
  * Reads ops/notice_sources.json (approved listing pages + allowed domains).
  * Fetches each page over HTTPS with a timeout and a size cap, retrying with
    a backoff and falling back to the source's `alternates` when the primary
    URL keeps failing (WBPSC times out from some networks; see
    docs/REAL_DATA_RUNBOOK.md).
  * Keeps <a> links whose visible text looks like a notice and whose target is
    on an allowed domain.
  * Compares against ops/notice_seen.json. Unseen links are reported.
  * If the seen file does not exist yet, the first run is a BASELINE: every
    current link is recorded and nothing is reported, so the first run does not
    flood the issue tracker with old notices.
  * Exits non-zero when no source could be fetched, so a broken site is not
    mistaken for "no new notices".

Usage:
  python3 scripts/discover_notices.py \
      --sources ops/notice_sources.json --seen ops/notice_seen.json \
      --out new_notices.json --max-new 20

  # Human triage of what is live right now, including links an earlier run
  # already recorded. Nothing is written to the seen file and nothing is
  # published: the output is a candidate list for a person to approve.
  python3 scripts/discover_notices.py \
      --sources ops/notice_sources.json --seen ops/notice_seen.json \
      --out candidates.json --report-candidates
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.request
from datetime import date
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlsplit, urlunsplit

USER_AGENT = "KarmopathNoticeDiscovery/1.0 (+https://github.com/Keshab1997/karmopath)"
MAX_BYTES = 2_000_000
TIMEOUT_SECONDS = 30
# Government listing sites are intermittently slow from GitHub-hosted runners
# (WBPSC timed out on every scheduled run of 2026-10-19/20). A single attempt
# turns a slow site into "no new notices", which is the failure mode this
# script must never report as success. Two retries with a short backoff cost
# seconds when the site is fine and recover most transient timeouts.
ATTEMPTS = 3
BACKOFF_SECONDS = 2.0
# Indirect so tests can run the retry loop without real sleeping.
SLEEP = time.sleep

NOTICE_PATTERN = re.compile(
    r"notice|announcement|advt|advertisement|notification|recruitment|"
    r"examination|vacancy|answer key|result|admit card|\bCEN\b|apply|"
    # Added after the 2026-10-20 review of the live listing pages: WBSSC and
    # RRC-ER title their stage documents this way, and a miss here means the
    # link is never recorded, so it can never be proposed for review.
    r"merit list|waiting list|wait ?list|panel|intimation|call letter|"
    r"interview|counselling|counseling|schedule|cut[ -]?off|"
    r"document verification|grievance|corrigendum|provisional|short ?list",
    re.IGNORECASE,
)


class _AnchorCollector(HTMLParser):
    """Collects (href, visible text) for every <a href> element."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.links: list[tuple[str, str]] = []
        self._href: str | None = None
        self._text: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            href = dict(attrs).get("href")
            if href:
                self._href = href
                self._text = []

    def handle_data(self, data):
        if self._href is not None:
            self._text.append(data)

    def handle_endtag(self, tag):
        if tag == "a" and self._href is not None:
            text = " ".join("".join(self._text).split())
            self.links.append((self._href, text))
            self._href = None


def encode_url_spaces(url: str) -> str:
    """Percent-encode literal spaces in the path and query.

    Official listing pages link PDFs whose filenames contain spaces (RRC-ER
    does this heavily). A raw space is rejected by the feed validator and by
    the publisher's link checks, so the discovery output must be launchable.
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


def normalise_url(base: str, href: str) -> str | None:
    """Resolve href against the page URL. Returns None unless it is plain HTTPS."""
    absolute = urljoin(base, href.strip())
    parts = urlsplit(absolute)
    if parts.scheme != "https" or not parts.hostname:
        return None
    # Drop fragments: the same document must not count as two notices.
    return encode_url_spaces(
        urlunsplit((parts.scheme, parts.netloc, parts.path, parts.query, ""))
    )


def host_allowed(url: str, allowed_domains: list[str]) -> bool:
    host = (urlsplit(url).hostname or "").lower()
    return any(host == d or host.endswith("." + d) for d in allowed_domains)


def extract_notices(
    base_url: str, html: str, allowed_domains: list[str]
) -> dict[str, str]:
    """Return {absolute_url: title} for notice-like links on allowed domains."""
    collector = _AnchorCollector()
    collector.feed(html)
    found: dict[str, str] = {}
    for href, text in collector.links:
        if len(text) < 10 or not NOTICE_PATTERN.search(text):
            continue
        url = normalise_url(base_url, href)
        if url is None or not host_allowed(url, allowed_domains):
            continue
        found.setdefault(url, text[:300])
    return found


def fetch_html(url: str, timeout: float = TIMEOUT_SECONDS) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        if response.status != 200:
            raise RuntimeError(f"HTTP {response.status}")
        body = response.read(MAX_BYTES + 1)
    if len(body) > MAX_BYTES:
        raise RuntimeError("page larger than size cap")
    return body.decode("utf-8", errors="replace")


def fetch_html_with_retry(
    url: str,
    *,
    attempts: int = ATTEMPTS,
    timeout: float = TIMEOUT_SECONDS,
    backoff: float = BACKOFF_SECONDS,
) -> str:
    """Fetch one URL, retrying transient failures. Never returns partial data.

    A listing page that is merely slow must not be reported as "no new
    notices": the last error is re-raised with the attempt count so the
    failure issue says what was actually tried.
    """
    if attempts < 1:
        raise ValueError("attempts must be at least 1")
    last: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            return fetch_html(url, timeout)
        except Exception as error:  # noqa: BLE001 - reported, not hidden
            last = error
            if attempt < attempts:
                SLEEP(backoff * attempt)
    raise RuntimeError(f"{last} (after {attempts} attempt(s))")


def source_urls(source: dict) -> list[str]:
    """Primary listing URL first, then any human-verified alternates."""
    urls = [source["url"]]
    alternates = source.get("alternates")
    if isinstance(alternates, list):
        urls.extend(str(url) for url in alternates)
    return urls


def fetch_source_html(
    source: dict,
    *,
    attempts: int = ATTEMPTS,
    timeout: float = TIMEOUT_SECONDS,
    backoff: float = BACKOFF_SECONDS,
) -> tuple[str, str]:
    """Return (html, url_used), falling through the source's alternates.

    Returns the first listing page that answers. Only when every URL for the
    source has exhausted its retries does this raise, so one slow mirror cannot
    hide a working site.
    """
    errors: list[str] = []
    for url in source_urls(source):
        try:
            return fetch_html_with_retry(
                url, attempts=attempts, timeout=timeout, backoff=backoff
            ), url
        except Exception as error:  # noqa: BLE001 - collected and reported
            errors.append(f"{url}: {error}")
    raise RuntimeError("; ".join(errors))


def load_seen(path: Path) -> dict[str, str] | None:
    """Load the seen map, migrating older keys that contain raw spaces.

    The first discovery run recorded links exactly as the listing page wrote
    them, including spaces in PDF filenames. New runs compare encoded URLs, so
    the old keys are normalised on read; otherwise every such link would look
    new once and flood the issue tracker.
    """
    if not path.exists():
        return None
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError("seen file must be a JSON object")
    seen: dict[str, str] = {}
    for url, day in raw.items():
        if isinstance(url, str) and isinstance(day, str):
            seen[encode_url_spaces(url)] = day
    return seen


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--seen", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--max-new", type=int, default=20)
    parser.add_argument(
        "--source",
        default="",
        help="limit the run to approved sources whose name contains this text",
    )
    parser.add_argument("--timeout", type=float, default=TIMEOUT_SECONDS)
    parser.add_argument("--retries", type=int, default=ATTEMPTS)
    parser.add_argument("--backoff", type=float, default=BACKOFF_SECONDS)
    parser.add_argument(
        "--report-candidates",
        action="store_true",
        help="report every live notice link with a seen flag; publish nothing "
        "and do not touch the seen file",
    )
    parser.add_argument(
        "--seed",
        action="store_true",
        help="record every live notice link as seen and report nothing",
    )
    args = parser.parse_args(argv)

    config = json.loads(args.sources.read_text(encoding="utf-8"))
    selected = [
        source
        for source in config.get("sources", [])
        if not args.source
        or args.source.lower() in str(source.get("name", "")).lower()
    ]
    if not selected:
        print(f"[error] no approved source matches {args.source!r}", file=sys.stderr)
        return 1

    seen = load_seen(args.seen)
    baseline = seen is None
    seen = dict(seen or {})
    today = date.today().isoformat()

    current: dict[str, dict[str, str]] = {}
    failures: list[str] = []
    for source in selected:
        try:
            html, url_used = fetch_source_html(
                source,
                attempts=args.retries,
                timeout=args.timeout,
                backoff=args.backoff,
            )
        except Exception as error:  # noqa: BLE001 - reported, not hidden
            failures.append(f"{source['name']}: {error}")
            print(f"[warn] {source['name']}: {error}", file=sys.stderr)
            continue
        if url_used != source["url"]:
            print(f"[info] {source['name']}: recovered via alternate {url_used}")
        notices = extract_notices(url_used, html, source["allowed_domains"])
        print(f"[info] {source['name']}: {len(notices)} notice-like link(s)")
        for url, title in notices.items():
            current[url] = {"source": source["name"], "title": title}

    if not current and len(failures) == len(selected):
        print("[error] no source could be fetched", file=sys.stderr)
        return 1

    if args.seed:
        # A source that has only just become reachable would otherwise open one
        # issue per historic link. --seed records the current listing and
        # reports nothing; backfilling a specific old notice stays a human
        # decision (see scripts/notice_proposals.py).
        seen.update({url: today for url in current})
        args.seen.parent.mkdir(parents=True, exist_ok=True)
        args.seen.write_text(
            json.dumps(seen, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        args.out.write_text(
            json.dumps(
                {
                    "new": [],
                    "truncated": False,
                    "failures": failures,
                    "seeded": len(current),
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        print(f"[info] seeded {len(current)} live link(s); reported none")
        return 0

    new_items = [
        {"url": url, **info}
        for url, info in current.items()
        if url not in seen
    ]

    if args.report_candidates:
        # Human triage output, not a publication: the whole live listing with a
        # seen flag, and the seen file is left untouched so a triage run can
        # never silently mark old notices as already reported.
        candidates = [
            {
                "url": url,
                "title": info["title"],
                "source": info["source"],
                "seen_on": seen.get(url),
                "is_new": url not in seen,
            }
            for url, info in current.items()
        ]
        truncated = len(candidates) > args.max_new
        args.out.write_text(
            json.dumps(
                {
                    "candidates": candidates[: args.max_new],
                    "total_live": len(candidates),
                    "truncated": truncated,
                    "failures": failures,
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        fresh = sum(1 for item in candidates if item["is_new"])
        print(
            f"[info] live notice links: {len(candidates)} ({fresh} unseen)"
            + (" (truncated)" if truncated else "")
        )
        return 0

    for item in new_items:
        seen[item["url"]] = today
    args.seen.parent.mkdir(parents=True, exist_ok=True)
    args.seen.write_text(
        json.dumps(seen, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    if baseline:
        print(f"[info] baseline run: recorded {len(current)} link(s), reporting none")
        new_items = []

    truncated = len(new_items) > args.max_new
    new_items = new_items[: args.max_new]
    args.out.write_text(
        json.dumps(
            {"new": new_items, "truncated": truncated, "failures": failures},
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(
        f"[info] new notices reported: {len(new_items)}"
        + (" (truncated)" if truncated else "")
    )
    return 0



if __name__ == "__main__":
    raise SystemExit(main())
