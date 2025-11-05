import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "minio_helper.py"


class MinioHelperCLITest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.pillar = Path(self.tmp.name) / "minio.sls"
        self.pillar.write_text(
            textwrap.dedent(
                """
                minio:
                  enabled: true
                  binary: /usr/local/bin/minio
                  data_dir: /srv/minio/data
                  config_dir: /etc/minio
                  listen_address: 0.0.0.0:9100
                  console_address: 0.0.0.0:9101
                  health:
                    scheme: http
                    host: 127.0.0.1
                    port: 9100
                    endpoint: /minio/health/live
                    timeout: 3
                  root_credentials:
                    access_key: testkey
                    secret_key: testsecret
                """
            ),
            encoding="utf-8",
        )

    def run_cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        return subprocess.run(
            [os.environ.get("PYTHON", "python3"), str(SCRIPT), "--pillar", str(self.pillar), *args],
            check=True,
            capture_output=True,
            text=True,
            env=env,
        )

    def test_info_outputs_json(self) -> None:
        proc = self.run_cli("info")
        data = json.loads(proc.stdout)
        self.assertEqual(data["listen"], "0.0.0.0:9100")
        self.assertEqual(data["root_user"], "testkey")
        self.assertIn("health_url", data)
        self.assertTrue(data["health_url"].startswith("http://127.0.0.1:9100"))

    def test_health_url(self) -> None:
        proc = self.run_cli("health-url")
        self.assertEqual(proc.stdout.strip(), "http://127.0.0.1:9100/minio/health/live")


if __name__ == "__main__":
    unittest.main()
