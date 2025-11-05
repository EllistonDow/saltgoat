import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "nginx_pillar.py"


class NginxPillarCLITest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.pillar = Path(self.tmp.name) / "nginx.sls"

    def run_cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        cmd = [sys.executable, str(SCRIPT), "--pillar", str(self.pillar), *args]
        return subprocess.run(cmd, capture_output=True, text=True, check=True)

    def test_create_enable_ssl(self) -> None:
        result = self.run_cli(
            "create", "--site", "bank", "--domains", "bank.example.com", "--magento"
        )
        self.assertEqual(result.returncode, 0)
        pillar_text = self.pillar.read_text()
        self.assertIn("bank:", pillar_text)
        self.run_cli("ssl", "--site", "bank", "--domain", "bank.example.com")
        ssl_text = self.pillar.read_text()
        self.assertIn("bank.example.com", ssl_text)
        self.run_cli("disable", "--site", "bank")
        disabled = self.pillar.read_text()
        self.assertIn("enabled: false", disabled)

    def test_csp_and_modsecurity(self) -> None:
        # Prepare pillar with create
        self.run_cli("create", "--site", "bank", "--domains", "bank.example.com")
        self.run_cli("csp-level", "--level", "3", "--enabled", "1")
        content = self.pillar.read_text()
        self.assertIn("csp:", content)
        self.run_cli("modsecurity-level", "--level", "5", "--enabled", "1", "--admin-path", "/secure")
        content = self.pillar.read_text()
        self.assertIn("modsecurity:", content)
        self.run_cli("modsecurity-level", "--level", "0", "--enabled", "0", "--admin-path", "/secure")
        content = self.pillar.read_text()
        self.assertIn("enabled: false", content)

    def test_list_output(self) -> None:
        self.run_cli("create", "--site", "bank", "--domains", "bank.example.com")
        proc = self.run_cli("list")
        self.assertIn("bank:", proc.stdout)

    def test_site_info_env(self) -> None:
        self.run_cli("create", "--site", "bank", "--domains", "bank.example.com", "--magento")
        proc = self.run_cli("site-info", "--site", "bank", "--format", "env")
        body = proc.stdout.strip().splitlines()
        env_map = dict(line.split("=", 1) for line in body if "=" in line)
        self.assertEqual(env_map.get("magento"), "1")
        self.assertIn("root", env_map)

    def test_magento_roots(self) -> None:
        self.run_cli("create", "--site", "bank", "--domains", "bank.example.com", "--magento")
        proc = self.run_cli("magento-roots")
        self.assertIn("/var/www/bank", proc.stdout)


if __name__ == "__main__":
    unittest.main()
