#!/usr/bin/env python3
"""Find NEW notice links on approved official listing pages.

This script only discovers. It never writes to the app feed and never claims a
notice was reviewed. A human checks each reported notice and decides what, if
anything, goes into the feed (see docs/REAL_DATA_RUNBOOK.md).

Behaviour:
  * Reads ops/notice_sources.json (approved listing pages + allowed domains).
  * Fetches each page over HTTPS with a timeout and a size cap.
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
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from datetime import date
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlsplit, urlunsplit

USER_AGENT = "KarmopathNoticeDiscovery/1.0 (+https://github.com/Keshab1997/karmopath)"
MAX_BYTES = 2_000_000
TIMEOUT_SECONDS = 30

NOTICE_PATTERN = re.compile(
    r"notice|announcement|advt|advertisement|notification|recruitment|"
    r"examination|vacancy|answer key|result|admit card|\bCEN\b|apply",
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


def normalise_url(base: str, href: str) -> str | None:
    """Resolve href against the page URL. Returns None unless it is plain HTTPS."""
    absolute = urljoin(base, href.strip())
    parts = urlsplit(absolute)
    if parts.scheme != "https" or not parts.hostname:
        return None
    # Drop fragments: the same document must not count as two notices.
    return urlunsplit((parts.scheme, parts.netloc, parts.path, parts.query, ""))


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


def fetch_html(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        if response.status != 200:
            raise RuntimeError(f"HTTP {response.status}")
        body = response.read(MAX_BYTES + 1)
    if len(body) > MAX_BYTES:
        raise RuntimeError("page larger than size cap")
    return body.decode("utf-8", errors="replace")


def load_seen(path: Path) -> dict[str, str] | None:
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--seen", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--max-new", type=int, default=20)
    args = parser.parse_args(argv)

    config = json.loads(args.sources.read_text(encoding="utf-8"))
    seen = load_seen(args.seen)
    baseline = seen is None
    seen = dict(seen or {})
    today = date.today().isoformat()

    current: dict[str, dict[str, str]] = {}
    failures: list[str] = []
    for source in config["sources"]:
        try:
            html = fetch_html(source["url"])
        except Exception as error:  # noqa: BLE001 - reported, not hidden
            failures.append(f"{source['name']}: {error}")
            print(f"[warn] {source['name']}: {error}", file=sys.stderr)
            continue
        notices = extract_notices(source["url"], html, source["allowed_domains"])
        print(f"[info] {source['name']}: {len(notices)} notice-like link(s)")
        for url, title in notices.items():
            current[url] = {"source": source["name"], "title": title}

    if not current and len(failures) == len(config["sources"]):
        print("[error] no source could be fetched", file=sys.stderr)
        return 1

    new_items = [
        {"url": url, **info}
        for url, info in current.items()
        if url not in seen
    ]

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
    print(f"[info] new notices reported: {len(new_items)}" + (" (truncated)" if truncated else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
