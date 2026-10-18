"""Unit and CLI tests for the offline publish-readiness checklist."""

from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "feed"))
import check_publish  # noqa: E402
import validate  # noqa: E402

NOW = datetime(2026, 10, 18, 6, 0, 0, tzinfo=timezone.utc)
NOW_TEXT = "2026-10-18T06:00:00Z"


def valid_job(job_id=None, **updates):
    job = {
        "id": job_id or "sample-recruitment-2026",
        "kind": "recruitment",
        "title_bn": "নমুনা নিয়োগ",
        "title_en": "Sample recruitment",
        "organization": "Sample organization",
        "category": "office",
        "districts": ["West Bengal"],
        "qualifications": ["Graduate"],
        "status": "open",
        "source_url": "https://example.org/notice",
        "notice_url": "https://example.org/notice.pdf",
        "reviewed_at": "2026-10-18T05:00:00Z",
        "published_at": "2026-10-18T04:00:00Z",
        "updated_at": "2026-10-18T05:00:00Z",
        "summary_bn": "এটি একটি নমুনা বিজ্ঞপ্তি।",
        "summary_en": "This is a sample notice.",
        "how_to_apply_bn": "",
        "how_to_apply_en": "",
        "vacancies": None,
        "application_start_date": None,
        "application_end_date": "2026-12-31",
        "application_end_at": None,
        "exam_date": None,
        "apply_url": None,
        "age_note_bn": None,
        "age_note_en": None,
    }
    job.update(updates)
    return job


def valid_feed(*jobs):
    return {"schema_version": 1, "updated_at": "2026-10-18T05:00:00Z", "jobs": list(jobs)}


def run_cli(payload, *flags, directory=None):
    with tempfile.TemporaryDirectory(dir=directory) as tmp:
        path = Path(tmp) / "candidate.json"
        path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(ROOT / "tools/feed/check_publish.py"), str(path), *flags],
            capture_output=True, text=True, timeout=60,
        )


def item_map(items):
    return {(item.path, item.field): item for item in items}


class ChecklistUnitTests(unittest.TestCase):
    def test_valid_feed_has_only_pass_items(self):
        items, checked = check_publish.run_checklist(valid_feed(valid_job()), NOW)
        self.assertEqual(checked, 1)
        self.assertEqual([item.status for item in items], ["PASS", "PASS", "PASS"])
        self.assertEqual([item.field for item in items], ["source_url", "notice_url", "published_at"])
        self.assertTrue(all(item.job_id == "sample-recruitment-2026" for item in items))

    def test_missing_and_null_links_fail_with_job_id(self):
        feed = valid_feed(
            valid_job("job-no-source", source_url=None),
            valid_job("job-no-notice", notice_url=""),
        )
        items, _ = check_publish.run_checklist(feed, NOW)
        mapped = item_map(items)
        self.assertEqual(mapped[("jobs[0].source_url", "source_url")].status, "FAIL")
        self.assertIn("null or missing", mapped[("jobs[0].source_url", "source_url")].detail)
        self.assertEqual(mapped[("jobs[1].notice_url", "notice_url")].status, "FAIL")
        self.assertEqual(mapped[("jobs[1].notice_url", "notice_url")].job_id, "job-no-notice")

    def test_fragment_fails_checklist_even_though_validator_accepts_it(self):
        job = valid_job(notice_url="https://example.org/notice.pdf#page=2")
        self.assertEqual(validate.validate_feed(valid_feed(job), NOW), [])
        items, _ = check_publish.run_checklist(valid_feed(job), NOW)
        notice = item_map(items)[("jobs[0].notice_url", "notice_url")]
        self.assertEqual(notice.status, "FAIL")
        self.assertIn("fragment", notice.detail)

    def test_embedded_credentials_fail_checklist(self):
        job = valid_job(source_url="https://user:pass@example.org/notice")
        items, _ = check_publish.run_checklist(valid_feed(job), NOW)
        source = item_map(items)[("jobs[0].source_url", "source_url")]
        self.assertEqual(source.status, "FAIL")
        self.assertIn("credentials", source.detail)

    def test_future_published_at_fails_and_near_tolerance_passes(self):
        far = valid_job(published_at="2099-01-01T00:00:00Z", updated_at="2099-01-01T00:00:00Z",
                        reviewed_at="2099-01-01T00:00:00Z")
        items, _ = check_publish.run_checklist(valid_feed(far), NOW)
        self.assertEqual(item_map(items)[("jobs[0].published_at", "published_at")].status, "FAIL")
        near = valid_job(published_at="2026-10-18T06:03:00Z", updated_at="2026-10-18T06:03:00Z",
                         reviewed_at="2026-10-18T06:03:00Z")
        items, _ = check_publish.run_checklist(valid_feed(near), NOW)
        self.assertEqual(item_map(items)[("jobs[0].published_at", "published_at")].status, "PASS")

    def test_unparseable_published_at_fails(self):
        job = valid_job(published_at="2026-10-18 06:00:00")
        items, _ = check_publish.run_checklist(valid_feed(job), NOW)
        published = item_map(items)[("jobs[0].published_at", "published_at")]
        self.assertEqual(published.status, "FAIL")
        self.assertIn("UTC", published.detail)

    def test_empty_districts_and_qualifications_warn_without_failing(self):
        job = valid_job(districts=[], qualifications=[])
        items, _ = check_publish.run_checklist(valid_feed(job), NOW)
        mapped = item_map(items)
        self.assertEqual(mapped[("jobs[0].districts", "districts")].status, "WARN")
        self.assertEqual(mapped[("jobs[0].qualifications", "qualifications")].status, "WARN")
        statuses = [item.status for item in items]
        self.assertEqual(statuses.count("FAIL"), 0)

    def test_non_dict_jobs_are_left_to_the_validator(self):
        items, checked = check_publish.run_checklist(valid_feed("not-an-object"), NOW)
        self.assertEqual(items, [])
        self.assertEqual(checked, 0)

    def test_deterministic_item_order_and_rendering(self):
        feed = valid_feed(valid_job("b-job", districts=[]), valid_job("a-job"))
        first = check_publish.run_checklist(feed, NOW)[0]
        second = check_publish.run_checklist(feed, NOW)[0]
        self.assertEqual([item.render() for item in first], [item.render() for item in second])
        self.assertTrue(first[0].render().startswith("[PASS] jobs[0].source_url (id=b-job) source_url:"))


