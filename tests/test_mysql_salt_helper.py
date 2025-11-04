import json
import subprocess
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "modules" / "lib" / "mysql_salt_helper.py"


class MysqlSaltHelperTest(unittest.TestCase):
    def run_cli(self, *args: str):
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            capture_output=True,
            text=True,
            check=True,
        )
        return proc.stdout.strip()

    def test_bool_true(self):
        payload = json.dumps({"local": True})
        out = self.run_cli("bool", "--payload", payload)
        self.assertEqual(out, "1")

    def test_bool_false(self):
        payload = json.dumps({"local": False})
        out = self.run_cli("bool", "--payload", payload)
        self.assertEqual(out, "0")

    def test_print(self):
        payload = json.dumps({"local": "mysql-db"})
        out = self.run_cli("print", "--payload", payload)
        self.assertEqual(out, "mysql-db")


if __name__ == "__main__":
    unittest.main()
