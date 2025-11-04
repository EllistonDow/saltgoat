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


if __name__ == "__main__":
    unittest.main()
