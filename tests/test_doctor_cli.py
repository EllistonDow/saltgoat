import json
import os
import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DOCTOR_SCRIPT = REPO_ROOT / "modules" / "lib" / "doctor.py"


class DoctorCLITests(unittest.TestCase):
    def setUp(self) -> None:
        self.env = os.environ.copy()
        self.env["SALTGOAT_UNIT_TEST"] = "1"

    def test_json_format_output(self) -> None:
        result = subprocess.run(
            ["python3", str(DOCTOR_SCRIPT), "--format", "json"],
            cwd=REPO_ROOT,
            env=self.env,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        )
        payload = json.loads(result.stdout)
        self.assertIn("timestamp", payload)
        self.assertIn("host", payload)
        self.assertTrue(payload["goat_pulse"].startswith("[stub]"))
        self.assertIn("[stub] df -h / /var/lib/mysql", payload["disk"])

    def test_markdown_format_contains_sections(self) -> None:
        result = subprocess.run(
            ["python3", str(DOCTOR_SCRIPT), "--format", "markdown"],
            cwd=REPO_ROOT,
            env=self.env,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        )
        output = result.stdout
        self.assertIn("# SaltGoat Doctor Snapshot", output)
        self.assertIn("## Goat Pulse", output)
        self.assertIn("## Disk Usage", output)
        self.assertIn("## Top Memory Processes", output)


if __name__ == "__main__":
    unittest.main()
