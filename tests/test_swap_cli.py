import subprocess
import unittest
from pathlib import Path


class SwapCliTest(unittest.TestCase):
    def test_helper_status_json(self):
        helper = Path("modules/lib/swap_helper.py")
        proc = subprocess.run(
            ["python3", str(helper), "status", "--json"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0)
        self.assertIn("total_bytes", proc.stdout)

    def test_helper_ensure_dry_run(self):
        helper = Path("modules/lib/swap_helper.py")
        proc = subprocess.run(
            ["python3", str(helper), "ensure", "--min-size", "1M", "--dry-run"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0)
        self.assertIn('"changed"', proc.stdout)


if __name__ == "__main__":
    unittest.main()
