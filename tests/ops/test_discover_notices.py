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
    def _run(self, seen_initial, pages):
        tmp = Path(tempfile.mkdtemp())
        sources = tmp / "sources.json"
        sources.write_text(
            json.dumps(
                {
                    "sources": [
                        {
                            "name": name,
                            "url": url,
                            "allowed_domains": [domain],
                        }
                        for name, (url, domain) in pages["config"].items()
                    ]
                }
            ),
            encoding="utf-8",
        )
        seen = tmp / "seen.json"
        if seen_initial is not None:
            seen.write_text(json.dumps(seen_initial), encoding="utf-8")
        out = tmp / "out.json"

        def fake_fetch(url):
            if url in pages["html"]:
                return pages["html"][url]
            raise RuntimeError("HTTP 404")

        with mock.patch.object(dn, "fetch_html", side_effect=fake_fetch):
            code = dn.main(
                ["--sources", str(sources), "--seen", str(seen), "--out", str(out)]
            )
        report = json.loads(out.read_text(encoding="utf-8")) if out.exists() else None
        return code, report, seen

    def setUp(self):
        self.pages = {
            "config": {"PSC": ("https://psc.wb.gov.in/", "psc.wb.gov.in")},
            "html": {"https://psc.wb.gov.in/": PAGE},
        }

    def test_first_run_is_baseline_and_reports_nothing(self):
        code, out, seen_path = self._run(None, self.pages)
        self.assertEqual(code, 0)
        self.assertEqual(out["new"], [])
        recorded = json.loads(seen_path.read_text(encoding="utf-8"))
        self.assertEqual(len(recorded), 2)

    def test_later_run_reports_only_unseen_links(self):
        seen = {"https://psc.wb.gov.in/Download?param1=x.pdf": "2026-10-19"}
        code, out, _ = self._run(seen, self.pages)
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
        code, report, _ = self._run({}, pages)
        self.assertEqual(code, 1)
        self.assertIsNone(report)


if __name__ == "__main__":
    unittest.main()
