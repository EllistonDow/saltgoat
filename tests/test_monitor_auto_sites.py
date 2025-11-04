import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "monitor_auto_sites.py"


class MonitorAutoSitesCLITest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.site_root = base / "sites"
        self.site_root.mkdir()
        self.nginx_dir = base / "nginx"
        self.nginx_dir.mkdir()
        self.monitor_file = base / "monitoring.sls"

    def run_cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            check=True,
            capture_output=True,
            text=True,
            env=env,
        )

    def write_site(self, name: str, url: str) -> None:
        site_dir = self.site_root / name / "app/etc"
        site_dir.mkdir(parents=True)
        (site_dir / "env.php").write_text("<?php return [];", encoding="utf-8")
        conf = self.nginx_dir / f"{name}.conf"
        conf.write_text(
            textwrap.dedent(
                f"""
                server {{
                    listen 443 ssl;
                    server_name {url};
                    set $MAGE_ROOT {self.site_root / name};
                    include {self.site_root / name}/nginx.conf.sample;
                }}
                """
            ),
            encoding="utf-8",
        )

    def load_output(self) -> dict:
        if not self.monitor_file.exists():
            return {}
        return yaml.safe_load(self.monitor_file.read_text(encoding="utf-8")) or {}

    def test_generate_and_remove_sites(self) -> None:
        self.write_site("bank", "bank.example.com")
        proc = self.run_cli(
            "--site-root",
            str(self.site_root),
            "--nginx-dir",
            str(self.nginx_dir),
            "--monitor-file",
            str(self.monitor_file),
            "--skip-salt-call",
            "--skip-systemctl",
        )
        self.assertIn("ADDED_SITES bank", proc.stdout)
        data = self.load_output()
        entry = data["saltgoat"]["monitor"]["sites"][0]
        self.assertEqual(entry["name"], "bank")
        self.assertTrue(entry["auto"])
        self.assertIn("php8.3-fpm", entry["timeout_services"])
        # Simulate site removal
        shutil.rmtree(self.site_root / "bank")
        proc = self.run_cli(
            "--site-root",
            str(self.site_root),
            "--nginx-dir",
            str(self.nginx_dir),
            "--monitor-file",
            str(self.monitor_file),
            "--skip-salt-call",
            "--skip-systemctl",
        )
        self.assertIn("REMOVED_SITES bank", proc.stdout)


if __name__ == "__main__":
    unittest.main()
