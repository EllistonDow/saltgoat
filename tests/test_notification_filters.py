import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from modules.lib import notification as notif


class NotificationFilterTests(unittest.TestCase):
    def setUp(self) -> None:
        notif._CACHE = None  # reset cache between tests

    def _set_pillar(self, data):
        notif._CACHE = None
        with mock.patch("modules.lib.notification.pillar_get", return_value=data):
            notif.load_config(reload=True)

    def test_global_min_severity(self):
        self._set_pillar({"telegram": {"enabled": True, "min_severity": "WARNING"}})
        self.assertFalse(notif.should_send("saltgoat/test", "INFO"))
        self.assertTrue(notif.should_send("saltgoat/test", "ERROR"))

    def test_disabled_tag_prefix(self):
        self._set_pillar({"telegram": {"disabled_tags": ["saltgoat/business"]}})
        self.assertFalse(notif.should_send("saltgoat/business/order", "ERROR"))
        self.assertTrue(notif.should_send("saltgoat/backup/mysql", "ERROR"))

    def test_site_override(self):
        self._set_pillar(
            {
                "telegram": {
                    "min_severity": "INFO",
                    "site_overrides": {
                        "bank": {
                            "min_severity": "ERROR",
                            "disabled_tags": ["saltgoat/autoscale/bank"],
                        }
                    },
                }
            }
        )
        self.assertFalse(notif.should_send("saltgoat/business/order/bank", "NOTICE", site="bank"))
        self.assertFalse(notif.should_send("saltgoat/autoscale/bank", "CRITICAL", site="bank"))
        self.assertTrue(notif.should_send("saltgoat/business/order/tank", "NOTICE", site="tank"))

    def test_parse_mode_passthrough(self):
        self._set_pillar({"telegram": {"parse_mode": "Markdown"}})
        self.assertEqual(notif.get_parse_mode(), "Markdown")

    def test_format_pre_block(self):
        plain, html_block = notif.format_pre_block(
            "TEST TITLE",
            "SITE",
            [("Field", "Value"), ("Empty", None), ("Multiline", "Line1\nLine2")],
        )
        self.assertIn("TEST TITLE", plain)
        self.assertIn("Line2", plain)
        self.assertTrue(html_block.startswith("<pre>"))
        self.assertIn("TEST TITLE", html_block)


if __name__ == "__main__":
    unittest.main()
