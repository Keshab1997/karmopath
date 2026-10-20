"""Offline tests for scripts/discover_notices.py (no network)."""

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import discover_notices as dn  # noqa: E402

PAGE = """
<html><body>
  <a href="Download?param1=x.pdf">IMPORTANT NOTICE REGARDING CLERKSHIP EXAMINATION 2024</a>
  <a href="https://psc.wb.gov.in/notice.pdf#top">Advertisement for Bengali Reporter 2025</a>
  <a href="https://evil.example.org/fake.pdf">Advertisement for fake job</a>
  <a href="http://psc.wb.gov.in/plain.pdf">Notification over plain http</a>
  <a href="mailto:help@psc.wb.gov.in">Email help desk for notification queries</a>
  <a href="/about">About us page</a>
  <a href="https://www.rrcer.org/x.pdf">Notice of Cultural Quota recruitment</a>
  <a href="https://www.rrcer.org/Cultural Quota Notification 2026-27..pdf">Cultural Quota Notification 2026-27</a>
</body></html>
"""


class ExtractTests(unittest.TestCase):
    def test_keeps_only_notice_links_on_allowed_domains(self):
        found = dn.extract_notices(
            "https://psc.wb.gov.in/", PAGE, ["psc.wb.gov.in"]
        )
        self.assertEqual(
            sorted(found),
            [
                "https://psc.wb.gov.in/Download?param1=x.pdf",
                "https://psc.wb.gov.in/notice.pdf",
            ],
        )

    def test_spaces_in_link_are_percent_encoded(self):
        found = dn.extract_notices(
            "https://www.rrcer.org/", PAGE, ["rrcer.org"]
        )
        self.assertIn(
            "https://www.rrcer.org/Cultural%20Quota%20Notification%202026-27..pdf",
            found,
        )

    def test_fragment_is_dropped_so_it_is_not_counted_twice(self):
        found = dn.extract_notices(
            "https://psc.wb.gov.in/", PAGE, ["psc.wb.gov.in"]
        )
        self.assertNotIn("https://psc.wb.gov.in/notice.pdf#top", found)

    def test_subdomain_is_allowed_but_lookalike_is_not(self):
        self.assertTrue(dn.host_allowed("https://www.rrcer.org/a", ["rrcer.org"]))
        self.assertFalse(dn.host_allowed("https://rrcer.org.evil.com/a", ["rrcer.org"]))
        self.assertFalse(dn.host_allowed("https://notrrcer.org/a", ["rrcer.org"]))


