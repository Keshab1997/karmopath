"""Tests for the offline candidate-vs-published-feed comparison gate."""

from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "feed"))
import compare  # noqa: E402
import test_validate  # noqa: E402

NOW = datetime.now(timezone.utc).replace(microsecond=0)
BASE_TIME = NOW - timedelta(days=2)
CANDIDATE_TIME = NOW - timedelta(days=1)


def stamp(value):
    return value.strftime("%Y-%m-%dT%H:%M:%SZ")


def job(job_id="sample-recruitment-2026", **updates):
    value = test_validate.valid_job(
        id=job_id,
        reviewed_at=stamp(BASE_TIME),
        updated_at=stamp(BASE_TIME),
        published_at=stamp(BASE_TIME - timedelta(hours=1)),
    )
    value.update(updates)
    return value


def feed(*jobs, updated_at=BASE_TIME):
    updated_stamp = updated_at if isinstance(updated_at, str) else stamp(updated_at)
    return {"schema_version": 1, "updated_at": updated_stamp, "jobs": list(jobs)}


class FeedComparisonTests(unittest.TestCase):
    def test_extension_null_addition_and_removal_require_fresh_review(self):
        for old, new in ((job(), job(correction_note=None)),
                         (job(correction_note=None), job())):
            with self.subTest(old_has_field="correction_note" in old):
                result = compare.compare_feeds(feed(old), feed(new), NOW)
                self.assertFalse(result.accepted, result.errors)
                self.assertIn((old["id"], ("correction_note",)), result.changed)
                new["updated_at"] = stamp(CANDIDATE_TIME)
                new["reviewed_at"] = stamp(CANDIDATE_TIME)
                accepted = compare.compare_feeds(feed(old), feed(new, updated_at=CANDIDATE_TIME), NOW)
                self.assertTrue(accepted.accepted, accepted.errors)

    def test_json_type_changes_in_extension_fields_require_review(self):
        old = job(editorial_metadata={"flag": [True]})
        new = job(editorial_metadata={"flag": [1]})
        result = compare.compare_feeds(feed(old), feed(new), NOW)
        self.assertFalse(result.accepted, result.errors)
        self.assertIn((old["id"], ("editorial_metadata",)), result.changed)

    def test_equivalent_exact_deadline_spellings_are_unchanged(self):
        old = job(application_end_at="2026-12-01T12:00:00.100Z")
        new = job(application_end_at="2026-12-01T12:00:00.1Z")
        result = compare.compare_feeds(feed(old), feed(new), NOW)
        self.assertTrue(result.accepted, result.errors)
        self.assertEqual(result.unchanged, [(old["id"], ())])

    def test_actual_exact_deadline_fraction_change_requires_review(self):
        old = job(application_end_at="2026-12-01T12:00:00.1000001Z")
        new = job(application_end_at="2026-12-01T12:00:00.1000002Z")
        result = compare.compare_feeds(feed(old), feed(new), NOW)
        self.assertFalse(result.accepted, result.errors)
        self.assertIn((old["id"], ("application_end_at",)), result.changed)

    def test_categories_field_names_and_deterministic_report(self):
        unchanged = job("a-unchanged")
        changed = job("b-changed", title_en="Updated title")
        withdrawn = job("c-withdrawn", status="withdrawn", application_end_date=None)
        baseline = feed(job("a-unchanged"), job("b-changed"), job("c-withdrawn"), job("d-missing"))
        candidate = feed(
            job("new-job", reviewed_at=stamp(CANDIDATE_TIME), updated_at=stamp(CANDIDATE_TIME),
                published_at=stamp(CANDIDATE_TIME)),
            unchanged,
            job("b-changed", title_en="Updated title", reviewed_at=stamp(CANDIDATE_TIME),
                updated_at=stamp(CANDIDATE_TIME)),
            withdrawn,
            updated_at=CANDIDATE_TIME,
        )
        result = compare.compare_feeds(baseline, candidate, NOW)
        self.assertFalse(result.accepted)
        self.assertEqual(result.added, [("new-job", "open")])
        self.assertEqual(result.unchanged, [("a-unchanged", ())])
        self.assertEqual(result.changed, [("b-changed", ("title_en",))])
        self.assertEqual(result.withdrawn, [("c-withdrawn", ("application_end_date", "status"))])
        self.assertEqual(result.missing, ["d-missing"])
        # Missing IDs make the result invalid, while the summary remains complete.
        self.assertIn("OFFLINE COMPARISON: REJECTED", compare.format_report(result))

    def test_valid_changed_and_withdrawn_rows_are_accepted_without_missing_ids(self):
        baseline = feed(job("change-me"), job("withdraw-me"))
        candidate = feed(
            job("change-me", summary_en="A revised summary", reviewed_at=stamp(CANDIDATE_TIME),
                updated_at=stamp(CANDIDATE_TIME)),
            job("withdraw-me", status="withdrawn", application_end_date=None,
                reviewed_at=stamp(CANDIDATE_TIME), updated_at=stamp(CANDIDATE_TIME)),
            updated_at=CANDIDATE_TIME,
        )
        result = compare.compare_feeds(baseline, candidate, NOW)
        self.assertTrue(result.accepted, result.errors)
        self.assertEqual(result.changed, [("change-me", ("summary_en",))])
        self.assertEqual(result.withdrawn, [("withdraw-me", ("application_end_date", "status"))])

    def test_equal_instants_with_fractional_timestamp_spellings_are_unchanged(self):
        old = job(reviewed_at="2026-10-16T12:00:00.100Z", updated_at="2026-10-16T12:00:00.100Z",
                  published_at="2026-10-16T11:00:00.100Z")
        new = job(reviewed_at="2026-10-16T12:00:00.1Z", updated_at="2026-10-16T12:00:00.1Z",
                  published_at="2026-10-16T11:00:00.1Z")
        result = compare.compare_feeds(
            feed(old, updated_at="2026-10-16T12:00:00.100Z"),
            feed(new, updated_at="2026-10-16T12:00:00.1Z"), NOW,
        )
        self.assertTrue(result.accepted, result.errors)
        self.assertEqual(result.unchanged, [(old["id"], ())])

    def test_unchanged_job_needs_no_timestamp_advance(self):
        result = compare.compare_feeds(feed(job()), feed(job()), NOW)
        self.assertTrue(result.accepted, result.errors)
        self.assertEqual(result.unchanged, [("sample-recruitment-2026", ())])

    def test_changed_content_requires_both_timestamps_to_advance(self):
        old = job()
        changed_no_advance = job(title_en="Edited title")
        result = compare.compare_feeds(feed(old), feed(changed_no_advance), NOW)
        self.assertFalse(result.accepted)
        self.assertTrue(any("updated_at: must advance" in error for error in result.errors), result.errors)
        self.assertTrue(any("reviewed_at: must advance" in error for error in result.errors), result.errors)

        update_only = job(title_en="Edited title", updated_at=stamp(CANDIDATE_TIME))
        result = compare.compare_feeds(feed(old), feed(update_only, updated_at=CANDIDATE_TIME), NOW)
        self.assertFalse(result.accepted)
        self.assertTrue(any("fresh human review is required" in error for error in result.errors), result.errors)

    def test_timestamp_regressions_are_rejected_by_instant(self):
        old = job(reviewed_at="2026-10-16T12:00:00.200Z", updated_at="2026-10-16T12:00:00.200Z")
        earlier = job(reviewed_at="2026-10-16T12:00:00.199Z", updated_at="2026-10-16T12:00:00.199Z")
        result = compare.compare_feeds(
            feed(old, updated_at="2026-10-16T12:00:00.200Z"),
            feed(earlier, updated_at="2026-10-16T12:00:00.199Z"), NOW,
        )
        self.assertTrue(any("updated_at: timestamp regressed" in e for e in result.errors), result.errors)
        self.assertTrue(any("reviewed_at: timestamp regressed" in e for e in result.errors), result.errors)
        self.assertTrue(any("envelope timestamp is earlier" in e for e in result.errors), result.errors)

    def test_submicrosecond_fractional_regressions_are_not_rounded_away(self):
        old = job(reviewed_at="2026-10-16T12:00:00.1000001Z",
                  updated_at="2026-10-16T12:00:00.1000001Z",
                  published_at="2026-10-16T11:00:00Z")
        earlier = job(reviewed_at="2026-10-16T12:00:00.1000000Z",
                      updated_at="2026-10-16T12:00:00.1000000Z",
                      published_at="2026-10-16T11:00:00Z")
        result = compare.compare_feeds(
            feed(old, updated_at="2026-10-16T12:00:00.1000001Z"),
            feed(earlier, updated_at="2026-10-16T12:00:00.1000000Z"), NOW,
        )
        self.assertTrue(any("updated_at: timestamp regressed" in e for e in result.errors), result.errors)
        self.assertTrue(any("reviewed_at: timestamp regressed" in e for e in result.errors), result.errors)
        self.assertTrue(any("envelope timestamp is earlier" in e for e in result.errors), result.errors)

    def test_published_at_is_immutable_for_existing_ids(self):
        old = job()
        changed = job(published_at=stamp(BASE_TIME - timedelta(minutes=30)))
        result = compare.compare_feeds(feed(old), feed(changed), NOW)
        self.assertFalse(result.accepted)
        self.assertTrue(any("published_at must be preserved" in error for error in result.errors), result.errors)

    def test_deadline_change_is_content_and_requires_fresh_review(self):
        old = job()
        changed_date = job(application_end_date="2027-01-15")
        result = compare.compare_feeds(feed(old), feed(changed_date), NOW)
        self.assertFalse(result.accepted)
        self.assertTrue(any("application_end_date" in error and "updated_at" in error for error in result.errors))
        self.assertTrue(any("application_end_date" in error and "reviewed_at" in error for error in result.errors))

        reviewed_change = job(application_end_date="2027-01-15", reviewed_at=stamp(CANDIDATE_TIME),
                              updated_at=stamp(CANDIDATE_TIME))
        result = compare.compare_feeds(feed(old), feed(reviewed_change, updated_at=CANDIDATE_TIME), NOW)
        self.assertTrue(result.accepted, result.errors)
        self.assertEqual(result.changed, [(old["id"], ("application_end_date",))])

    def test_closure_is_allowed_with_fresh_timestamps(self):
        old = job()
        closed = job(status="closed", reviewed_at=stamp(CANDIDATE_TIME),
                     updated_at=stamp(CANDIDATE_TIME))
        result = compare.compare_feeds(feed(old), feed(closed, updated_at=CANDIDATE_TIME), NOW)
        self.assertTrue(result.accepted, result.errors)
        self.assertEqual(result.changed, [(old["id"], ("status",))])

    def test_new_id_and_empty_baseline_bootstrap_are_allowed(self):
        new_job = job("first-job", reviewed_at=stamp(CANDIDATE_TIME), updated_at=stamp(CANDIDATE_TIME),
                      published_at=stamp(CANDIDATE_TIME))
        empty_baseline = feed(updated_at=BASE_TIME)
        result = compare.compare_feeds(empty_baseline, feed(new_job, updated_at=CANDIDATE_TIME), NOW)
        self.assertTrue(result.accepted, result.errors)
        self.assertEqual(result.added, [("first-job", "open")])
        bootstrap = compare.compare_feeds(empty_baseline, feed(updated_at=BASE_TIME), NOW)
        self.assertTrue(bootstrap.accepted, bootstrap.errors)

    def test_prior_id_deletion_and_remove_plus_add_replacement_are_rejected(self):
        old = job("prior-id")
        deleted = compare.compare_feeds(feed(old), feed(updated_at=CANDIDATE_TIME), NOW)
        self.assertFalse(deleted.accepted)
        self.assertEqual(deleted.missing, ["prior-id"])
        replaced = compare.compare_feeds(
            feed(old),
            feed(job("replacement-id", reviewed_at=stamp(CANDIDATE_TIME), updated_at=stamp(CANDIDATE_TIME),
                     published_at=stamp(CANDIDATE_TIME)), updated_at=CANDIDATE_TIME),
            NOW,
        )
        self.assertFalse(replaced.accepted)
        self.assertEqual(replaced.added, [("replacement-id", "open")])
        self.assertEqual(replaced.missing, ["prior-id"])
        self.assertTrue(any("possible ID replacement" in error for error in replaced.errors))

    def test_invalid_duplicate_inputs_are_rejected_on_either_side(self):
        duplicate = feed(job("duplicate"), job("duplicate"))
        bad_baseline = compare.compare_feeds(duplicate, feed(), NOW)
        self.assertFalse(bad_baseline.accepted)
        self.assertTrue(any(error.startswith("baseline:") and "duplicate id" in error
                            for error in bad_baseline.errors), bad_baseline.errors)
        bad_candidate = compare.compare_feeds(feed(), duplicate, NOW)
        self.assertFalse(bad_candidate.accepted)
        self.assertTrue(any(error.startswith("candidate:") and "duplicate id" in error
                            for error in bad_candidate.errors), bad_candidate.errors)

    def test_other_invalid_feed_fields_rejected_on_both_sides(self):
        broken_old = feed(job(title_en=""))
        broken_new = feed(job(source_url="javascript:alert(1)"))
        result = compare.compare_feeds(broken_old, broken_new, NOW)
        self.assertFalse(result.accepted)
        self.assertTrue(any(error.startswith("baseline:") and "title_en" in error for error in result.errors))
        self.assertTrue(any(error.startswith("candidate:") and "source_url" in error for error in result.errors))

    def test_cli_output_is_deterministic_and_inputs_are_byte_preserved(self):
        with tempfile.TemporaryDirectory(dir=ROOT.parent) as temp:
            directory = Path(temp)
            baseline_path = directory / "published.json"
            candidate_path = directory / "candidate.json"
            baseline_bytes = json.dumps(feed(job("z-job"), job("a-job")), ensure_ascii=False,
                                        indent=2).encode("utf-8")
            candidate_bytes = json.dumps(feed(
                job("a-job"), job("z-job"), job("new-job", reviewed_at=stamp(CANDIDATE_TIME),
                    updated_at=stamp(CANDIDATE_TIME), published_at=stamp(CANDIDATE_TIME)),
                updated_at=CANDIDATE_TIME,
            ), ensure_ascii=False, indent=2).encode("utf-8")
            baseline_path.write_bytes(baseline_bytes)
            candidate_path.write_bytes(candidate_bytes)
            before = (baseline_path.read_bytes(), candidate_path.read_bytes())
            command = [sys.executable, str(ROOT / "tools/feed/compare.py"), str(baseline_path), str(candidate_path)]
            first = subprocess.run(command, capture_output=True, text=True, check=False)
            second = subprocess.run(command, capture_output=True, text=True, check=False)
            after = (baseline_path.read_bytes(), candidate_path.read_bytes())
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        self.assertEqual(first.stdout, second.stdout)
        self.assertEqual(before, after)
        self.assertIn("Added (1):", first.stdout)
        self.assertIn("Unchanged (2):", first.stdout)
        self.assertIn("new-job", first.stdout)

    def test_cli_read_and_utf8_errors_are_clean_nonzero_exits(self):
        with tempfile.TemporaryDirectory(dir=ROOT.parent) as temp:
            directory = Path(temp)
            missing = directory / "missing.json"
            invalid_utf8 = directory / "invalid.json"
            valid = directory / "valid.json"
            valid.write_text(json.dumps(feed()), encoding="utf-8")
            invalid_utf8.write_bytes(b"\xff\xfe")
            read_error = subprocess.run(
                [sys.executable, str(ROOT / "tools/feed/compare.py"), str(missing), str(valid)],
                capture_output=True, text=True, check=False,
            )
            utf_error = subprocess.run(
                [sys.executable, str(ROOT / "tools/feed/compare.py"), str(valid), str(invalid_utf8)],
                capture_output=True, text=True, check=False,
            )
        self.assertNotEqual(read_error.returncode, 0)
        self.assertIn("baseline: cannot read file", read_error.stdout)
        self.assertNotIn("Traceback", read_error.stderr)
        self.assertNotEqual(utf_error.returncode, 0)
        self.assertIn("candidate: input is not valid UTF-8", utf_error.stdout)
        self.assertNotIn("Traceback", utf_error.stderr)

    def test_cli_malformed_json_is_rejected_without_traceback(self):
        with tempfile.TemporaryDirectory(dir=ROOT.parent) as temp:
            directory = Path(temp)
            baseline_path = directory / "baseline.json"
            candidate_path = directory / "candidate.json"
            baseline_path.write_text("{", encoding="utf-8")
            candidate_path.write_text(json.dumps(feed()), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools/feed/compare.py"), str(baseline_path), str(candidate_path)],
                capture_output=True, text=True, check=False,
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("baseline: invalid JSON", result.stdout)
        self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
