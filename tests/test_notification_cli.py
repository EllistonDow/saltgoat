import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


class NotificationCLITest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.NamedTemporaryFile("w", delete=False)
        self.tmp.write(
            textwrap.dedent(
                """\
                notifications:
                  telegram:
                    enabled: false
                  webhook:
                    enabled: false
                """
            )
        )
        self.tmp.flush()
        self.tmp.close()
        self.env = os.environ.copy()
        self.env["SALTGOAT_NOTIFICATIONS_FILE"] = self.tmp.name
        self.env["SALTGOAT_SKIP_PILLAR"] = "1"

    def tearDown(self) -> None:
        try:
            os.unlink(self.tmp.name)
        except FileNotFoundError:
            pass

    def test_notification_test_script_runs_with_stub_config(self) -> None:
        repo_root = Path(__file__).resolve().parents[1]
        proc = subprocess.run(
            [
                "python3",
                "scripts/notification-test.py",
                "--tag",
                "saltgoat/test/ping",
                "--severity",
                "INFO",
                "--text",
                "CLI self-test",
                "--webhook-only",
            ],
            cwd=repo_root,
            env=self.env,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Webhook delivered:", proc.stdout)


if __name__ == "__main__":
    unittest.main()
