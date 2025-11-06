import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "traefik_helper.py"

import sys

if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from modules.lib import traefik_helper  # type: ignore  # noqa: E402


class TraefikHelperCLITest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.pillar = Path(self.tmp.name) / "docker.sls"
        self.pillar.write_text(
            textwrap.dedent(
                """
                docker:
                  traefik:
                    base_dir: /opt/traefik
                    image: traefik:v3.0
                    project: edge
                    http_port: 10080
                    https_port: 10443
                    dashboard_port: 10088
                    log_level: debug
                    dashboard:
                      enabled: true
                      insecure: false
                      basic_auth:
                        admin: "$apr1$hash"
                    acme:
                      enabled: true
                      resolver: myresolver
                      email: ops@example.com
                      storage: letsencrypt/acme.json
                      http_challenge:
                        enabled: true
                        entrypoint: web
                      tls_challenge: true
                    extra_args:
                      - "--pilot.token=xyz"
                    environment:
                      TRAEFIK_LOG: structured
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
        self.assertEqual(data["base_dir"], "/opt/traefik")
        self.assertEqual(data["project"], "edge")
        self.assertEqual(data["http_port"], 10080)
        self.assertEqual(data["acme"]["resolver"], "myresolver")
        self.assertIn("--pilot.token=xyz", data["extra_args"])

    def test_base_dir_cli(self) -> None:
        proc = self.run_cli("base-dir")
        self.assertEqual(proc.stdout.strip(), "/opt/traefik")

    def test_load_config_defaults_when_missing(self) -> None:
        cfg = traefik_helper.load_config(Path(self.tmp.name) / "missing.sls")
        self.assertEqual(cfg["base_dir"], "/opt/saltgoat/docker/traefik")
        self.assertEqual(cfg["http_port"], 18080)
        self.assertFalse(cfg["acme"]["enabled"])


class TraefikSampleTest(unittest.TestCase):
    def test_sample_structure(self) -> None:
        sample = REPO_ROOT / "salt" / "pillar" / "docker.sls.sample"
        self.assertTrue(sample.exists())
        data = yaml.safe_load(sample.read_text(encoding="utf-8")) or {}
        docker_cfg = data.get("docker", {})
        self.assertIn("traefik", docker_cfg)
        cfg = docker_cfg["traefik"]
        self.assertEqual(cfg.get("base_dir"), "/opt/saltgoat/docker/traefik")
        self.assertIn("acme", cfg)
        self.assertIn("dashboard", cfg)


if __name__ == "__main__":
    unittest.main()