class MainTests(unittest.TestCase):
    """Runs main() with a patched fetch, so no test touches the network."""

    def _run(self, seen_initial, pages, extra_args=(), fetch=None):
        tmp = Path(tempfile.mkdtemp())
        sources = tmp / "sources.json"
        entries = []
        for name, spec in pages["config"].items():
            url, domain = spec[0], spec[1]
            entry = {"name": name, "url": url, "allowed_domains": [domain]}
            if len(spec) > 2:
                entry["alternates"] = list(spec[2])
            entries.append(entry)
        sources.write_text(json.dumps({"sources": entries}), encoding="utf-8")
        seen = tmp / "seen.json"
        if seen_initial is not None:
            seen.write_text(json.dumps(seen_initial), encoding="utf-8")
        out = tmp / "out.json"

        calls = []

        def fake_fetch(url, timeout=dn.TIMEOUT_SECONDS):
            if url in pages["html"]:
                return pages["html"][url]
            raise RuntimeError("HTTP 404")

        fetch_impl = fetch or fake_fetch

        def recorded(url, timeout=dn.TIMEOUT_SECONDS):
            calls.append(url)
            return fetch_impl(url, timeout)

        with mock.patch.object(
            dn, "fetch_html", recorded
        ), mock.patch.object(dn, "SLEEP", lambda _seconds: None):
            code = dn.main(
                ["--sources", str(sources), "--seen", str(seen), "--out", str(out)]
                + list(extra_args)
            )
        report = json.loads(out.read_text(encoding="utf-8")) if out.exists() else None
        return code, report, seen, calls

    def setUp(self):
        self.pages = {
            "config": {"PSC": ("https://psc.wb.gov.in/", "psc.wb.gov.in")},
            "html": {"https://psc.wb.gov.in/": PAGE},
        }

    def test_first_run_is_baseline_and_reports_nothing(self):
        code, out, seen_path, _ = self._run(None, self.pages)
        self.assertEqual(code, 0)
        self.assertEqual(out["new"], [])
        recorded = json.loads(seen_path.read_text(encoding="utf-8"))
        self.assertEqual(len(recorded), 2)

    def test_old_seen_keys_with_spaces_are_migrated(self):
        seen = {
            "https://www.rrcer.org/Cultural Quota Notification 2026-27..pdf": "2026-10-19"
        }
        tmp = Path(tempfile.mkdtemp())
        seen_path = tmp / "seen.json"
        seen_path.write_text(json.dumps(seen), encoding="utf-8")
        migrated = dn.load_seen(seen_path)
        self.assertIn(
            "https://www.rrcer.org/Cultural%20Quota%20Notification%202026-27..pdf",
            migrated,
        )

    def test_later_run_reports_only_unseen_links(self):
        seen = {"https://psc.wb.gov.in/Download?param1=x.pdf": "2026-10-19"}
        code, out, _, _ = self._run(seen, self.pages)
        self.assertEqual(code, 0)
        self.assertEqual(
            [item["url"] for item in out["new"]],
            ["https://psc.wb.gov.in/notice.pdf"],
        )
        self.assertEqual(out["new"][0]["source"], "PSC")

    def test_all_sources_failing_is_an_error_not_silence(self):
        pages = {
            "config": {"PSC": ("https://psc.wb.gov.in/", "psc.wb.gov.in")},
            "html": {},
        }
        code, report, _, _ = self._run({}, pages)
        self.assertEqual(code, 1)
        self.assertIsNone(report)

    def test_slow_source_is_retried_before_it_is_called_a_failure(self):
        """A listing page that answers on the third try must be reported."""
        state = {"tries": 0}

        def flaky(url, timeout=dn.TIMEOUT_SECONDS):
            state["tries"] += 1
            if state["tries"] < 3:
                raise TimeoutError("timed out")
            return PAGE

        code, report, _, calls = self._run({}, self.pages, fetch=flaky)
        self.assertEqual(code, 0)
        self.assertEqual(state["tries"], 3)
        self.assertEqual(len(calls), 3)
        self.assertEqual(report["failures"], [])
        self.assertEqual(len(report["new"]), 2)

    def test_persistent_timeout_is_reported_with_the_attempt_count(self):
        def always_timeout(url, timeout=dn.TIMEOUT_SECONDS):
            raise TimeoutError("timed out")

        code, report, _, calls = self._run({}, self.pages, fetch=always_timeout)
        self.assertEqual(code, 1)  # nothing readable at all
        self.assertEqual(len(calls), dn.ATTEMPTS)

    def test_alternate_listing_url_is_used_when_the_primary_is_down(self):
        pages = {
            "config": {
                "PSC": (
                    "https://psc.wb.gov.in/",
                    "psc.wb.gov.in",
                    ["https://www.psc.wb.gov.in/"],
                )
            },
            "html": {"https://www.psc.wb.gov.in/": PAGE},
        }
        code, report, seen_path, calls = self._run({}, pages)
        self.assertEqual(code, 0)
        self.assertEqual(calls[0], "https://psc.wb.gov.in/")
        self.assertIn("https://www.psc.wb.gov.in/", calls)
        self.assertEqual(report["failures"], [])
        # A relative link is resolved against the page that actually answered;
        # an absolute link keeps its own host. Both are on the approved domain.
        self.assertEqual(
            sorted(item["url"] for item in report["new"]),
            [
                "https://psc.wb.gov.in/notice.pdf",
                "https://www.psc.wb.gov.in/Download?param1=x.pdf",
            ],
        )
        recorded = json.loads(seen_path.read_text(encoding="utf-8"))
        self.assertIn("https://psc.wb.gov.in/notice.pdf", recorded)

    def test_report_candidates_includes_seen_links_and_writes_no_state(self):
        seen = {
            "https://psc.wb.gov.in/notice.pdf": "2026-10-19",
            "https://psc.wb.gov.in/Download?param1=x.pdf": "2026-10-19",
        }
        before = json.dumps(seen, sort_keys=True)
        code, report, seen_path, _ = self._run(
            seen, self.pages, extra_args=["--report-candidates", "--max-new", "5"]
        )
        self.assertEqual(code, 0)
        self.assertEqual(report["total_live"], 2)
        self.assertEqual(len(report["candidates"]), 2)
        self.assertEqual(
            [item["is_new"] for item in report["candidates"]], [False, False]
        )
        self.assertEqual(report.get("new", "absent"), "absent")
        self.assertEqual(
            json.dumps(json.loads(seen_path.read_text(encoding="utf-8")), sort_keys=True),
            before,
        )

    def test_source_filter_limits_the_run(self):
        pages = {
            "config": {
                "PSC": ("https://psc.wb.gov.in/", "psc.wb.gov.in"),
                "RRC Eastern Railway (Kolkata)": ("https://www.rrcer.org/", "rrcer.org"),
            },
            "html": {"https://psc.wb.gov.in/": PAGE},
        }
        code, report, _, calls = self._run(
            {}, pages, extra_args=["--source", "psc"]
        )
        self.assertEqual(code, 0)
        self.assertEqual(calls, ["https://psc.wb.gov.in/"])
        self.assertTrue(all(item["source"] == "PSC" for item in report["new"]))

    def test_source_filter_with_no_match_fails_loudly(self):
        code, report, _, _ = self._run(
            {}, self.pages, extra_args=["--source", "no-such-body"]
        )
        self.assertEqual(code, 1)
        self.assertIsNone(report)


