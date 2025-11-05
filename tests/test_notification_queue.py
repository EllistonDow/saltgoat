import json
import tempfile
import unittest
from pathlib import Path

from modules.lib import notification


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


if __name__ == "__main__":
    unittest.main()
