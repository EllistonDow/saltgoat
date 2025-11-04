#!/usr/bin/env python3
import json
import os
import subprocess
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "backup_notify.py"


class BackupNotifyCliTests(unittest.TestCase):
    def run_cli(self, args):
        env = os.environ.copy()
        env["SALTGOAT_UNIT_TEST"] = "1"
        result = subprocess.run(
            ["python3", str(SCRIPT), *args],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            env=env,
            check=True,
        )
        self.assertTrue(result.stdout.strip(), "CLI emitted empty output")
        return json.loads(result.stdout.strip())

    def test_mysql_success(self):
        data = self.run_cli(
            [
                "mysql",
                "--status",
                "success",
                "--database",
                "bank",
                "--path",
                "/tmp/dump.sql",
                "--size",
                "10MB",
                "--site",
                "bank",
                "--host",
                "host1",
            ]
        )
        self.assertEqual(data["tag"], "saltgoat/backup/mysql_dump/bank")
        self.assertEqual(data["payload"]["severity"], "INFO")

    def test_restic_failure(self):
        data = self.run_cli(
            [
                "restic",
                "--status",
                "failure",
                "--repo",
                "/var/backups/restic/bank",
                "--site",
                "bank",
                "--log-file",
                "/var/log/restic/bank.log",
                "--paths",
                "/var/www/bank,/etc/nginx",
                "--tags",
                "bank,magento",
                "--return-code",
                "3",
                "--origin",
                "manual",
                "--host",
                "host1",
            ]
        )
        self.assertEqual(data["tag"], "saltgoat/backup/restic/bank")
        self.assertEqual(data["payload"]["severity"], "ERROR")


if __name__ == "__main__":
    unittest.main()
