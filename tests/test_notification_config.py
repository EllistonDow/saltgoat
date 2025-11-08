import os
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest import mock

from modules.lib import notification


class NotificationConfigFallbackTest(unittest.TestCase):
    def setUp(self) -> None:
        self._cache_backup = notification._CACHE
        notification._CACHE = None
        self.tmp = tempfile.NamedTemporaryFile("w", delete=False)
        self.tmp.write(
            textwrap.dedent(
                """\
                notifications:
                  telegram:
                    enabled: false
                    min_severity: WARNING
                  webhook:
                    enabled: true
                    endpoints:
                      - name: mattermost
                        url: https://example.com/hooks/demo
                        headers:
                          X-Auth: token
                """
            )
        )
        self.tmp.flush()
        self.tmp.close()
        self._fallback_backup = notification.FALLBACK_NOTIFICATIONS_PATH
        notification.FALLBACK_NOTIFICATIONS_PATH = Path(self.tmp.name)

    def tearDown(self) -> None:
        notification._CACHE = None
        notification.FALLBACK_NOTIFICATIONS_PATH = self._fallback_backup
        try:
            os.unlink(self.tmp.name)
        except FileNotFoundError:
            pass

    def test_load_config_uses_fallback_file(self) -> None:
        with mock.patch.object(notification, "pillar_get", return_value={}):
            cfg = notification.load_config(reload=True)
        self.assertEqual(cfg["min_level"], "WARNING")
        self.assertFalse(cfg["enabled"])
        webhooks = cfg.get("webhooks")
        self.assertIsInstance(webhooks, list)
        self.assertEqual(webhooks[0]["url"], "https://example.com/hooks/demo")
        self.assertEqual(webhooks[0]["headers"]["X-Auth"], "token")


if __name__ == "__main__":
    unittest.main()

