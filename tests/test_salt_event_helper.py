import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "salt_event.py"


class SaltEventHelperTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_send_with_stubbed_salt(self) -> None:
        stub_dir = Path(self.tmp.name) / "stub"
        (stub_dir / "salt").mkdir(parents=True)
        (stub_dir / "salt/__init__.py").write_text("", encoding="utf-8")
        (stub_dir / "salt/client.py").write_text(
            textwrap.dedent(
                """
                import json
                import os

                class Caller:
                    def cmd(self, func, tag, data):
                        log_path = os.environ.get("SALTGOAT_EVENT_LOG")
                        if log_path:
                            with open(log_path, "a", encoding="utf-8") as fh:
                                fh.write(json.dumps({"func": func, "tag": tag, "data": data}))
                """
            ),
            encoding="utf-8",
        )
        log_path = Path(self.tmp.name) / "events.log"
        env = os.environ.copy()
        env["PYTHONPATH"] = f"{stub_dir}:{env.get('PYTHONPATH', '')}"
        env["SALTGOAT_EVENT_LOG"] = str(log_path)
        subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "send",
                "--tag",
                "saltgoat/test",
                "site=bank",
                "status=success",
            ],
            check=True,
            env=env,
        )
        contents = log_path.read_text(encoding="utf-8")
        record = json.loads(contents)
        self.assertEqual(record["func"], "event.send")
        self.assertEqual(record["tag"], "saltgoat/test")
        self.assertEqual(record["data"]["site"], "bank")

    def test_fallback_outputs_json(self) -> None:
        env = os.environ.copy()
        env["SALTGOAT_FORCE_EVENT_FALLBACK"] = "1"
        proc = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "send",
                "--tag",
                "saltgoat/test",
                "site=tank",
            ],
            capture_output=True,
            text=True,
            env=env,
        )
        self.assertEqual(proc.returncode, 2)
        payload = json.loads(proc.stdout.strip())
        self.assertEqual(payload["site"], "tank")

    def test_format_outputs_json(self) -> None:
        proc = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "format",
                "--tag",
                "saltgoat/test",
                "site=pwas",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        payload = json.loads(proc.stdout.strip())
        self.assertEqual(payload["site"], "pwas")


if __name__ == "__main__":
    unittest.main()