class NoticePatternTests(unittest.TestCase):
    """The listing pages use words the original pattern never covered."""

    LINKS = """
    <html><body>
      <a href="/otr/downloads/notice/MeritList.pdf">Click here to Download Combined Merit List
         for 1st Phase(Part-II) Counselling</a>
      <a href="/otr/downloads/notice/Intimation.pdf">Download Intimation Letter for 1st phase
         (Part II) counselling of 2nd SLST 2025</a>
      <a href="/otr/downloads/panel.pdf">Notice for Publication of Provisional Panel and
         Waiting List</a>
      <a href="/x.pdf">Cut off for Document Verification for engagement of Act Apprentices</a>
      <a href="/home.html">Read our privacy policy and accessibility statement</a>
      <a href="/contact.html">Contact the commission office in Kolkata for queries</a>
    </body></html>
    """

    def test_stage_documents_are_recognised_as_notices(self):
        found = dn.extract_notices("https://www.westbengalssc.com/", self.LINKS, ["westbengalssc.com"])
        self.assertEqual(
            sorted(found),
            [
                "https://www.westbengalssc.com/otr/downloads/notice/Intimation.pdf",
                "https://www.westbengalssc.com/otr/downloads/notice/MeritList.pdf",
                "https://www.westbengalssc.com/otr/downloads/panel.pdf",
                "https://www.westbengalssc.com/x.pdf",
            ],
        )

    def test_chrome_links_are_still_ignored(self):
        found = dn.extract_notices("https://www.westbengalssc.com/", self.LINKS, ["westbengalssc.com"])
        self.assertNotIn("https://www.westbengalssc.com/home.html", found)
        self.assertNotIn("https://www.westbengalssc.com/contact.html", found)


class CentralListingTests(unittest.TestCase):
    """How a dated central-board listing row behaves."""

    PAGE = """
    <html><body>
      <table><tr>
        <td>15 Oct 26</td>
        <td><a href="http://ibpsreg.ibps.in/crpspxvimy26/presta_oct26/login.php?appid=x">
            Result Status of Online Preliminary Examination for CRP-SPL-XVI</a></td>
      </tr><tr>
        <td>01 Jul 26</td>
        <td><a href="/wp-content/uploads/Detailed-Notification-CRP-PO-XVI.pdf">
            Notification for Common Recruitment Process for CRP- PO/MTs-XVI</a></td>
      </tr><tr>
        <td>16 Jan 26</td>
        <td><a href="/wp-content/uploads/IBPS_CALENDAR_2026-27_final.pdf">
            Tentative Calendar of CRP (PSBs &amp; RRBs) Online Examinations</a></td>
      </tr></table>
    </body></html>
    """

    def test_https_notice_rows_are_found_and_plain_http_is_not(self):
        found = dn.extract_notices(
            "https://www.ibps.in/index.php/crp-updates/",
            self.PAGE,
            ["ibps.in"],
        )
        self.assertEqual(
            sorted(found),
            [
                "https://www.ibps.in/wp-content/uploads/Detailed-Notification-CRP-PO-XVI.pdf",
                "https://www.ibps.in/wp-content/uploads/IBPS_CALENDAR_2026-27_final.pdf",
            ],
        )

    def test_ampersand_in_visible_text_is_decoded(self):
        found = dn.extract_notices(
            "https://www.ibps.in/index.php/crp-updates/",
            self.PAGE,
            ["ibps.in"],
        )
        title = found["https://www.ibps.in/wp-content/uploads/IBPS_CALENDAR_2026-27_final.pdf"]
        self.assertIn("PSBs & RRBs", title)



class SeedTests(unittest.TestCase):
    def test_seed_records_links_and_reports_nothing(self):
        tmp = Path(tempfile.mkdtemp())
        sources = tmp / "sources.json"
        sources.write_text(
            json.dumps(
                {
                    "sources": [
                        {
                            "name": "PSC",
                            "url": "https://psc.wb.gov.in/",
                            "allowed_domains": ["psc.wb.gov.in"],
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        seen = tmp / "seen.json"
        seen.write_text(json.dumps({"https://psc.wb.gov.in/old.pdf": "2026-01-01"}), encoding="utf-8")
        out = tmp / "out.json"
        pages = {"html": {"https://psc.wb.gov.in/": PAGE}}

        def fake_fetch(url, timeout=dn.TIMEOUT_SECONDS):
            if url in pages["html"]:
                return pages["html"][url]
            raise RuntimeError("HTTP 404")

        with mock.patch.object(dn, "fetch_html", fake_fetch), mock.patch.object(
            dn, "SLEEP", lambda _seconds: None
        ):
            code = dn.main(
                [
                    "--sources", str(sources),
                    "--seen", str(seen),
                    "--out", str(out),
                    "--seed",
                ]
            )
        self.assertEqual(code, 0)
        report = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(report["new"], [])
        self.assertEqual(report["seeded"], 2)
        recorded = json.loads(seen.read_text(encoding="utf-8"))
        # The previously seen entry survives and the live ones are recorded, so
        # the next daily run cannot flood the tracker with historic notices.
        self.assertEqual(len(recorded), 3)
        self.assertIn("https://psc.wb.gov.in/old.pdf", recorded)


if __name__ == "__main__":
    unittest.main()
