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

    def test_render_scripts(self):
        payload = json.dumps(
            {
                "local": {
                    "scripts": [
                        {"name": "demo", "path": "/srv/demo.sh", "modified": "2025-01-01", "size": 128}
                    ]
                }
            }
        )
        proc = self.run_cmd("render-scripts", "--json", payload)
        self.assertIn("- demo", proc.stdout)
        empty = self.run_cmd("render-scripts", "--json", json.dumps({"local": {"scripts": []}}))
        self.assertIn("暂无脚本", empty.stdout)

    def test_render_jobs(self):
        payload = json.dumps(
            {
                "local": {
                    "jobs": [
                        {
                            "name": "nightly",
                            "enabled": True,
                            "backend": "cron",
                            "active": False,
                            "cron": "0 3 * * *",
                            "script_path": "/srv/demo.sh",
                            "last_run": "2025-01-01 03:00",
                            "last_retcode": 0,
                        }
                    ]
                }
            }
        )
        proc = self.run_cmd("render-jobs", "--json", payload)
        self.assertIn("nightly", proc.stdout)
        empty = self.run_cmd("render-jobs", "--json", json.dumps({"local": {"jobs": []}}))
        self.assertIn("暂无任务", empty.stdout)


if __name__ == "__main__":
    unittest.main()
