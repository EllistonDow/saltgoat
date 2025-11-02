#!/usr/bin/env python3
"""
Regression tests for modules/magetools/magento_summary.py.
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path

# Ensure watcher module runs in test mode (skip root / Salt deps)
os.environ.setdefault("MAGENTO_WATCHER_TEST_MODE", "1")

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(REPO_ROOT / "modules" / "magetools"))

from modules.magetools import magento_summary as summary  # noqa: E402
from modules.magetools import magento_api_watch as watcher_mod  # noqa: E402


class MagentoSummaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        # Redirect watcher state to tempdir so tests don't touch real paths
        self.prev_state_root = watcher_mod.STATE_ROOT
        watcher_mod.STATE_ROOT = Path(self.tempdir.name)

        # Stub side-effects
        self.prev_log = summary.log_to_file
        self.prev_emit = summary.emit_event
        self.prev_tele = summary.telegram_broadcast
        summary.log_to_file = lambda *args, **kwargs: None
        summary.emit_event = lambda *args, **kwargs: None
        summary.telegram_broadcast = lambda *args, **kwargs: None

    def tearDown(self) -> None:
        summary.log_to_file = self.prev_log
        summary.emit_event = self.prev_emit
        summary.telegram_broadcast = self.prev_tele
        watcher_mod.STATE_ROOT = self.prev_state_root
        self.tempdir.cleanup()

    def test_fetch_entities_uses_distinct_from_to_filters(self) -> None:
        start, end, _ = summary.period_range("daily")
        watcher = watcher_mod.MagentoWatcher(
            "demo",
            "https://example.com",
            "tok",
            ["orders"],
            page_size=5,
        )

        captured = []

        def fake_request(path, params):
            captured.append(params)
            return {"items": [], "total_count": 0}

        watcher._request = fake_request  # type: ignore[assignment]
        list(
            summary.fetch_entities(
                watcher,
                "/rest/V1/orders",
                "entity_id",
                start,
                end,
            )
        )

        self.assertTrue(captured, "fetch_entities should invoke _request at least once")
        params = captured[0]
        self.assertEqual(
            "from",
            params.get("searchCriteria[filter_groups][0][filters][0][condition_type]"),
        )
        self.assertEqual(
            "to",
            params.get("searchCriteria[filter_groups][1][filters][0][condition_type]"),
        )
        self.assertNotEqual(
            params.get("searchCriteria[filter_groups][0][filters][0][value]"),
            params.get("searchCriteria[filter_groups][1][filters][0][value]"),
            "from/to filters should be populated independently",
        )


if __name__ == "__main__":
    unittest.main()