class ChecklistCliTests(unittest.TestCase):
    def test_valid_feed_exits_zero_and_is_ready(self):
        result = run_cli(valid_feed(valid_job()), "--now", NOW_TEXT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("VALIDATION: PASS", result.stdout)
        self.assertIn("RESULT: READY", result.stdout)
        self.assertIn("[PASS] jobs[0].source_url (id=sample-recruitment-2026)", result.stdout)

    def test_missing_source_url_fails_with_job_id(self):
        result = run_cli(valid_feed(valid_job(source_url=None)), "--now", NOW_TEXT)
        self.assertEqual(result.returncode, 1)
        self.assertIn("[FAIL]", result.stdout)
        self.assertIn("id=sample-recruitment-2026", result.stdout)
        self.assertIn("source_url", result.stdout)

    def test_future_published_at_fails(self):
        job = valid_job(published_at="2099-01-01T00:00:00Z", updated_at="2099-01-01T00:00:00Z",
                        reviewed_at="2099-01-01T00:00:00Z")
        result = run_cli(valid_feed(job), "--now", NOW_TEXT)
        self.assertEqual(result.returncode, 1)
        self.assertIn("published_at: is in the future", result.stdout)
        self.assertIn("RESULT: NOT READY", result.stdout)

    def test_null_source_url_is_flagged_by_validation_and_checklist(self):
        result = run_cli(valid_feed(valid_job(source_url=None)), "--now", NOW_TEXT)
        self.assertEqual(result.returncode, 1)
        self.assertIn("VALIDATION: FAIL", result.stdout)
        self.assertIn("jobs[0].source_url: must be an HTTPS URL", result.stdout)
        self.assertIn("is null or missing", result.stdout)

    def test_empty_districts_warn_exit_zero_then_strict_fails(self):
        result = run_cli(valid_feed(valid_job(districts=[])), "--now", NOW_TEXT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("[WARN] jobs[0].districts", result.stdout)
        self.assertIn("RESULT: READY", result.stdout)
        strict = run_cli(valid_feed(valid_job(districts=[])), "--now", NOW_TEXT, "--strict")
        self.assertEqual(strict.returncode, 1)
        self.assertIn("--strict", strict.stdout)
        self.assertIn("RESULT: NOT READY", strict.stdout)

    def test_identical_input_and_now_give_identical_output(self):
        feed = valid_feed(valid_job("job-one"), valid_job("job-two", districts=[]))
        first = run_cli(feed, "--now", NOW_TEXT)
        second = run_cli(feed, "--now", NOW_TEXT)
        self.assertEqual(first.returncode, second.returncode)
        self.assertTrue(first.stdout.startswith("PUBLISH CHECKLIST (offline): "))
        self.assertEqual(first.stdout.splitlines()[1:], second.stdout.splitlines()[1:])

    def test_bad_now_flag_is_rejected(self):
        result = run_cli(valid_feed(valid_job()), "--now", "not-a-timestamp")
        self.assertEqual(result.returncode, 1)
        self.assertIn("--now", result.stderr)

    def test_unreadable_file_reports_error_without_traceback(self):
        with tempfile.TemporaryDirectory() as tmp:
            missing = Path(tmp) / "absent.json"
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools/feed/check_publish.py"), str(missing)],
                capture_output=True, text=True, timeout=60,
            )
        self.assertEqual(result.returncode, 1)
        self.assertIn("cannot read file", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_malformed_json_reports_error_without_traceback(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "candidate.json"
            path.write_text("{ not json", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools/feed/check_publish.py"), str(path)],
                capture_output=True, text=True, timeout=60,
            )
        self.assertEqual(result.returncode, 1)
        self.assertIn("invalid JSON", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_empty_feed_passes_with_zero_jobs(self):
        result = run_cli(valid_feed(), "--now", NOW_TEXT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("0 passed, 0 failed, 0 warning(s) across 0 job(s)", result.stdout)


if __name__ == "__main__":
    unittest.main()
