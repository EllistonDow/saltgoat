import unittest

from modules.lib import notification


class NotificationFilterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.original_pillar_get = notification.pillar_get
        notification._CACHE = None

        def fake_pillar_get(path: str, default=None):
            if path == "notifications":
                return {
                    "telegram": {
                        "enabled": True,
                        "min_severity": "NOTICE",
                        "disabled_tags": ["saltgoat/debug"],
                        "site_overrides": {
                            "bank": {
                                "min_severity": "ERROR",
                                "disabled_tags": ["saltgoat/orders/bank/summary"],
                            }
                        },
                    }
                }
            return default

        notification.pillar_get = fake_pillar_get
        notification.load_config(reload=True)

    def tearDown(self) -> None:
        notification.pillar_get = self.original_pillar_get
        notification._CACHE = None

    def test_global_min_level_blocks_low_severity(self) -> None:
        self.assertFalse(notification.should_send("saltgoat/general", "INFO"))
        self.assertTrue(notification.should_send("saltgoat/general", "NOTICE"))

    def test_global_disabled_tag(self) -> None:
        self.assertFalse(notification.should_send("saltgoat/debug/tooling", "WARNING"))

    def test_site_override_min_level(self) -> None:
        self.assertFalse(notification.should_send("saltgoat/orders/bank", "WARNING"))
        self.assertTrue(notification.should_send("saltgoat/orders/bank", "ERROR"))

    def test_site_override_disabled_tag(self) -> None:
        self.assertFalse(
            notification.should_send("saltgoat/orders/bank/summary", "CRITICAL", site="bank")
        )

    def test_inferred_site_slug(self) -> None:
        # Site inferred from tag suffix
        self.assertTrue(notification.should_send("saltgoat/alerts/pwas", "ERROR"))


if __name__ == "__main__":
    unittest.main()
