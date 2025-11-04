#!/usr/bin/env python3
import os
import subprocess
import tempfile
from pathlib import Path
import unittest

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "restic_helpers.py"


class ResticHelpersCLITests(unittest.TestCase):
    def run_cli(self, *args, env=None):
        base_env = os.environ.copy()
        if env:
            base_env.update(env)
        result = subprocess.run(
            ["python3", str(SCRIPT), *args],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            env=base_env,
            check=True,
        )
        return result.stdout.strip()

    def test_random_secret_length(self):
        out = self.run_cli("random-secret")
        self.assertEqual(len(out), 24)

    def test_normalize_path(self):
        out = self.run_cli("normalize-path", "./modules/lib")
        self.assertTrue(out.endswith("modules/lib"))

    def test_summarize_sites_skip_restic(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            meta = Path(tmpdir) / "bank.env"
            meta.write_text(
                "\n".join([
                    "SITE=bank",
                    "REPO=/var/backups/restic/bank",
                    "ENV_FILE=/etc/restic/restic.env",
                    "SERVICE_NAME=saltgoat-restic-bank.service",
                ])
            )
            out = self.run_cli(
                "summarize-sites",
                "--metadata-dir",
                tmpdir,
                "--skip-restic",
                env={"SALTGOAT_UNIT_TEST": "1"},
            )
            self.assertIn("bank", out)


if __name__ == "__main__":
    unittest.main()
