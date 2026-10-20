"""Offline tests for scripts/publish_notice.py (no network)."""

from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "tools" / "feed"))

import publish_notice as pn  # noqa: E402
import validate  # noqa: E402

NOW = datetime(2026, 10, 19, 12, 0, tzinfo=timezone.utc)
SOURCES = [
    {
        "name": "RRC Eastern Railway (Kolkata)",
        "url": "https://www.rrcer.org/notice_board.html",
        "allowed_domains": ["rrcer.org"],
        "districts": ["West Bengal", "Bihar"],
    },
    {
        "name": "WBPSC (West Bengal Public Service Commission)",
        "url": "https://psc.wb.gov.in/",
        "allowed_domains": ["psc.wb.gov.in"],
        "districts": ["West Bengal"],
    },
]

PAN_INDIA_SOURCES = [
    {
        "name": "IBPS (Institute of Banking Personnel Selection)",
        "url": "https://www.ibps.in/index.php/crp-updates/",
        "allowed_domains": ["ibps.in"],
        "districts": ["All India"],
    }
]


def issue(**updates):
    body = (
        "Cultural Quota Notification 2026-27..pdf\n\n"
        "- Source listing: RRC Eastern Railway (Kolkata)\n"
        "- Notice link: https://www.rrcer.org/Cultural Quota Notification 2026-27..pdf\n\n"
        "Human steps before any feed change:\n"
        "1. Open the notice and confirm it is on an official site.\n"
    )
    value = {"number": 4, "title": "[notice] Cultural Quota Notification 2026-27", "body": body}
    value.update(updates)
    return value


class ParseTests(unittest.TestCase):
    def test_valid_issue_is_parsed_and_spaces_encoded(self):
        notice = pn.parse_issue(issue(), SOURCES)
        self.assertEqual(notice["title"], "Cultural Quota Notification 2026-27")
        self.assertEqual(
            notice["url"],
            "https://www.rrcer.org/Cultural%20Quota%20Notification%202026-27..pdf",
        )
        self.assertEqual(notice["source_name"], "RRC Eastern Railway (Kolkata)")
        self.assertEqual(notice["source_url"], "https://www.rrcer.org/notice_board.html")

    def test_title_prefix_is_required(self):
        with self.assertRaises(pn.NoticeError):
            pn.parse_issue(issue(title="Cultural Quota"), SOURCES)

    def test_unknown_source_is_refused(self):
        body = issue()["body"].replace(
            "RRC Eastern Railway (Kolkata)", "Some Blog"
        )
        with self.assertRaises(pn.NoticeError):
            pn.parse_issue(issue(body=body), SOURCES)

    def test_foreign_domain_is_refused_even_for_an_approved_source(self):
        body = issue()["body"].replace(
            "https://www.rrcer.org/Cultural Quota Notification 2026-27..pdf",
            "https://rrcer.org.evil.example/Cultural Quota.pdf",
        )
        with self.assertRaises(pn.NoticeError):
            pn.parse_issue(issue(body=body), SOURCES)

    def test_plain_http_credentials_and_fragment_are_refused(self):
        for bad in (
            "http://www.rrcer.org/a.pdf",
            "https://user:pw@www.rrcer.org/a.pdf",
            "https://www.rrcer.org/a.pdf#page=2",
        ):
            with self.subTest(url=bad):
                body = issue()["body"].replace(
                    "https://www.rrcer.org/Cultural Quota Notification 2026-27..pdf",
                    bad,
                )
                with self.assertRaises(pn.NoticeError):
                    pn.parse_issue(issue(body=body), SOURCES)

    def test_two_links_are_refused(self):
        body = issue()["body"] + "- Notice link: https://www.rrcer.org/second.pdf\n"
        with self.assertRaises(pn.NoticeError):
            pn.parse_issue(issue(body=body), SOURCES)


