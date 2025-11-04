import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
import importlib.util
import uuid
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "nginx_context.py"


class NginxContextCLITest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.sites_dir = Path(self.tmp.name) / "sites-available"
        self.sites_dir.mkdir()
        self.pillar = Path(self.tmp.name) / "nginx.sls"
        self._orig_sites_available = os.environ.get("SALTGOAT_SITES_AVAILABLE")
        os.environ["SALTGOAT_SITES_AVAILABLE"] = str(self.sites_dir)
        self.addCleanup(self._restore_sites_available)

    def run_cli(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["SALTGOAT_SITES_AVAILABLE"] = str(self.sites_dir)
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            check=check,
            capture_output=True,
            text=True,
            env=env,
        )

    def write_conf(self, name: str, content: str) -> Path:
        path = self.sites_dir / name
        path.write_text(textwrap.dedent(content), encoding="utf-8")
        return path

    def _restore_sites_available(self) -> None:
        if self._orig_sites_available is None:
            os.environ.pop("SALTGOAT_SITES_AVAILABLE", None)
        else:
            os.environ["SALTGOAT_SITES_AVAILABLE"] = self._orig_sites_available

    def import_nginx_context(self):
        module_name = f"nginx_context_test_{uuid.uuid4().hex}"
        spec = importlib.util.spec_from_file_location(module_name, SCRIPT)
        module = importlib.util.module_from_spec(spec)
        sys.modules[module_name] = module
        spec.loader.exec_module(module)
        self.addCleanup(lambda: sys.modules.pop(module_name, None))
        return module

    def test_run_context_and_server_names(self) -> None:
        self.write_conf(
            "bank",
            """
            server {
                server_name bank.example.com bank-alt.example.com;
                set $MAGE_ROOT /var/www/bank;
                include /var/www/bank/nginx.conf.sample;
            }
            """,
        )
        self.pillar.write_text(
            textwrap.dedent(
                """
                nginx:
                  sites:
                    bank:
                      magento_run:
                        type: store
                        code: bank_store
                        mode: production
                """
            ),
            encoding="utf-8",
        )
        proc = self.run_cli(
            "run-context", "--pillar", str(self.pillar), "--site", "bank", "--format", "env"
        )
        env_lines = dict(line.split("=", 1) for line in proc.stdout.strip().splitlines())
        self.assertEqual(env_lines["type"], "store")
        self.assertEqual(env_lines["code"], "bank_store")
        names = self.run_cli("server-names", "--site", "bank").stdout.strip().splitlines()
        self.assertIn("bank.example.com", names)
        self.assertIn("bank-alt.example.com", names)
        root = self.run_cli("site-root", "--site", "bank").stdout.strip()
        self.assertEqual(root, "/var/www/bank")

    def test_related_sites_and_include_rewrite(self) -> None:
        self.write_conf(
            "bank",
            """
            server {
                server_name bank.example.com;
                set $MAGE_ROOT /var/www/bank;
                include /var/www/bank/nginx.conf.sample;
            }
            """,
        )
        self.write_conf(
            "tank",
            """
            server {
                server_name tank.example.com;
                set $MAGE_ROOT /var/www/bank;
                include /var/www/bank/nginx.conf.sample;
            }
            """,
        )
        self.pillar.write_text(
            textwrap.dedent(
                """
                nginx:
                  sites:
                    bank:
                      root: /var/www/bank
                    tank:
                      root: /var/www/bank
                """
            ),
            encoding="utf-8",
        )
        related = self.run_cli(
            "related-sites",
            "--site",
            "bank",
            "--root",
            "/var/www/bank",
            "--pillar",
            str(self.pillar),
            "--mode",
            "both",
        ).stdout.strip().splitlines()
        self.assertIn("tank", related)

        target_snippet = "/etc/nginx/snippets/varnish-frontend-bank.conf"
        self.run_cli(
            "replace-include",
            "--site",
            "bank",
            "--target",
            target_snippet,
            "--root",
            "/var/www/bank",
        )
        updated = (self.sites_dir / "bank").read_text(encoding="utf-8")
        self.assertIn(target_snippet, updated)
        self.run_cli("restore-include", "--site", "bank", "--root", "/var/www/bank")
        restored = (self.sites_dir / "bank").read_text(encoding="utf-8")
        self.assertIn("include /var/www/bank/nginx.conf.sample", restored)

    def test_sanitize_and_ensure_run_context(self) -> None:
        config = self.write_conf(
            "bank",
            """
            server {
                include /etc/nginx/snippets/varnish-frontend-bank.conf;
                location ~ \\.php$ {
                    fastcgi_pass fastcgi_backend;
                }
            }
            """,
        )
        socket = "unix:/run/php/php8.3-fpm-magento-bank.sock"
        sanitize = self.run_cli("sanitize-config", "--site", "bank", "--pool-socket", socket).stdout
        self.assertIn("include /var/www/bank/nginx.conf.sample;", sanitize)
        self.assertIn(f"fastcgi_pass {socket};", sanitize)
        config.write_text("    include /var/www/bank/nginx.conf.sample;\n", encoding="utf-8")
        self.run_cli(
            "ensure-run-context",
            "--config",
            str(config),
            "--type",
            "store",
            "--code",
            "bank",
            "--mode",
            "production",
            "--ident",
            "magento_bank",
        )
        ensured = config.read_text(encoding="utf-8")
        self.assertIn("set $MAGE_RUN_TYPE store;", ensured)
        self.assertIn("set $MAGE_RUN_TYPE $mage_magento_bank_run_type;", ensured)

    def test_site_metadata_outputs_expected_fields(self) -> None:
        self.write_conf(
            "bank",
            """
            server {
                listen 80;
                server_name bank.example.com *.bank.example.net;
                set $MAGE_ROOT /var/www/bank;
                include /var/www/bank/nginx.conf.sample;
            }
            """,
        )
        self.pillar.write_text(
            textwrap.dedent(
                """
                nginx:
                  sites:
                    bank:
                      root: /var/www/bank
                      magento: true
                      magento_run:
                        type: store
                        code: default
                        mode: production
                """
            ),
            encoding="utf-8",
        )
        result = self.run_cli("site-metadata", "--site", "bank", "--pillar", str(self.pillar))
        data = json.loads(result.stdout)
        self.assertEqual(data["site"], "bank")
        self.assertTrue(data["server_names"])
        self.assertIn("bank.example.com", data["server_names"])

    def test_site_metadata_includes_pool_socket_from_runtime(self) -> None:
        module = self.import_nginx_context()
        runtime_file = Path(self.tmp.name) / "php-fpm-pools.json"
        module.RUNTIME_POOLS_PATH = runtime_file
        runtime_file.write_text(
            json.dumps(
                {
                    "pools": [
                        {
                            "site_id": "bank",
                            "site_root": "/var/www/bank",
                            "pool_name": "magento-bank",
                            "listen": "/run/php/php8.3-fpm-magento-bank.sock",
                            "fastcgi_pass": "unix:/run/php/php8.3-fpm-magento-bank.sock",
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        self.addCleanup(lambda: runtime_file.unlink(missing_ok=True))
        module.SITES_AVAILABLE = self.sites_dir
        metadata = module.get_site_metadata("bank", self.pillar)
        self.assertIsNotNone(metadata["fpm_pool"])
        self.assertEqual(metadata["fpm_pool"]["name"], "magento-bank")
        self.assertEqual(metadata["fpm_pool"]["socket"], "unix:/run/php/php8.3-fpm-magento-bank.sock")


if __name__ == "__main__":
    unittest.main()
