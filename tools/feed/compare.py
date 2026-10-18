#!/usr/bin/env python3
"""Offline structural and editorial comparison for published/candidate feeds.

This tool only reads two local JSON files. It never uploads, publishes, or
modifies either input. A passing comparison is not source/authenticity approval.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal
import json
from pathlib import Path
import sys
from typing import Any

import validate

EDITORIAL_TIMESTAMP_FIELDS = {"reviewed_at", "updated_at"}
UTC_TIMESTAMP_FIELDS = {"reviewed_at", "updated_at", "published_at", "application_end_at"}


@dataclass
class Comparison:
    baseline_count: int = 0
    candidate_count: int = 0
    added: list[tuple[str, str]] = field(default_factory=list)
    unchanged: list[tuple[str, tuple[str, ...]]] = field(default_factory=list)
    changed: list[tuple[str, tuple[str, ...]]] = field(default_factory=list)
    withdrawn: list[tuple[str, tuple[str, ...]]] = field(default_factory=list)
    missing: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    @property
    def accepted(self) -> bool:
        return not self.errors


def _instant(value: str) -> tuple[datetime, Decimal]:
    """Parse a validated UTC timestamp without losing sub-microsecond precision."""
    whole, separator, fraction_and_z = value.partition(".")
    second_text = whole if separator else whole[:-1]
    second = datetime.fromisoformat(second_text + "+00:00").astimezone(timezone.utc)
    fraction = Decimal("0." + fraction_and_z[:-1]) if separator else Decimal(0)
    return second, fraction


def _same_field(field_name: str, left: Any, right: Any) -> bool:
    if field_name in UTC_TIMESTAMP_FIELDS:
        if left is None or right is None:
            return left is right
        return _instant(left) == _instant(right)
    # Python equality conflates JSON true with 1, even inside nested values.
    # Canonical serialization retains JSON types while ignoring object order.
    return json.dumps(left, sort_keys=True, ensure_ascii=True) == json.dumps(
        right, sort_keys=True, ensure_ascii=True
    )


def _safe_count(feed: Any) -> int:
    jobs = feed.get("jobs") if isinstance(feed, dict) else None
    return len(jobs) if isinstance(jobs, list) else 0


def compare_feeds(baseline: Any, candidate: Any, now: datetime | None = None) -> Comparison:
    """Validate and compare two schema-v1 feed objects without mutating them."""
    result = Comparison(baseline_count=_safe_count(baseline), candidate_count=_safe_count(candidate))
    baseline_errors = validate.validate_feed(baseline, now)
    candidate_errors = validate.validate_feed(candidate, now)
    if baseline_errors or candidate_errors:
        result.errors.extend(f"baseline: {error}" for error in baseline_errors)
        result.errors.extend(f"candidate: {error}" for error in candidate_errors)
        result.errors = sorted(set(result.errors))
        return result

    old_jobs = {job["id"]: job for job in baseline["jobs"]}
    new_jobs = {job["id"]: job for job in candidate["jobs"]}
    old_ids = set(old_jobs)
    new_ids = set(new_jobs)
    result.missing = sorted(old_ids - new_ids)
    added_ids = sorted(new_ids - old_ids)

    if _instant(candidate["updated_at"]) < _instant(baseline["updated_at"]):
        result.errors.append("updated_at: candidate envelope timestamp is earlier than baseline")
    if result.missing:
        result.errors.extend(
            f"jobs[{job_id}]: prior ID is missing; retain it and mark the job closed/withdrawn instead of deleting it"
            for job_id in result.missing
        )
        if added_ids:
            result.errors.append(
                "jobs: missing prior ID(s) occur with new ID(s); possible ID replacement disguised as remove+add"
            )

    result.added = [(job_id, new_jobs[job_id]["status"]) for job_id in added_ids]

    for job_id in sorted(old_ids & new_ids):
        old = old_jobs[job_id]
        new = new_jobs[job_id]
        old_updated = _instant(old["updated_at"])
        new_updated = _instant(new["updated_at"])
        old_reviewed = _instant(old["reviewed_at"])
        new_reviewed = _instant(new["reviewed_at"])
        old_published = _instant(old["published_at"])
        new_published = _instant(new["published_at"])

        if new_updated < old_updated:
            result.errors.append(f"jobs[{job_id}].updated_at: timestamp regressed relative to baseline")
        if new_reviewed < old_reviewed:
            result.errors.append(f"jobs[{job_id}].reviewed_at: timestamp regressed relative to baseline")
        if new_published != old_published:
            result.errors.append(f"jobs[{job_id}].published_at: published_at must be preserved for an existing ID")

        keys = set(old) | set(new)
        content_changes = tuple(sorted(
            key for key in keys
            if key not in EDITORIAL_TIMESTAMP_FIELDS and (
                key not in old or key not in new or not _same_field(key, old[key], new[key])
            )
        ))
        if content_changes:
            changed_label = ", ".join(content_changes)
            if new_updated <= old_updated:
                result.errors.append(
                    f"jobs[{job_id}].updated_at: must advance for changed field(s): {changed_label}"
                )
            if new_reviewed <= old_reviewed:
                result.errors.append(
                    f"jobs[{job_id}].reviewed_at: must advance for changed field(s); a fresh human review is required: {changed_label}"
                )
            if new["status"] == "withdrawn":
                result.withdrawn.append((job_id, content_changes))
            else:
                result.changed.append((job_id, content_changes))
        else:
            timestamp_only = tuple(
                key for key, before, after in (
                    ("reviewed_at", old_reviewed, new_reviewed),
                    ("updated_at", old_updated, new_updated),
                ) if before != after
            )
            result.unchanged.append((job_id, timestamp_only))

    result.errors = sorted(set(result.errors))
    return result


def format_report(result: Comparison) -> str:
    """Render a stable ID/field-only report; never dump feed contents."""
    state = "ACCEPTED" if result.accepted else "REJECTED"
    lines = [
        f"OFFLINE COMPARISON: {state}",
        f"Baseline jobs: {result.baseline_count}; candidate jobs: {result.candidate_count}",
    ]

    def section(name: str, entries: list[str]) -> None:
        lines.append(f"{name} ({len(entries)}):")
        lines.extend(f"  - {entry}" for entry in entries)
        if not entries:
            lines.append("  - none")

    section("Added", [f"{job_id} (status={status})" for job_id, status in result.added])
    section("Unchanged", [
        f"{job_id} (timestamp-only: {', '.join(timestamps)})" if timestamps else job_id
        for job_id, timestamps in result.unchanged
    ])
    section("Changed", [f"{job_id}: {', '.join(fields)}" for job_id, fields in result.changed])
    section("Withdrawn", [
        f"{job_id}: {', '.join(fields)}" if fields else job_id
        for job_id, fields in result.withdrawn
    ])
    section("Missing IDs", result.missing)
    if result.errors:
        lines.append("Errors:")
        lines.extend(f"  - {error}" for error in result.errors)
    lines.append("No files were modified; passing is structural/comparison evidence only, not source verification or publication approval.")
    return "\n".join(lines)


def _read_feed(path: Path, label: str) -> tuple[Any | None, str | None]:
    try:
        raw = path.read_text(encoding="utf-8")
    except UnicodeError as exc:
        return None, f"{label}: input is not valid UTF-8: {exc}"
    except OSError as exc:
        return None, f"{label}: cannot read file: {exc}"
    try:
        return json.loads(raw), None
    except json.JSONDecodeError as exc:
        return None, f"{label}: invalid JSON at line {exc.lineno}, column {exc.colno}: {exc.msg}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Compare a local published-feed snapshot with a candidate feed; no publication is performed"
    )
    parser.add_argument("baseline", type=Path, help="prior published schema-v1 JSON feed")
    parser.add_argument("candidate", type=Path, help="exported candidate schema-v1 JSON feed")
    args = parser.parse_args(argv)

    baseline, baseline_error = _read_feed(args.baseline, "baseline")
    candidate, candidate_error = _read_feed(args.candidate, "candidate")
    if baseline_error or candidate_error:
        print("OFFLINE COMPARISON: REJECTED")
        for error in (baseline_error, candidate_error):
            if error:
                print(f"  - {error}")
        print("No files were modified.")
        return 1

    result = compare_feeds(baseline, candidate)
    print(format_report(result))
    return 0 if result.accepted else 1


if __name__ == "__main__":
    raise SystemExit(main())
