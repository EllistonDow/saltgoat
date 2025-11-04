import base64
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "pwa_helpers.py"


class PWAHelpersTest(unittest.TestCase):
    def run_cli(self, *args: str, input_data: str | None = None):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            input=input_data,
            text=True,
            capture_output=True,
            check=True,
        )

    def test_decode_b64_valid(self):
        payload = base64.b64encode(json.dumps({"foo": "bar"}).encode()).decode()
        proc = self.run_cli("decode-b64", "--data", payload)
        self.assertEqual(json.loads(proc.stdout), {"foo": "bar"})

    def test_decode_b64_invalid(self):
        proc = self.run_cli("decode-b64", "--data", "notbase64")
        self.assertEqual(proc.stdout.strip(), "{}")

    def test_apply_env(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = Path(tmp) / ".env"
            env.write_text("FOO=bar\n", encoding="utf-8")
            overrides = json.dumps({"FOO": "baz", "NEW": "value"})
            self.run_cli("apply-env", "--file", str(env), "--overrides", overrides)
            content = env.read_text(encoding="utf-8").strip().splitlines()
            self.assertIn("FOO=baz", content)
            self.assertIn("NEW=value", content)


if __name__ == "__main__":
    unittest.main()
