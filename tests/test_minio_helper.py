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

import sys

if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

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
                  image: quay.io/minio/minio:latest
                  base_dir: /opt/minio
                  data_dir: /srv/minio/data
                  bind_host: 127.0.0.1
                  api_port: 9100
                  console_port: 9101
                  root_credentials:
                    access_key: testkey
                    secret_key: testsecret
                  health:
                    scheme: http
                    host: 127.0.0.1
                    port: 9100
                    endpoint: /minio/health/live
                    timeout: 3
                    verify: true
                  extra_env:
                    MINIO_BROWSER_REDIRECT_URL: https://minio.example.com
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
        self.assertEqual(data["base_dir"], "/opt/minio")
        self.assertEqual(data["api_port"], 9100)
        self.assertEqual(data["root_user"], "testkey")
        self.assertIn("health_url", data)
        self.assertTrue(data["health_url"].startswith("http://127.0.0.1:9100"))
        self.assertIn("MINIO_BROWSER_REDIRECT_URL", data["extra_env_keys"])

    def test_health_url(self) -> None:
        proc = self.run_cli("health-url")
        self.assertEqual(proc.stdout.strip(), "http://127.0.0.1:9100/minio/health/live")

    def test_load_enabled_config(self) -> None:
        cfg = minio_helper.load_enabled_config(self.pillar)
        self.assertIsNotNone(cfg)
        assert cfg is not None
        self.assertEqual(cfg.api_port, 9100)
        self.assertTrue(cfg.health_verify)
        self.assertEqual(cfg.root_user, "testkey")
        self.assertEqual(cfg.image, "quay.io/minio/minio:latest")

    def test_load_enabled_config_disabled(self) -> None:
        cfg = minio_helper.load_enabled_config(self.disabled)
        self.assertIsNone(cfg)


class MinioSampleTest(unittest.TestCase):
    def test_sample_structure(self) -> None:
        sample = Path("salt/pillar/minio.sls.sample")
        self.assertTrue(sample.exists())
        data = yaml.safe_load(sample.read_text(encoding="utf-8"))
        self.assertIn("minio", data)
        cfg = data["minio"]
        self.assertEqual(cfg.get("base_dir"), "/opt/saltgoat/docker/minio")
        self.assertEqual(cfg.get("api_port"), 9000)
        self.assertIn("root_credentials", cfg)


if __name__ == "__main__":
    unittest.main()
