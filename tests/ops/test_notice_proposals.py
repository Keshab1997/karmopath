"""Offline tests for scripts/notice_proposals.py (no network, never writes a feed)."""

import json
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from unittest import mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import notice_proposals as np  # noqa: E402
import publish_notice as pn  # noqa: E402

NOW = datetime(2026, 10, 20, 6, 0, 0, tzinfo=timezone.utc)
SOURCES = [
    {
        "name": "RRC Eastern Railway (Kolkata)",
        "url": "https://www.rrcer.org/notice_board.html",
        "allowed_domains": ["rrcer.org"],
    },
    {
        "name": "West Bengal School Service Commission",
        "url": "https://www.westbengalssc.com/otr/recruitment/",
        "allowed_domains": ["westbengalssc.com"],
    },
]

CANDIDATES = [
    {
        "url": "https://www.rrcer.org/PET result 29.09.2026.pdf",
        "title": "Result of Physicial Efficiency Test (PET) against CEN 08/2024 dtd. 29.09.2026.",
        "source": "RRC Eastern Railway (Kolkata)",
        "seen_on": "2026-10-19",
        "is_new": False,
    },
    {
        "url": "https://www.westbengalssc.com/otr/downloads/notice/MeritList.pdf",
        "title": "Click here to Download Combined Merit List for 1st Phase(Part-II) Counselling",
        "source": "West Bengal School Service Commission",
        "is_new": True,
    },
    {
        "url": "https://job-blog.example.org/advertisement.pdf",
        "title": "Advertisement for something unofficial",
        "source": "RRC Eastern Railway (Kolkata)",
        "is_new": True,
    },
]


class CandidateLoadingTests(unittest.TestCase):
    def _load(self, payload):
        tmp = Path(tempfile.mkdtemp()) / "candidates.json"
        tmp.write_text(json.dumps(payload), encoding="utf-8")
        return np.load_candidates(tmp)

    def test_accepts_report_candidates_output(self):
        items = self._load({"candidates": CANDIDATES, "total_live": 3})
        self.assertEqual(len(items), 3)
        self.assertEqual(items[0]["source"], "RRC Eastern Railway (Kolkata)")

    def test_accepts_discovery_new_list(self):
        items = self._load({"new": [{"url": "https://a/x", "title": "Notice", "source": "S"}]})
        self.assertEqual(items[0]["seen_on"], None)

    def test_accepts_bare_list_and_rejects_missing_fields(self):
        self.assertEqual(len(self._load(CANDIDATES)), 3)
        with self.assertRaises(np.ProposalError):
            self._load([{"title": "no url", "source": "S"}])
        with self.assertRaises(np.ProposalError):
            self._load({"unexpected": 1})

    def test_feed_urls_are_read_only_and_missing_is_empty(self):
        tmp = Path(tempfile.mkdtemp())
        feed = tmp / "jobs.json"
        feed.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "updated_at": "2026-10-19T19:36:45Z",
                    "jobs": [{"id": "job-1", "notice_url": "https://x/a.pdf"}],
                }
            ),
            encoding="utf-8",
        )
        self.assertEqual(np.feed_notice_urls(feed), {"https://x/a.pdf": "job-1"})
        self.assertEqual(np.feed_notice_urls(tmp / "absent.json"), {})
        self.assertEqual(np.feed_notice_urls(None), {})