class BuildTests(unittest.TestCase):
    def test_districts_come_from_the_source_not_a_default(self):
        """A board's HQ location is not where its posts are."""
        job = pn.build_job(pn.parse_issue(issue(), SOURCES), NOW)
        self.assertEqual(job["districts"], ["West Bengal", "Bihar"])

        body = (
            "Notification for CRP-PO/MTs-XVI\n\n"
            "- Source listing: IBPS (Institute of Banking Personnel Selection)\n"
            "- Notice link: https://www.ibps.in/wp-content/uploads/x.pdf\n"
        )
        parsed = pn.parse_issue(
            {"title": "[notice] CRP PO/MT", "body": body}, PAN_INDIA_SOURCES
        )
        self.assertEqual(pn.build_job(parsed, NOW)["districts"], ["All India"])

    def test_a_source_without_districts_is_refused(self):
        undeclared = [
            {
                "name": "RRC Eastern Railway (Kolkata)",
                "url": "https://www.rrcer.org/notice_board.html",
                "allowed_domains": ["rrcer.org"],
            }
        ]
        with self.assertRaises(pn.NoticeError) as caught:
            pn.parse_issue(issue(), undeclared)
        self.assertIn("must declare non-empty 'districts'", str(caught.exception))

    def test_an_empty_districts_list_is_refused(self):
        broken = [dict(SOURCES[0], districts=[])]
        with self.assertRaises(pn.NoticeError):
            pn.parse_issue(issue(), broken)
        blank = [dict(SOURCES[0], districts=["  "])]
        with self.assertRaises(pn.NoticeError):
            pn.parse_issue(issue(), blank)

    def test_every_category_is_reachable_from_an_approved_source(self):
        """The chip row and the card must agree, or a filter is permanently empty."""
        cases = {
            "West Bengal Police Recruitment Board": "police",
            "RRC Eastern Railway (Kolkata)": "railway",
            "IBPS (Institute of Banking Personnel Selection)": "banking",
            "West Bengal School Service Commission": "teaching",
            "West Bengal Health Recruitment Board": "medical",
            "WBPSC (West Bengal Public Service Commission)": "office",
            "Some Other Official Body": "other",
        }
        for name, expected in cases.items():
            self.assertEqual(pn.infer_category(name), expected, name)

    def test_job_is_a_valid_notice_only_card(self):
        job = pn.build_job(pn.parse_issue(issue(), SOURCES), NOW)
        self.assertEqual(job["kind"], "notice")
        self.assertEqual(job["status"], "published")
        self.assertEqual(job["category"], "railway")
        self.assertIsNone(job["application_end_date"])
        self.assertIsNone(job["apply_url"])
        self.assertEqual(job["qualifications"], [])
        self.assertIn("যাচাই করা হয়নি", job["summary_bn"])
        self.assertEqual(
            validate.validate_feed(
                {"schema_version": 1, "updated_at": "2026-10-19T12:00:00Z", "jobs": [job]},
                NOW,
            ),
            [],
        )

    def test_id_is_stable_and_derived_from_url(self):
        first = pn.notice_id("https://www.rrcer.org/a.pdf")
        second = pn.notice_id("https://www.rrcer.org/a.pdf")
        other = pn.notice_id("https://www.rrcer.org/b.pdf")
        self.assertEqual(first, second)
        self.assertNotEqual(first, other)
        self.assertRegex(first, r"^[a-z0-9-]{1,100}$")

    def test_upsert_is_idempotent(self):
        job = pn.build_job(pn.parse_issue(issue(), SOURCES), NOW)
        feed = {"schema_version": 1, "updated_at": "2026-10-19T12:00:00Z", "jobs": []}
        self.assertEqual(pn.upsert(feed, job), "added")
        self.assertEqual(pn.upsert(feed, dict(job)), "already-published")
        self.assertEqual(len(feed["jobs"]), 1)


class CliTests(unittest.TestCase):
    def _files(self):
        tmp = Path(tempfile.mkdtemp())
        issue_path = tmp / "issue.json"
        issue_path.write_text(json.dumps(issue()), encoding="utf-8")
        sources = tmp / "sources.json"
        sources.write_text(json.dumps({"sources": SOURCES}), encoding="utf-8")
        feed = tmp / "feed" / "jobs.json"
        return tmp, issue_path, sources, feed

    def test_cli_writes_a_valid_feed_then_refuses_to_duplicate(self):
        _, issue_path, sources, feed = self._files()
        args = [
            "--issue", str(issue_path), "--sources", str(sources),
            "--feed", str(feed), "--now", "2026-10-19T12:00:00Z",
        ]
        self.assertEqual(pn.main(args), 0)
        written = json.loads(feed.read_text(encoding="utf-8"))
        self.assertEqual(len(written["jobs"]), 1)
        self.assertEqual(validate.validate_feed(written, NOW), [])

        self.assertEqual(pn.main(args), 0)
        again = json.loads(feed.read_text(encoding="utf-8"))
        self.assertEqual(len(again["jobs"]), 1)

    def test_cli_refuses_a_foreign_domain_without_touching_the_feed(self):
        _, issue_path, sources, feed = self._files()
        bad = issue()
        bad["body"] = bad["body"].replace(
            "https://www.rrcer.org/Cultural Quota Notification 2026-27..pdf",
            "https://evil.example/x.pdf",
        )
        issue_path.write_text(json.dumps(bad), encoding="utf-8")
        code = pn.main(
            ["--issue", str(issue_path), "--sources", str(sources), "--feed", str(feed)]
        )
        self.assertEqual(code, 2)
        self.assertFalse(feed.exists())


if __name__ == "__main__":
    unittest.main()
