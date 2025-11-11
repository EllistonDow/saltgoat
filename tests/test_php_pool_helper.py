import argparse
import importlib
import os
import tempfile
import unittest
from pathlib import Path


class PhpPoolHelperTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp.name)
        os.environ["SALTGOAT_ALERT_LOG"] = str(self.tmp_path / "alerts.log")
        os.environ["SALTGOAT_RUNTIME_DIR"] = str(self.tmp_path / "runtime")
        os.environ["SALTGOAT_SKIP_SALT_EVENT"] = "1"
        # Reload module so constants pick up new env overrides
        import modules.lib.php_pool_helper as php_pool_helper  # noqa: WPS433

        self.helper = importlib.reload(php_pool_helper)
        self.pillar = self.tmp_path / "pillar.sls"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def _args(
        self,
        *,
        site: str = "bank",
        store_code: str | None = None,
        action: str = "add",
        set_weight: int | None = None,
    ):
        return argparse.Namespace(
            pillar=self.pillar,
            site=site,
            site_root=f"/var/www/{site}",
            pool_name=f"magento-{site}",
            store_code=store_code,
            primary_store=site,
            action=action,
            set_weight=set_weight,
            base_weight=1,
            per_store=1,
            max_weight=None,
            dry_run=False,
        )

    def test_add_store_updates_weight_and_store_codes(self):
        args = self._args(store_code="duobank")
        result = self.helper.adjust(args)
        self.assertEqual(result["weight_after"], 2)
        pillar_data = self.pillar.read_text(encoding="utf-8")
        self.assertIn("duobank", pillar_data)

    def test_remove_store_keeps_primary(self):
        self.pillar.write_text(
            "magento_optimize:\n"
            "  sites:\n"
            "    bank:\n"
            "      php_pool:\n"
            "        weight: 2\n"
            "        store_codes:\n"
            "          - bank\n"
            "          - duobank\n",
            encoding="utf-8",
        )
        args = self._args(store_code="duobank", action="remove")
        result = self.helper.adjust(args)
        self.assertEqual(result["weight_after"], 1)
        self.assertIn("bank", self.pillar.read_text(encoding="utf-8"))

    def test_force_weight_override(self):
        args = self._args(store_code="duobank", set_weight=5)
        result = self.helper.adjust(args)
        self.assertEqual(result["weight_after"], 5)
        self.assertIn("weight: 5", self.pillar.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
