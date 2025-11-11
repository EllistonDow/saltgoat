import tempfile
import unittest
from pathlib import Path

from modules.lib import swap_helper


class SwapHelperTest(unittest.TestCase):
    def test_parse_size(self):
        self.assertEqual(swap_helper.parse_size("1G"), 1024**3)
        self.assertEqual(swap_helper.parse_size("512M"), 512 * 1024**2)

    def test_ensure_swap_capacity_dry_run(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            swapfile = Path(tmpdir) / "swapfile"
            swapfile.touch()
            devices = [
                swap_helper.SwapDevice(
                    name="/dev/sda4",
                    type="partition",
                    size_bytes=512 * 1024**2,
                    used_bytes=0,
                    priority=-2,
                )
            ]
            result = swap_helper.ensure_swap_capacity(
                min_size=swap_helper.parse_size("1G"),
                swapfile=swapfile,
                dry_run=True,
                devices=devices,
            )
            self.assertTrue(result["changed"])
            self.assertIn("commands", result)

    def test_tune_sysctl_dry_run(self):
        result = swap_helper.tune_sysctl(swappiness=20, vfs_cache_pressure=50, dry_run=True)
        self.assertTrue(result["dry_run"])
        self.assertEqual(result["sysctl"]["vm.swappiness"], 20)


if __name__ == "__main__":
    unittest.main()
