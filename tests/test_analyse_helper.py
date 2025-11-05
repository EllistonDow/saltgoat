import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "analyse_helper.py"


class AnalyseHelperTest(unittest.TestCase):
    def run_cli(self, *args: str, env=None, expect_ok=True):
        cmd = [sys.executable, str(SCRIPT), *args]
        proc = subprocess.run(
            cmd,
            text=True,
            capture_output=True,
            env=env,
        )
        if expect_ok:
            self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc

    def test_diff_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            diff_file = Path(tmp) / "diff.json"
            diff_file.write_text(
                json.dumps({"before_reference": "foo\n", "after_reference": "bar\n"}),
                encoding="utf-8",
            )
            proc = self.run_cli("diff", "--file", str(diff_file))
            self.assertIn("-foo", proc.stdout)
            self.assertIn("+bar", proc.stdout)

    def test_random_password(self):
        proc = self.run_cli("random-password", "--length", "32")
        password = proc.stdout.strip()
        self.assertEqual(len(password), 32)
        self.assertTrue(all(ch.isalnum() for ch in password))

    def test_matomo_override(self):
        proc = self.run_cli(
            "matomo-override",
            "--install-dir",
            "/var/www/matomo",
            "--domain",
            "matomo.local",
            "--php-socket",
            "/run/php/php8.3-fpm.sock",
            "--owner",
            "www-data",
            "--group",
            "www-data",
            "--db-enabled",
            "--db-name",
            "matomo",
            "--db-user",
            "matomo",
        )
        data = json.loads(proc.stdout)
        self.assertEqual(data["matomo"]["domain"], "matomo.local")
        self.assertIn("db", data["matomo"])
        self.assertTrue(data["matomo"]["db"]["enabled"])


if __name__ == "__main__":
    unittest.main()
