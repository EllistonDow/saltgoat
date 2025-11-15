import base64
import json
import subprocess
import sys
import tempfile
import textwrap
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

    def test_list_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            nested = Path(tmp) / "a" / "b"
            nested.mkdir(parents=True)
            target1 = nested / "orderHistoryPage.gql.js"
            target2 = Path(tmp) / "orderHistoryPage.gql.js"
            target1.write_text("state\n", encoding="utf-8")
            target2.write_text("state\n", encoding="utf-8")
            proc = self.run_cli(
                "list-files",
                "--root",
                tmp,
                "--pattern",
                "orderHistoryPage.gql.js",
            )
            hits = set(proc.stdout.strip().splitlines())
            self.assertIn(str(target1), hits)
            self.assertIn(str(target2), hits)

    def test_load_config_emits_services_and_options(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as cfg:
            cfg.write(
                textwrap.dedent(
                    """
                    magento_pwa:
                      sites:
                        demo:
                          root: /var/www/demo
                          base_url: http://demo.test/
                          base_url_secure: https://demo.test/
                          services:
                            configure_valkey: true
                            configure_rabbitmq: false
                          options:
                            http_cache_hosts: 10.0.0.1:6081
                          pwa_studio:
                            enable: true
                    """
                ).strip()
            )
            cfg.flush()
        proc = self.run_cli("load-config", "--config", cfg.name, "--site", "demo")
        Path(cfg.name).unlink(missing_ok=True)
        exports = {}
        for line in proc.stdout.strip().splitlines():
            if not line.strip():
                continue
            key, _, raw = line.partition("=")
            exports[key] = json.loads(raw)
        self.assertEqual(exports["PWA_HTTP_CACHE_HOSTS"], "10.0.0.1:6081")
        self.assertTrue(exports["PWA_CONFIGURE_VALKEY"])
        self.assertFalse(exports["PWA_CONFIGURE_RABBITMQ"])
        self.assertTrue(exports["PWA_STUDIO_ENABLE"])


if __name__ == "__main__":
    unittest.main()
