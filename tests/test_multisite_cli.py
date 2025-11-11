import subprocess
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


class MultisiteCliFlagTest(unittest.TestCase):
    def test_help_lists_php_pool_flags(self) -> None:
        script = REPO_ROOT / "modules" / "magetools" / "multisite.sh"
        proc = subprocess.run(
            ["bash", str(script), "--help"],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0)
        self.assertIn("--no-adjust-php-pool", proc.stdout)
        self.assertIn("--php-pool-weight", proc.stdout)


if __name__ == "__main__":
    unittest.main()
