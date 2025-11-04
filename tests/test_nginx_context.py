import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
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
            }
            """,
        )
        sanitize = self.run_cli("sanitize-config", "--site", "bank").stdout
        self.assertIn("include /var/www/bank/nginx.conf.sample;", sanitize)
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


if __name__ == "__main__":
    unittest.main()
