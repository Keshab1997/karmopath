#!/usr/bin/env python3
"""Offline validator for Karmopath candidate feeds (contract v1).

This command intentionally performs no network requests and writes no files.
It validates structure and timestamps; it cannot establish that a source is
official or that a human actually reviewed its contents.
"""

from __future__ import annotations

import argparse
from datetime import date, datetime, timedelta, timezone
import ipaddress
import json
from pathlib import Path
import re
import sys
from typing import Any
from urllib.parse import urlsplit

KINDS = {"recruitment", "result", "admit_card", "notice"}
CATEGORIES = {"police", "railway", "banking", "teaching", "medical", "office", "other"}
STATUSES = {"open", "closed", "withdrawn", "published"}
ID_RE = re.compile(r"^[a-z0-9-]{1,100}$")
UTC_TIMESTAMP_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$")
BAD_PERCENT_ESCAPE_RE = re.compile(r"%(?![0-9a-fA-F]{2})")
HTML_RE = re.compile(r"</?[a-z][^>]*>", re.IGNORECASE)

REQUIRED_JOB_FIELDS = {
    "id", "kind", "title_bn", "title_en", "organization", "category",
    "districts", "qualifications", "status", "source_url", "notice_url",
    "reviewed_at", "published_at", "updated_at", "summary_bn", "summary_en",
    "how_to_apply_bn", "how_to_apply_en", "vacancies", "application_start_date",
    "application_end_date", "application_end_at", "exam_date", "apply_url",
    "age_note_bn", "age_note_en",
}
REQUIRED_TEXT = {
    "title_bn", "title_en", "organization", "summary_bn", "summary_en",
    "how_to_apply_bn", "how_to_apply_en",
}
OPTIONAL_TEXT = {"age_note_bn", "age_note_en"}
REQUIRED_TIMESTAMPS = {"reviewed_at", "published_at", "updated_at"}
DATE_FIELDS = {"application_start_date", "application_end_date", "exam_date"}


def _error(errors: list[str], path: str, message: str) -> None:
    errors.append(f"{path}: {message}")


def _utc_timestamp(value: Any, path: str, errors: list[str]) -> datetime | None:
    if not isinstance(value, str) or UTC_TIMESTAMP_RE.fullmatch(value) is None:
        _error(errors, path, "must be an ISO 8601 UTC timestamp ending in Z")
        return None
    try:
        parsed = datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError:
        _error(errors, path, "must be a valid ISO 8601 UTC timestamp")
        return None
    if parsed.tzinfo is None or parsed.utcoffset() != timedelta(0):
        _error(errors, path, "must be UTC")
        return None
    return parsed.astimezone(timezone.utc)


def _date_value(value: Any, path: str, errors: list[str]) -> date | None:
    if value is None:
        return None
    if not isinstance(value, str):
        _error(errors, path, "must be a YYYY-MM-DD date or null")
        return None
    try:
        parsed = date.fromisoformat(value)
    except ValueError:
        _error(errors, path, "must be a valid YYYY-MM-DD date or null")
        return None
    if parsed.isoformat() != value:
        _error(errors, path, "must use canonical YYYY-MM-DD format")
        return None
    return parsed


def _https_url(value: Any, path: str, errors: list[str], *, nullable: bool = False) -> None:
    if value is None and nullable:
        return
    if (not isinstance(value, str) or not value.strip() or any(ch.isspace() for ch in value)
            or "\\" in value or BAD_PERCENT_ESCAPE_RE.search(value)):
        _error(errors, path, "must be an HTTPS URL" + (" or null" if nullable else ""))
        return
    try:
        parts = urlsplit(value)
        host = parts.hostname
        # Accessing .port validates both numeric syntax and the 0..65535 range.
        port = parts.port
    except ValueError:
        _error(errors, path, "must be a valid HTTPS URL")
        return
    if not parts.netloc or parts.netloc.endswith(":"):
        _error(errors, path, "must be a valid HTTPS URL with a host and valid port")
        return
    if parts.scheme.lower() != "https" or not host or parts.username is not None or parts.password is not None:
        _error(errors, path, "must be an HTTPS URL without embedded credentials")
        return
    try:
        if ":" in host:
            ipaddress.IPv6Address(host)
        else:
            ascii_host = host.encode("idna").decode("ascii").rstrip(".")
            labels = ascii_host.split(".")
            if (not ascii_host or len(ascii_host) > 253
                    or any(not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label) for label in labels)):
                raise ValueError("invalid hostname")
            if re.fullmatch(r"[0-9.]+", ascii_host):
                ipaddress.IPv4Address(ascii_host)
    except (UnicodeError, ValueError):
        _error(errors, path, "must be a valid HTTPS URL with a valid host")
        return
    if port is not None and not 1 <= port <= 65535:
        _error(errors, path, "port must be between 1 and 65535")


