#!/usr/bin/env python3
"""
Lightweight tests for modules/magetools/magento_api_watch.py.
"""

import os
import tempfile
import unittest
import urllib.request
from pathlib import Path

# 启用测试模式，跳过 root / Salt 依赖
os.environ.setdefault("MAGENTO_WATCHER_TEST_MODE", "1")

from modules.magetools import magento_api_watch as watcher_mod  # noqa: E402


class DummyCaller:
    def __init__(self):
        self.events = []

    def cmd(self, function: str, *args, **kwargs):
        if function == "pillar.get":
            return ""
        if function == "event.send":
            tag = args[0]
            data = args[1] if len(args) > 1 else {}
            self.events.append((tag, data))
            return True
        return {}


class MagentoApiWatchTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.prev_state_root = watcher_mod.STATE_ROOT
        self.prev_caller = watcher_mod.CALLER
        self.prev_broadcast = watcher_mod.telegram_broadcast
        self.prev_log = watcher_mod.LOG

        watcher_mod.STATE_ROOT = Path(self.tempdir.name)
        watcher_mod.CALLER = DummyCaller()
        watcher_mod.telegram_broadcast = lambda *args, **kwargs: None
        watcher_mod.LOG = lambda *_args, **_kwargs: None

    def tearDown(self) -> None:
        watcher_mod.STATE_ROOT = self.prev_state_root
        watcher_mod.CALLER = self.prev_caller
        watcher_mod.telegram_broadcast = self.prev_broadcast
        watcher_mod.LOG = self.prev_log
        self.tempdir.cleanup()

    def test_process_orders_paginates_and_emits_events(self) -> None:
        watcher = watcher_mod.MagentoWatcher(
            "bank",
            "https://example.com",
            "token",
            ["orders"],
            page_size=2,
            max_pages=5,
        )
        watcher._save_last_id("orders", 100)

        pages = []

        def fake_request(path, params):
            pages.append(int(params["searchCriteria[current_page]"]))
            if pages[-1] == 1:
                return {"items": [{"entity_id": 101}, {"entity_id": 102}]}
            if pages[-1] == 2:
                return {"items": [{"entity_id": 103}]}
            return {"items": []}

        watcher._request = fake_request  # type: ignore[assignment]
        watcher.process_orders()

        self.assertEqual([1, 2], pages)
        self.assertEqual(103, watcher._load_last_id("orders"))
        events = watcher_mod.CALLER.events
        self.assertEqual(3, len(events))
        self.assertTrue(all(tag == "saltgoat/business/order" for tag, _ in events))

    def test_oauth1_header_contains_signature(self) -> None:
        watcher = watcher_mod.MagentoWatcher(
            "bank",
            "https://example.com",
            "token",
            ["orders"],
            auth_mode="oauth1",
            oauth_params={
                "consumer_key": "ckey",
                "consumer_secret": "csecret",
                "access_token": "atok",
                "access_token_secret": "asecret",
            },
        )
        params = [("searchCriteria[current_page]", "1")]
        req = urllib.request.Request("https://example.com/rest/V1/orders")
        watcher._apply_auth(req, "GET", "https://example.com/rest/V1/orders", params)
        header = req.get_header("Authorization")
        self.assertIsNotNone(header)
        assert header is not None
        self.assertTrue(header.startswith("OAuth "))
        self.assertIn('oauth_consumer_key="ckey"', header)
        self.assertIn('oauth_token="atok"', header)
        self.assertIn("oauth_signature=", header)

    def test_bootstrap_only_requests_first_page(self) -> None:
        watcher = watcher_mod.MagentoWatcher(
            "bank",
            "https://example.com",
            "token",
            ["orders"],
            page_size=2,
        )

        watcher._bootstrap_last_id = lambda *args, **kwargs: 0  # type: ignore[assignment]
        calls = []

        def fake_request(path, params):
            calls.append(params["searchCriteria[current_page]"])
            return {"items": [{"entity_id": 5}, {"entity_id": 6}]}

        watcher._request = fake_request  # type: ignore[assignment]
        watcher_mod.CALLER.events.clear()
        watcher.process_orders()
        self.assertEqual([1], calls)
        self.assertEqual(6, watcher._load_last_id("orders"))
        self.assertEqual([], watcher_mod.CALLER.events)


if __name__ == "__main__":
    unittest.main()
