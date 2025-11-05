import json
import tempfile
import unittest
from pathlib import Path

from modules.lib import notification
from modules.lib import backup_notify


class NotificationQueueTestCase(unittest.TestCase):
    def test_queue_failure_writes_record(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            queue_dir = Path(tmp)
            original_dir = notification.QUEUE_DIR
            try:
                notification.QUEUE_DIR = queue_dir
                notification.queue_failure(
                    "telegram",
                    "saltgoat/test",
                    {"message": "hello"},
                    error="timeout",
                    context={"chat_id": "123"},
                )
            finally:
                notification.QUEUE_DIR = original_dir

            files = list(queue_dir.glob("*.json"))
            self.assertEqual(len(files), 1)
            data = json.loads(files[0].read_text(encoding="utf-8"))
            self.assertEqual(data["destination"], "telegram")
            self.assertEqual(data["tag"], "saltgoat/test")
            self.assertEqual(data["payload"]["message"], "hello")
            self.assertEqual(data["context"]["chat_id"], "123")

    def test_dispatch_webhooks_queue_on_failure(self) -> None:
        original_cache = notification._CACHE
        original_queue_dir = notification.QUEUE_DIR
        original_urlopen = notification.urllib.request.urlopen  # type: ignore[attr-defined]
        try:
            notification._CACHE = {
                "webhooks": [{"url": "https://example.invalid/webhook"}],
            }
            with tempfile.TemporaryDirectory() as tmp:
                notification.QUEUE_DIR = Path(tmp)

                def fail_urlopen(*_args, **_kwargs):
                    raise RuntimeError("connection refused")

                notification.urllib.request.urlopen = fail_urlopen  # type: ignore[attr-defined]
                notification.dispatch_webhooks(
                    "saltgoat/test",
                    "INFO",
                    "demo",
                    "plain text",
                    "<b>html</b>",
                    {"foo": "bar"},
                )
                files = list(Path(tmp).glob("*.json"))
                self.assertEqual(len(files), 1)
                payload = json.loads(files[0].read_text(encoding="utf-8"))
                self.assertEqual(payload["destination"], "webhook")
                self.assertEqual(payload["tag"], "saltgoat/test")
                self.assertEqual(payload["payload"]["payload"]["foo"], "bar")
                self.assertIn("connection refused", payload["error"])
        finally:
            notification._CACHE = original_cache
            notification.QUEUE_DIR = original_queue_dir
            notification.urllib.request.urlopen = original_urlopen  # type: ignore[attr-defined]

    def test_backup_notify_queue_failure_on_telegram_error(self) -> None:
        original_unit_test = backup_notify.UNIT_TEST
        original_path_exists = backup_notify._path_exists
        original_reactor = backup_notify.reactor_common
        original_log = backup_notify._log
        original_dispatch = notification.dispatch_webhooks
        original_should_send = notification.should_send
        original_parse_mode = notification.get_parse_mode
        queue_dir = tempfile.TemporaryDirectory()
        temp_dir = tempfile.TemporaryDirectory()
        original_config = backup_notify.TELEGRAM_CONFIG
        backup_notify.TELEGRAM_CONFIG = Path(temp_dir.name) / "telegram.json"
        backup_notify.TELEGRAM_CONFIG.write_text("{}", encoding="utf-8")
        notification_queue_dir = Path(queue_dir.name)
        original_queue_dir = notification.QUEUE_DIR

        class DummyReactor:
            @staticmethod
            def load_telegram_profiles(_config, _logger):
                return [{"chat_id": "123"}]

            @staticmethod
            def broadcast_telegram(*_args, **_kwargs):
                raise RuntimeError("telegram down")

        try:
            backup_notify.UNIT_TEST = False
            backup_notify._path_exists = lambda _path: True  # type: ignore[assignment]
            backup_notify._log = lambda *args, **kwargs: None  # type: ignore[assignment]
            backup_notify.reactor_common = DummyReactor()
            notification.dispatch_webhooks = lambda *args, **kwargs: 0  # type: ignore[assignment]
            notification.should_send = lambda *args, **kwargs: True  # type: ignore[assignment]
            notification.get_parse_mode = lambda: "HTML"  # type: ignore[assignment]
            notification.QUEUE_DIR = notification_queue_dir

            payload = {"severity": "INFO", "site": "bank", "telegram_thread": 321}
            backup_notify._send(
                "saltgoat/backup/mysql_dump/bank",
                "plain text",
                "<b>html</b>",
                payload.copy(),
                "bank",
            )

            files = list(notification_queue_dir.glob("*.json"))
            self.assertEqual(len(files), 1)
            data = json.loads(files[0].read_text(encoding="utf-8"))
            self.assertEqual(data["destination"], "telegram")
            self.assertEqual(data["tag"], "saltgoat/backup/mysql_dump/bank")
            self.assertEqual(data["payload"]["site"], "bank")
            self.assertEqual(data["context"]["thread"], 321)
            self.assertIn("telegram down", data["error"])
        finally:
            backup_notify.UNIT_TEST = original_unit_test
            backup_notify._path_exists = original_path_exists  # type: ignore[assignment]
            backup_notify.reactor_common = original_reactor
            backup_notify._log = original_log  # type: ignore[assignment]
            backup_notify.TELEGRAM_CONFIG = original_config
            notification.dispatch_webhooks = original_dispatch  # type: ignore[assignment]
            notification.should_send = original_should_send  # type: ignore[assignment]
            notification.get_parse_mode = original_parse_mode  # type: ignore[assignment]
            notification.QUEUE_DIR = original_queue_dir
            queue_dir.cleanup()
            temp_dir.cleanup()


if __name__ == "__main__":
    unittest.main()
