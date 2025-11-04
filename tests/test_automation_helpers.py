import json
import subprocess
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "automation_helpers.py"


class AutomationHelperTest(unittest.TestCase):
    def run_cmd(self, *args: str, input_data: str | None = None, expect_ok: bool = True):
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            input=input_data,
            text=True,
            capture_output=True,
        )
        if expect_ok:
            self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc

    def payload(self):
        return json.dumps({"local": {"result": True, "comment": "OK", "path": "/tmp/foo"}})

    def test_render_basic(self):
        proc = self.run_cmd("render-basic", "--json", self.payload())
        self.assertIn("OK", proc.stdout)

    def test_extract_field(self):
        proc = self.run_cmd("extract-field", "path", "--json", self.payload())
        self.assertEqual(proc.stdout.strip(), "/tmp/foo")

    def test_parse_paths_defaults(self):
        payload = json.dumps({"local": {"paths": {"base_dir": "/srv/base"}}})
        proc = self.run_cmd("parse-paths", "--json", payload)
        lines = proc.stdout.strip().splitlines()
        self.assertEqual(lines[0], "/srv/base")
        self.assertEqual(lines[1], "/srv/base/scripts")


if __name__ == "__main__":
    unittest.main()