def validate_job(job: Any, path: str = "jobs[0]", now: datetime | None = None) -> list[str]:
    """Return field-path validation errors for a single v1 job."""
    errors: list[str] = []
    if not isinstance(job, dict):
        return [f"{path}: must be an object"]

    for key in sorted(REQUIRED_JOB_FIELDS - job.keys()):
        _error(errors, f"{path}.{key}", "required field is missing")

    job_id = job.get("id")
    if not isinstance(job_id, str) or ID_RE.fullmatch(job_id) is None:
        _error(errors, f"{path}.id", "must match [a-z0-9-] and be 1–100 characters")

    for key in sorted(REQUIRED_TEXT):
        value = job.get(key)
        allow_empty = key.startswith("how_to_apply_")
        if not isinstance(value, str) or (not allow_empty and not value.strip()):
            _error(errors, f"{path}.{key}", "must be a non-empty string" if not allow_empty else "must be a string")
        elif HTML_RE.search(value):
            _error(errors, f"{path}.{key}", "HTML markup is not allowed")

    for key in sorted(OPTIONAL_TEXT):
        value = job.get(key)
        if value is not None and not isinstance(value, str):
            _error(errors, f"{path}.{key}", "must be a string or null")
        elif isinstance(value, str) and HTML_RE.search(value):
            _error(errors, f"{path}.{key}", "HTML markup is not allowed")

    for key, allowed in (("kind", KINDS), ("category", CATEGORIES), ("status", STATUSES)):
        value = job.get(key)
        if not isinstance(value, str) or value not in allowed:
            _error(errors, f"{path}.{key}", "has an unknown value")

    for key in ("districts", "qualifications"):
        value = job.get(key)
        if not isinstance(value, list) or any(not isinstance(item, str) or not item.strip() for item in value):
            _error(errors, f"{path}.{key}", "must be an array of non-empty strings")

    _https_url(job.get("source_url"), f"{path}.source_url", errors)
    _https_url(job.get("notice_url"), f"{path}.notice_url", errors)
    _https_url(job.get("apply_url"), f"{path}.apply_url", errors, nullable=True)

    timestamps: dict[str, datetime] = {}
    for key in sorted(REQUIRED_TIMESTAMPS):
        parsed = _utc_timestamp(job.get(key), f"{path}.{key}", errors)
        if parsed is not None:
            timestamps[key] = parsed
    end_at = job.get("application_end_at")
    if end_at is not None:
        parsed = _utc_timestamp(end_at, f"{path}.application_end_at", errors)
        if parsed is not None:
            timestamps["application_end_at"] = parsed

    for key in sorted(DATE_FIELDS):
        _date_value(job.get(key), f"{path}.{key}", errors)
    start_date = _date_value(job.get("application_start_date"), f"{path}.application_start_date", [])
    end_date = _date_value(job.get("application_end_date"), f"{path}.application_end_date", [])
    if start_date is not None and end_date is not None and start_date > end_date:
        _error(errors, f"{path}.application_start_date", "must not be after application_end_date")

    vacancies = job.get("vacancies")
    if vacancies is not None and (type(vacancies) is not int or vacancies < 0):
        _error(errors, f"{path}.vacancies", "must be a non-negative integer or null")

    if "updated_at" in timestamps and "published_at" in timestamps:
        if timestamps["updated_at"] < timestamps["published_at"]:
            _error(errors, f"{path}.updated_at", "must be at or after published_at")
    if "reviewed_at" in timestamps and "updated_at" in timestamps:
        if timestamps["reviewed_at"] > timestamps["updated_at"]:
            _error(errors, f"{path}.reviewed_at", "must be at or before updated_at")

    clock = now or datetime.now(timezone.utc)
    if clock.tzinfo is None:
        clock = clock.replace(tzinfo=timezone.utc)
    tolerance = clock.astimezone(timezone.utc) + timedelta(minutes=5)
    for key in ("reviewed_at", "published_at"):
        if key in timestamps and timestamps[key] > tolerance:
            _error(errors, f"{path}.{key}", "must not be more than 5 minutes in the future")

    kind = job.get("kind")
    status = job.get("status")
    if kind == "recruitment" and status == "open" and job.get("application_end_date") is None:
        _error(errors, f"{path}.application_end_date", "is required for open recruitment")
    if isinstance(kind, str) and kind in {"result", "admit_card", "notice"} and isinstance(status, str) and status in {"open", "closed"}:
        _error(errors, f"{path}.status", "result/admit_card/notice must use published or withdrawn")

    return errors


def validate_feed(feed: Any, now: datetime | None = None) -> list[str]:
    """Return all discoverable envelope, job, and duplicate-ID errors."""
    if not isinstance(feed, dict):
        return ["feed: must be an object"]
    errors: list[str] = []
    if feed.get("schema_version") != 1 or type(feed.get("schema_version")) is not int:
        _error(errors, "schema_version", "must be integer 1")
    feed_time = _utc_timestamp(feed.get("updated_at"), "updated_at", errors)
    jobs = feed.get("jobs")
    if not isinstance(jobs, list):
        _error(errors, "jobs", "must be an array")
        return errors

    seen: set[str] = set()
    for index, job in enumerate(jobs):
        path = f"jobs[{index}]"
        errors.extend(validate_job(job, path, now))
        if isinstance(job, dict):
            job_id = job.get("id")
            if isinstance(job_id, str):
                if job_id in seen:
                    _error(errors, f"{path}.id", f"duplicate id {job_id!r}")
                seen.add(job_id)
    # The envelope timestamp is parsed for format/UTC validation above. The feed
    # contract does not impose ordering against individual job timestamps.
    del feed_time
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate a Karmopath v1 candidate feed offline")
    parser.add_argument("candidate", type=Path, help="candidate JSON file")
    args = parser.parse_args(argv)
    try:
        raw = args.candidate.read_text(encoding="utf-8")
    except UnicodeError as exc:
        print(f"candidate: input is not valid UTF-8: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"candidate: cannot read file: {exc}", file=sys.stderr)
        return 1
    try:
        feed = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"JSON: invalid JSON at line {exc.lineno}, column {exc.colno}: {exc.msg}", file=sys.stderr)
        return 1
    errors = validate_feed(feed)
    if errors:
        print("INVALID candidate feed:")
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"VALID candidate feed: {len(feed['jobs'])} job(s); structure only, source verification remains human review.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
