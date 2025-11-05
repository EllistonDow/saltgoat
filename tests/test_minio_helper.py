import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "minio_helper.py"
sys_path_added = False
import sys
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
    sys_path_added = True

from modules.lib import minio_helper  # type: ignore  # noqa: E402


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
                    verify: true
                  root_credentials:
                    access_key: testkey
                    secret_key: testsecret
                """
            ),
            encoding="utf-8",
        )
        self.disabled = Path(self.tmp.name) / "disabled.sls"
        self.disabled.write_text(
            textwrap.dedent(
                """
                minio:
                  enabled: false
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
        self.assertEqual(data["service"], "minio")
        self.assertIn("health_url", data)
        self.assertTrue(data["health_url"].startswith("http://127.0.0.1:9100"))

    def test_health_url(self) -> None:
        proc = self.run_cli("health-url")
        self.assertEqual(proc.stdout.strip(), "http://127.0.0.1:9100/minio/health/live")

    def test_load_enabled_config(self) -> None:
        cfg = minio_helper.load_enabled_config(self.pillar)
        self.assertIsNotNone(cfg)
        assert cfg is not None
        self.assertEqual(cfg.listen_port, 9100)
        self.assertTrue(cfg.health_verify)
        self.assertEqual(cfg.root_user, "testkey")
        self.assertEqual(cfg.service_name, "minio")

    def test_load_enabled_config_disabled(self) -> None:
        cfg = minio_helper.load_enabled_config(self.disabled)
        self.assertIsNone(cfg)

    def test_set_proxy_command_updates_pillar(self) -> None:
        self.run_cli(
            "set-proxy",
            "--domain",
            "minio.example.com",
            "--ssl-email",
            "ops@example.com",
            "--site-id",
            "minio-edge",
        )
        data = yaml.safe_load(self.pillar.read_text(encoding="utf-8"))
        proxy = data["minio"]["proxy"]
        self.assertTrue(proxy["enabled"])
        self.assertEqual(proxy["domain"], "minio.example.com")
        self.assertEqual(proxy["ssl_email"], "ops@example.com")
        self.assertEqual(proxy["site_id"], "minio-edge")


if __name__ == "__main__":
    unittest.main()