class ProposalTests(unittest.TestCase):
    def _build(self, only_new=False, max_title=np.MAX_TITLE):
        return np.build_proposals(
            CANDIDATES,
            SOURCES,
            now=NOW,
            feed_urls={},
            only_new=only_new,
            max_title=max_title,
        )

    def test_card_is_exactly_what_the_publisher_would_write(self):
        proposals, _ = self._build()
        self.assertEqual(len(proposals), 2)
        first = proposals[0]
        expected = pn.build_job(
            {
                "title": pn.clean_title(CANDIDATES[0]["title"]),
                "url": "https://www.rrcer.org/PET%20result%2029.09.2026.pdf",
                "source_name": "RRC Eastern Railway (Kolkata)",
                "source_url": "https://www.rrcer.org/notice_board.html",
            },
            NOW,
        )
        self.assertEqual(first["card"], expected)
        # A notice-only card never claims the fields the gate protects.
        self.assertEqual(first["card"]["kind"], "notice")
        self.assertIsNone(first["card"]["vacancies"])
        self.assertIsNone(first["card"]["application_end_date"])
        self.assertIsNone(first["card"]["apply_url"])

    def test_spaces_are_encoded_and_fragment_dropped(self):
        proposals, _ = self._build()
        self.assertEqual(
            proposals[0]["url"], "https://www.rrcer.org/PET%20result%2029.09.2026.pdf"
        )

    def test_unofficial_host_is_skipped_not_proposed(self):
        proposals, skipped = self._build()
        self.assertNotIn("job-blog.example.org", json.dumps(proposals))
        self.assertTrue(
            any("not on the approved domain" in item["reason"] for item in skipped),
            skipped,
        )

    def test_link_already_in_feed_is_skipped(self):
        proposals, skipped = np.build_proposals(
            CANDIDATES,
            SOURCES,
            now=NOW,
            feed_urls={"https://www.rrcer.org/PET%20result%2029.09.2026.pdf": "job-live"},
            only_new=False,
            max_title=np.MAX_TITLE,
        )
        self.assertEqual(len(proposals), 1)
        self.assertEqual(skipped[0]["reason"], "already-in-feed as job-live")

    def test_only_new_drops_links_discovery_reported(self):
        proposals, skipped = self._build(only_new=True)
        self.assertEqual([item["url"] for item in proposals], [CANDIDATES[1]["url"]])
        self.assertEqual(skipped[0]["reason"], "already-reported-on 2026-10-19")

    def test_long_titles_are_cut_at_a_word_and_flagged(self):
        candidates = [
            {
                "url": "https://www.rrcer.org/a.pdf",
                "title": "IMPORTANT NOTICE " + "word " * 60,
                "source": "RRC Eastern Railway (Kolkata)",
            }
        ]
        proposals, _ = np.build_proposals(
            candidates,
            SOURCES,
            now=NOW,
            feed_urls={},
            only_new=False,
            max_title=40,
        )
        title = proposals[0]["card"]["title_en"]
        self.assertTrue(title.startswith("IMPORTANT NOTICE"))
        self.assertLessEqual(len(title), 40)
        self.assertFalse(title.endswith(" "))
        self.assertNotIn("  ", title)
        self.assertTrue(proposals[0]["title_truncated"])

    def test_seen_flags_come_from_the_seen_file_when_absent(self):
        candidates = [
            {
                "url": "https://www.rrcer.org/PET result 29.09.2026.pdf",
                "title": "Result of Physical Efficiency Test against CEN 08/2024",
                "source": "RRC Eastern Railway (Kolkata)",
            },
            {
                "url": "https://www.rrcer.org/New%20Notice.pdf",
                "title": "New Notice for candidates",
                "source": "RRC Eastern Railway (Kolkata)",
            },
        ]
        proposals, _ = np.build_proposals(
            candidates,
            SOURCES,
            now=NOW,
            feed_urls={},
            only_new=False,
            max_title=np.MAX_TITLE,
            seen={"https://www.rrcer.org/PET%20result%2029.09.2026.pdf": "2026-10-19"},
        )
        by_url = {item["url"]: item for item in proposals}
        self.assertEqual(
            by_url["https://www.rrcer.org/PET%20result%2029.09.2026.pdf"]["seen_on"],
            "2026-10-19",
        )
        self.assertFalse(by_url["https://www.rrcer.org/PET%20result%2029.09.2026.pdf"]["is_new"])
        self.assertIsNone(by_url["https://www.rrcer.org/New%20Notice.pdf"]["seen_on"])
        self.assertTrue(by_url["https://www.rrcer.org/New%20Notice.pdf"]["is_new"])

    def test_only_new_uses_the_seen_file_when_the_input_has_no_flag(self):
        candidates = [
            {
                "url": "https://www.rrcer.org/PET result 29.09.2026.pdf",
                "title": "Result of Physical Efficiency Test against CEN 08/2024",
                "source": "RRC Eastern Railway (Kolkata)",
            }
        ]
        proposals, skipped = np.build_proposals(
            candidates,
            SOURCES,
            now=NOW,
            feed_urls={},
            only_new=True,
            max_title=np.MAX_TITLE,
            seen={"https://www.rrcer.org/PET%20result%2029.09.2026.pdf": "2026-10-19"},
        )
        self.assertEqual(proposals, [])
        self.assertEqual(skipped[0]["reason"], "already-reported-on 2026-10-19")

    def test_issue_body_round_trips_through_the_publisher_parser(self):
        proposals, _ = self._build()
        for proposal in proposals:
            parsed = pn.parse_issue(proposal["issue"], SOURCES)
            self.assertEqual(parsed["url"], proposal["url"])
            self.assertEqual(parsed["title"], proposal["card"]["title_en"])
            self.assertEqual(pn.build_job(parsed, NOW), proposal["card"])
        np.selfcheck(proposals, SOURCES, NOW)  # must not raise

    def test_selfcheck_catches_a_tampered_preview(self):
        proposals, _ = self._build()
        proposals[0]["card"]["summary_bn"] = "invented"
        with self.assertRaises(np.ProposalError):
            np.selfcheck(proposals, SOURCES, NOW)


