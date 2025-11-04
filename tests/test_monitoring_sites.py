import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "monitoring_sites.py"


class MonitoringSitesCLITest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.pillar = Path(self.tmp.name) / "monitoring.sls"

    def run_cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            check=True,
            capture_output=True,
            text=True,
            env=env,
        )

    def load_yaml(self) -> dict:
        if not self.pillar.exists():
            return {}
        return yaml.safe_load(self.pillar.read_text(encoding="utf-8")) or {}

    def test_upsert_creates_entry(self) -> None:
        self.run_cli(
            "upsert",
            "--file",
            str(self.pillar),
            "--site",
            "bank",
            "--domain",
            "bank.example.com",
        )
        data = self.load_yaml()
        site = data["saltgoat"]["monitor"]["sites"][0]
        self.assertEqual(site["name"], "bank")
        self.assertEqual(site["url"], "https://bank.example.com/")
        self.assertTrue(site["auto"])
        self.assertIn("php8.3-fpm", site["timeout_services"])

    def test_upsert_updates_existing_entry(self) -> None:
        self.test_upsert_creates_entry()
        self.run_cli(
            "upsert",
            "--file",
            str(self.pillar),
            "--site",
            "bank",
            "--domain",
            "bank.example.com",
            "--manual",
            "--timeout",
            "10",
        )
        data = self.load_yaml()
        site = data["saltgoat"]["monitor"]["sites"][0]
        self.assertFalse(site["auto"])
        self.assertEqual(site["timeout"], 10)

    def test_remove_entry(self) -> None:
        self.test_upsert_creates_entry()
        self.run_cli("remove", "--file", str(self.pillar), "--site", "bank")
        data = self.load_yaml()
        self.assertEqual(data["saltgoat"]["monitor"]["sites"], [])


if __name__ == "__main__":
    unittest.main()
