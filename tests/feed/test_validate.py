"""Unit tests for the dependency-free candidate feed validator."""

from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "feed"))
import validate  # noqa: E402

NOW = datetime(2026, 10, 17, 12, 0, tzinfo=timezone.utc)


def valid_job(**updates):
    job = {
        "id": "sample-recruitment-2026",
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
        "reviewed_at": "2026-10-17T11:00:00Z",
        "published_at": "2026-10-17T10:00:00Z",
        "updated_at": "2026-10-17T11:00:00Z",
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
    return {"schema_version": 1, "updated_at": "2026-10-17T11:00:00Z", "jobs": list(jobs)}


class FeedValidationTests(unittest.TestCase):
    def test_valid_feed_and_empty_feed(self):
        self.assertEqual(validate.validate_feed(valid_feed(valid_job()), NOW), [])
        self.assertEqual(validate.validate_feed(valid_feed(), NOW), [])

    def test_missing_bilingual_field_reports_exact_path(self):
        job = valid_job()
        del job["title_bn"]
        errors = validate.validate_feed(valid_feed(job), NOW)
        self.assertTrue(any(error.startswith("jobs[0].title_bn:") for error in errors), errors)

    def test_duplicate_ids_and_unknown_enum(self):
        errors = validate.validate_feed(valid_feed(valid_job(), valid_job()), NOW)
        self.assertTrue(any("jobs[1].id: duplicate id" in error for error in errors), errors)
        errors = validate.validate_feed(valid_feed(valid_job(category=[])), NOW)
        self.assertTrue(any(error.startswith("jobs[0].category:") for error in errors), errors)

    def test_schema_version_and_feed_timestamp(self):
        feed = valid_feed(valid_job())
        feed["schema_version"] = True
        feed["updated_at"] = "2026-10-17T11:00:00+00:00"
        errors = validate.validate_feed(feed, NOW)
        self.assertTrue(any(error.startswith("schema_version:") for error in errors), errors)
        self.assertTrue(any(error.startswith("updated_at:") for error in errors), errors)

    def test_open_recruitment_requires_deadline_and_date_order(self):
        errors = validate.validate_feed(valid_feed(valid_job(application_end_date=None)), NOW)
        self.assertTrue(any("jobs[0].application_end_date: is required" in error for error in errors), errors)
        errors = validate.validate_feed(valid_feed(valid_job(
            application_start_date="2026-12-31", application_end_date="2026-12-01"
        )), NOW)
        self.assertTrue(any("must not be after application_end_date" in error for error in errors), errors)

    def test_leap_day_and_invalid_calendar_date(self):
        self.assertEqual(validate.validate_feed(valid_feed(valid_job(exam_date="2024-02-29")), NOW), [])
        errors = validate.validate_feed(valid_feed(valid_job(exam_date="2025-02-29")), NOW)
        self.assertTrue(any(error.startswith("jobs[0].exam_date:") for error in errors), errors)

    def test_timestamp_order_and_future_tolerance(self):
        errors = validate.validate_feed(valid_feed(valid_job(
            reviewed_at="2026-10-17T11:30:00Z", updated_at="2026-10-17T11:00:00Z"
        )), NOW)
        self.assertTrue(any(error.startswith("jobs[0].reviewed_at:") for error in errors), errors)
        errors = validate.validate_feed(valid_feed(valid_job(
            published_at="2026-10-17T11:30:00Z", updated_at="2026-10-17T11:00:00Z"
        )), NOW)
        self.assertTrue(any(error.startswith("jobs[0].updated_at:") for error in errors), errors)
        errors = validate.validate_feed(valid_feed(valid_job(
            reviewed_at="2026-10-17T12:06:00Z", updated_at="2026-10-17T12:06:00Z"
        )), NOW)
        self.assertTrue(any("more than 5 minutes" in error for error in errors), errors)

    def test_unsafe_urls_html_and_non_integer_vacancies(self):
        job = valid_job(source_url="javascript:alert(1)", title_en="<b>Not safe</b>", vacancies=True)
        errors = validate.validate_feed(valid_feed(job), NOW)
        for prefix in ("jobs[0].source_url:", "jobs[0].title_en:", "jobs[0].vacancies:"):
            self.assertTrue(any(error.startswith(prefix) for error in errors), errors)

    def test_result_and_admit_card_cannot_be_open_or_closed(self):
        for kind in ("result", "admit_card"):
            errors = validate.validate_feed(valid_feed(valid_job(kind=kind, status="closed")), NOW)
            self.assertTrue(any(error.startswith("jobs[0].status:") for error in errors), errors)

    def test_cli_invalid_json_exits_nonzero_with_message(self):
        with tempfile.TemporaryDirectory(dir=ROOT.parent) as temp:
            candidate = Path(temp) / "bad.json"
            candidate.write_text("{", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools/feed/validate.py"), str(candidate)],
                capture_output=True, text=True, check=False,
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid JSON", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_cli_invalid_candidate_reports_field_path_without_traceback(self):
        with tempfile.TemporaryDirectory(dir=ROOT.parent) as temp:
            candidate = Path(temp) / "invalid-field.json"
            broken = valid_feed(valid_job())
            del broken["jobs"][0]["title_bn"]
            candidate.write_text(json.dumps(broken, ensure_ascii=False), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools/feed/validate.py"), str(candidate)],
                capture_output=True, text=True, check=False,
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("jobs[0].title_bn", result.stdout)
        self.assertNotIn("Traceback", result.stderr)

    def test_cli_valid_candidate_exits_zero(self):
        with tempfile.TemporaryDirectory(dir=ROOT.parent) as temp:
            candidate = Path(temp) / "candidate.json"
            candidate.write_text(json.dumps(valid_feed(valid_job()), ensure_ascii=False), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools/feed/validate.py"), str(candidate)],
                capture_output=True, text=True, check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("VALID candidate feed", result.stdout)
        self.assertIn("structure only", result.stdout)


    def test_contract_fixture_is_read_only_and_validates(self):
        fixture_path = ROOT / "test/fixtures/sample_feed.json"
        fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        self.assertEqual(validate.validate_feed(fixture, NOW), [])
        self.assertIn("SAMPLE ONLY", fixture["jobs"][0]["title_en"])

    def test_every_required_field_is_required_including_nullable_fields(self):
        for key in sorted(validate.REQUIRED_JOB_FIELDS):
            with self.subTest(field=key):
                job = valid_job()
                del job[key]
                errors = validate.validate_feed(valid_feed(job), NOW)
                self.assertTrue(any(error.startswith(f"jobs[0].{key}:") for error in errors), errors)

    def test_nullable_fields_reject_wrong_types(self):
        invalid_values = {
            "vacancies": True,
            "application_start_date": [],
            "application_end_date": 20261017,
            "application_end_at": 123,
            "exam_date": {},
            "apply_url": "javascript:alert(1)",
            "age_note_bn": [],
            "age_note_en": {},
        }
        for key, value in invalid_values.items():
            with self.subTest(field=key):
                errors = validate.validate_feed(valid_feed(valid_job(**{key: value})), NOW)
                self.assertTrue(any(error.startswith(f"jobs[0].{key}:") for error in errors), errors)

    def test_malformed_urls_credentials_and_ports_are_rejected(self):
        invalid_urls = [
            "http://example.org/notice",
            "https:///missing-host",
            "https://user:secret@example.org/notice",
            "https://example.org:abc/notice",
            "https://example.org:99999/notice",
            "https://example.org:/notice",
            "https://bad%zz.example/notice",
            "https://example.org\\\\notice",
        ]
        for value in invalid_urls:
            with self.subTest(url=value):
                errors = validate.validate_feed(valid_feed(valid_job(source_url=value)), NOW)
                self.assertTrue(any(error.startswith("jobs[0].source_url:") for error in errors), errors)
        self.assertEqual(validate.validate_feed(valid_feed(valid_job(source_url="https://[2001:db8::1]/notice")), NOW), [])

    def test_strict_utc_timestamp_shape_and_calendar_ranges(self):
        bad_values = [
            "2026-10-17 11:00:00Z",
            "2026-10-17T11:00:00+00:00",
            "2026-10-17T25:00:00Z",
            "2026-02-30T00:00:00Z",
        ]
        for value in bad_values:
            with self.subTest(timestamp=value):
                errors = validate.validate_feed(valid_feed(valid_job(reviewed_at=value)), NOW)
                self.assertTrue(any(error.startswith("jobs[0].reviewed_at:") for error in errors), errors)

    def test_withdrawal_and_result_status_contract(self):
        self.assertEqual(validate.validate_feed(valid_feed(valid_job(
            status="withdrawn", application_end_date=None
        )), NOW), [])
        for kind in ("result", "admit_card"):
            for status in ("published", "withdrawn"):
                with self.subTest(kind=kind, status=status):
                    self.assertEqual(validate.validate_feed(valid_feed(valid_job(kind=kind, status=status)), NOW), [])
            for status in ("open", "closed"):
                with self.subTest(kind=kind, status=status):
                    errors = validate.validate_feed(valid_feed(valid_job(kind=kind, status=status)), NOW)
                    self.assertTrue(any(error.startswith("jobs[0].status:") for error in errors), errors)

    def test_cli_invalid_utf8_exits_nonzero_without_traceback(self):
        with tempfile.TemporaryDirectory(dir=ROOT.parent) as temp:
            candidate = Path(temp) / "invalid-utf8.json"
            candidate.write_bytes(bytes([0xFF, 0xFE]))
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools/feed/validate.py"), str(candidate)],
                capture_output=True, text=True, check=False,
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not valid UTF-8", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_cli_read_error_exits_nonzero_without_traceback(self):
        with tempfile.TemporaryDirectory(dir=ROOT.parent) as temp:
            missing = Path(temp) / "missing.json"
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools/feed/validate.py"), str(missing)],
                capture_output=True, text=True, check=False,
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot read file", result.stderr)
        self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
