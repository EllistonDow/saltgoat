import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "maintenance_pillar.py"


class MaintenancePillarTest(unittest.TestCase):
    def run_helper(self, extra_env: dict[str, str]) -> dict:
        env = os.environ.copy()
        env.update(extra_env)
        proc = subprocess.run(
            [sys.executable, str(SCRIPT)],
            capture_output=True,
            text=True,
            check=True,
            env=env,
        )
        return json.loads(proc.stdout.strip())

    def test_basic_payload(self) -> None:
        payload = self.run_helper(
            {
                "SITE_NAME": "bank",
                "SITE_PATH": "/var/www/bank",
                "ALLOW_VALKEY_FLUSH": "1",
                "BACKUP_KEEP_DAYS": "5",
                "RESTIC_EXTRA_PATHS": "/tmp/foo;/tmp/bar",
            }
        )
        self.assertEqual(payload["site_name"], "bank")
        self.assertEqual(payload["site_path"], "/var/www/bank")
        self.assertTrue(payload["allow_valkey_flush"])
        self.assertEqual(payload["backup_keep_days"], 5)
        self.assertEqual(payload["restic_extra_paths"], ["/tmp/foo", "/tmp/bar"])

    def test_static_jobs_cast(self) -> None:
        payload = self.run_helper(
            {
                "SITE_NAME": "tank",
                "STATIC_JOBS": "6",
                "STATIC_LANGS": "en_US,zh_CN",
            }
        )
        self.assertEqual(payload["static_jobs"], 6)
        self.assertEqual(payload["static_languages"], "en_US,zh_CN")


if __name__ == "__main__":
    unittest.main()
