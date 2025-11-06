import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "uptime_kuma_helper.py"


class UptimeKumaHelperCLITest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.pillar = Path(self.tmp.name) / "uptime_kuma.sls"
        self.pillar.write_text(
            textwrap.dedent(
                """
                uptime_kuma:
                  base_dir: /srv/uptime
                  data_dir: /srv/uptime/data
                  bind_host: 0.0.0.0
                  http_port: 4000
                  image: uptime:test
                  traefik:
                    domain: status.example.com
                    aliases:
                      - status-alt.example.com
                    entrypoints:
                      - web
                      - websecure
                    tls:
                      enabled: true
                      resolver: letsencrypt
                    extra_labels:
                      - traefik.http.routers.uptime.middlewares=auth
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
        self.assertEqual(data["base_dir"], "/srv/uptime")
        self.assertEqual(data["http_port"], 4000)
        self.assertEqual(data["traefik"]["domain"], "status.example.com")
        self.assertEqual(data["traefik_rule"], "Host(`status.example.com`) || Host(`status-alt.example.com`)")

    def test_base_dir_cli(self) -> None:
        proc = self.run_cli("base-dir")
        self.assertEqual(proc.stdout.strip(), "/srv/uptime")

    def test_compose_path_cli(self) -> None:
        proc = self.run_cli("compose-path")
        self.assertEqual(proc.stdout.strip(), "/srv/uptime/docker-compose.yml")


class UptimeKumaSampleTest(unittest.TestCase):
    def test_sample_exists(self) -> None:
        sample = REPO_ROOT / "salt" / "pillar" / "uptime_kuma.sls.sample"
        self.assertTrue(sample.exists())
        data = yaml.safe_load(sample.read_text(encoding="utf-8")) or {}
        cfg = data.get("uptime_kuma", {})
        self.assertEqual(cfg.get("base_dir"), "/opt/saltgoat/docker/uptime-kuma")
        self.assertIn("traefik", cfg)
        self.assertIn("entrypoints", cfg.get("traefik", {}))


if __name__ == "__main__":
    unittest.main()