class MainTests(unittest.TestCase):
    def _tmp(self):
        tmp = Path(tempfile.mkdtemp())
        candidates = tmp / "candidates.json"
        candidates.write_text(json.dumps({"candidates": CANDIDATES}), encoding="utf-8")
        sources = tmp / "sources.json"
        sources.write_text(json.dumps({"sources": SOURCES}), encoding="utf-8")
        return tmp, candidates, sources

    def test_writes_proposal_preview_and_issue_script(self):
        tmp, candidates, sources = self._tmp()
        out = tmp / "proposals.json"
        preview = tmp / "preview.json"
        issues = tmp / "issues.sh"
        code = np.main(
            [
                "--candidates", str(candidates),
                "--sources", str(sources),
                "--out", str(out),
                "--feed-preview", str(preview),
                "--issues-out", str(issues),
                "--now", "2026-10-20T06:00:00Z",
            ]
        )
        self.assertEqual(code, 0)
        document = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(len(document["proposals"]), 2)
        self.assertEqual(len(document["skipped"]), 1)
        feed = json.loads(preview.read_text(encoding="utf-8"))
        self.assertEqual(feed["schema_version"], 1)
        self.assertEqual(len(feed["jobs"]), 2)
        self.assertEqual(feed["updated_at"], "2026-10-20T06:00:00Z")
        script = issues.read_text(encoding="utf-8")
        self.assertIn("gh issue create --label notice-review", script)
        self.assertIn("- Notice link: https://www.rrcer.org/PET%20result%2029.09.2026.pdf", script)
        self.assertNotIn("--label approve-notice", script)

    def test_refuses_to_write_into_the_live_feed_directory(self):
        tmp, candidates, sources = self._tmp()
        feed_dir = tmp / "feed"
        feed_dir.mkdir()
        blocked = feed_dir / "jobs.json"
        with mock.patch.object(np, "ROOT", tmp):
            code = np.main(
                [
                    "--candidates", str(candidates),
                    "--sources", str(sources),
                    "--out", str(blocked),
                    "--now", "2026-10-20T06:00:00Z",
                ]
            )
        self.assertEqual(code, 2)
        self.assertFalse(blocked.exists())

    def test_unknown_source_name_is_a_skip_not_a_crash(self):
        tmp, _candidates, sources = self._tmp()
        candidates = tmp / "c.json"
        candidates.write_text(
            json.dumps(
                [{"url": "https://x/a.pdf", "title": "Notice", "source": "Made Up Board"}]
            ),
            encoding="utf-8",
        )
        out = tmp / "o.json"
        code = np.main(
            [
                "--candidates", str(candidates),
                "--sources", str(sources),
                "--out", str(out),
                "--now", "2026-10-20T06:00:00Z",
            ]
        )
        self.assertEqual(code, 0)
        document = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(document["proposals"], [])
        self.assertIn("approved sources", document["skipped"][0]["reason"])


if __name__ == "__main__":
    unittest.main()
