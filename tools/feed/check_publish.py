#!/usr/bin/env python3
"""Offline publish-readiness checklist for Karmopath candidate feeds (contract v1).

This command never forks the frozen validator rules: it first runs
``validate.validate_feed`` from ``tools/feed/validate.py`` unchanged, then adds
these publication-readiness checks per job:

- ``source_url`` and ``notice_url`` are nonempty, absolute HTTPS URLs without
  embedded credentials and without a fragment (the fragment rule is additive;
  the other link rules are reused from the validator);
- ``published_at`` is present, a valid UTC timestamp, and not in the future
  beyond the contract's documented 5-minute clock tolerance (the same
  tolerance the validator applies);
- ``districts`` and ``qualifications`` carry at least one entry where
  applicable. Missing/empty arrays are reported as warnings; ``--strict``
  turns warnings into failures. The validator alone still owns every other
  rule, so an empty array never silently passes here.

The command is offline and read-only: no network requests, no file writes, no
upload, no publication. Exit 0 only when validation and every failing
checklist item pass. A passing result proves structure and readiness signals
only; it cannot establish that a source is official or that a human verified
dates and eligibility. Human source/date verification and owner-authorized
publication remain separate manual steps.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sys
from typing import Any
from urllib.parse import urlsplit

import validate

FUTURE_TOLERANCE = timedelta(minutes=5)
LINK_FIELDS = ("source_url", "notice_url")
WARN_LIST_FIELDS = ("districts", "qualifications")
PASS = "PASS"
FAIL = "FAIL"
WARN = "WARN"


@dataclass(frozen=True)
class CheckItem:
    """One deterministic checklist line for one job field."""

    path: str
    job_id: str
    field: str
    status: str
    detail: str

    def render(self) -> str:
        return f"[{self.status}] {self.path} (id={self.job_id}) {self.field}: {self.detail}"


def _job_id(job: dict[str, Any]) -> str:
    value = job.get("id")
    if isinstance(value, str) and value:
        return value
    return "(missing id)"


def _check_link(job: dict[str, Any], field: str, path: str) -> CheckItem:
    value = job.get(field)
    if value is None:
        return CheckItem(path, _job_id(job), field, FAIL,
                         "is null or missing; publication requires a nonempty absolute HTTPS URL")
    if not isinstance(value, str) or not value.strip():
        return CheckItem(path, _job_id(job), field, FAIL,
                         "is empty; publication requires a nonempty absolute HTTPS URL")
    # Reuse the validator's exact HTTPS/host/credential rules; never fork them.
    errors: list[str] = []
    validate._https_url(value, field, errors)
    if errors:
        detail = errors[0].split(": ", 1)[1] if ": " in errors[0] else errors[0]
        return CheckItem(path, _job_id(job), field, FAIL, f"{detail} (absolute HTTPS required)")
    if urlsplit(value).fragment:
        return CheckItem(path, _job_id(job), field, FAIL,
                         "must not contain a fragment (#...); link to the page itself")
    return CheckItem(path, _job_id(job), field, PASS, "nonempty absolute HTTPS, no credentials, no fragment")


def _check_published_at(job: dict[str, Any], path: str, now: datetime) -> CheckItem:
    value = job.get("published_at")
    if value is None:
        return CheckItem(path, _job_id(job), "published_at", FAIL,
                         "is missing; the actual publication time must be set before publication review")
    errors: list[str] = []
    parsed = validate._utc_timestamp(value, "published_at", errors)
    if errors:
        detail = errors[0].split(": ", 1)[1] if ": " in errors[0] else errors[0]
        return CheckItem(path, _job_id(job), "published_at", FAIL, detail)
    if parsed > now + FUTURE_TOLERANCE:
        return CheckItem(path, _job_id(job), "published_at", FAIL,
                         f"is in the future ({value}); must not be ahead of now beyond the 5-minute clock tolerance")
    return CheckItem(path, _job_id(job), "published_at", PASS,
                     "present and not in the future (5-minute clock tolerance)")


def _check_nonempty_list(job: dict[str, Any], field: str, path: str) -> CheckItem | None:
    value = job.get(field)
    if isinstance(value, list) and not value:
        return CheckItem(path, _job_id(job), field, WARN,
                         'is empty; add at least one entry where applicable (statewide uses the literal "West Bengal")')
    return None


def checklist_for_job(job: Any, index: int, now: datetime) -> list[CheckItem]:
    """Checklist items for one job; structurally invalid jobs are left to the validator."""
    if not isinstance(job, dict):
        return []
    path = f"jobs[{index}]"
    items = [
        _check_link(job, "source_url", f"{path}.source_url"),
        _check_link(job, "notice_url", f"{path}.notice_url"),
        _check_published_at(job, f"{path}.published_at", now),
    ]
    for field in WARN_LIST_FIELDS:
        item = _check_nonempty_list(job, field, f"{path}.{field}")
        if item is not None:
            items.append(item)
    return items


def run_checklist(feed: Any, now: datetime) -> tuple[list[CheckItem], int]:
    """Return (items, number of job objects checked) for a parsed feed."""
    jobs = feed.get("jobs") if isinstance(feed, dict) else None
    if not isinstance(jobs, list):
        return [], 0
    items: list[CheckItem] = []
    checked = 0
    for index, job in enumerate(jobs):
        if isinstance(job, dict):
            checked += 1
        items.extend(checklist_for_job(job, index, now))
    return items, checked


def _counts(items: list[CheckItem]) -> tuple[int, int, int]:
    passed = sum(1 for item in items if item.status == PASS)
    failed = sum(1 for item in items if item.status == FAIL)
    warned = sum(1 for item in items if item.status == WARN)
    return passed, failed, warned


def _parse_now(value: str | None) -> datetime | None:
    """Parse --now with the validator's own timestamp rule; None on error."""
    if value is None:
        return datetime.now(timezone.utc)
    errors: list[str] = []
    parsed = validate._utc_timestamp(value, "--now", errors)
    return parsed


def _load_feed(path: Path) -> tuple[Any, str | None]:
    """Read and parse the candidate file; mirror validate.py's error style."""
    try:
        raw = path.read_text(encoding="utf-8")
    except UnicodeError as exc:
        return None, f"candidate: input is not valid UTF-8: {exc}"
    except OSError as exc:
        return None, f"candidate: cannot read file: {exc}"
    try:
        return json.loads(raw), None
    except json.JSONDecodeError as exc:
        return None, f"JSON: invalid JSON at line {exc.lineno}, column {exc.colno}: {exc.msg}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Offline publish-readiness checklist: validate.py rules plus additive "
                    "source/notice/published_at/districts checks; no network, no upload.")
    parser.add_argument("candidate", type=Path, help="candidate JSON file")
    parser.add_argument("--now", type=str, default=None,
                        help="ISO 8601 UTC instant ending in Z used as the current time (deterministic runs)")
    parser.add_argument("--strict", action="store_true",
                        help="treat checklist warnings (empty districts/qualifications) as failures")
    args = parser.parse_args(argv)

    now = _parse_now(args.now)
    if now is None:
        print("--now: must be an ISO 8601 UTC timestamp ending in Z", file=sys.stderr)
        return 1

    feed, load_error = _load_feed(args.candidate)
    if load_error is not None:
        print(load_error, file=sys.stderr)
        return 1

    validation_errors = validate.validate_feed(feed, now)
    items, checked = run_checklist(feed, now)
    passed, failed, warned = _counts(items)

    print(f"PUBLISH CHECKLIST (offline): {args.candidate}")
    if validation_errors:
        print(f"VALIDATION: FAIL ({len(validation_errors)} error(s) under unchanged tools/feed/validate.py rules)")
        for error in validation_errors:
            print(f"- {error}")
    else:
        print(f"VALIDATION: PASS ({checked} job(s) accepted by tools/feed/validate.py; structure only)")
    print("CHECKLIST (additive publication-readiness checks):")
    if items:
        for item in items:
            print(f"- {item.render()}")
    else:
        print("- (no per-job checklist items; feed exposes no jobs array)")
    summary = f"checklist summary: {passed} passed, {failed} failed, {warned} warning(s) across {checked} job(s)"
    if args.strict and warned:
        summary += "; --strict treats warning(s) as failure(s)"
    print(summary)
    if validation_errors or failed or (args.strict and warned):
        reasons = []
        if validation_errors:
            reasons.append(f"{len(validation_errors)} validation error(s)")
        if failed:
            reasons.append(f"{failed} failed checklist item(s)")
        if args.strict and warned:
            reasons.append(f"{warned} warning(s) under --strict")
        print(f"RESULT: NOT READY — fix {' and '.join(reasons)} before human publication review.")
        return 1
    print("RESULT: READY for human publication review — offline signals pass; official-source authenticity, "
          "notice contents, and dates still require human verification, and publication itself stays a separate "
          "owner-authorized step.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
