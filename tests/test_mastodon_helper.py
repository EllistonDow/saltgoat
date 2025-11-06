import json
import tempfile
import textwrap
import unittest
from pathlib import Path

from modules.lib import mastodon_helper


class MastodonHelperTests(unittest.TestCase):
    def test_load_config_merges_defaults(self) -> None:
        pillar = textwrap.dedent(
            """
            mastodon:
              instances:
                bank:
                  domain: "bank.social.example.com"
                  base_dir: "/opt/custom/bank"
                  postgres:
                    password: "SecretPass"
                  storage:
                    uploads_dir: "/srv/mastodon/bank/uploads"
            """
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            pillar_path = Path(tmpdir) / "mastodon.sls"
            pillar_path.write_text(pillar, encoding="utf-8")
            cfg = mastodon_helper.load_config(pillar_path)
        self.assertIn("instances", cfg)
        bank = cfg["instances"]["bank"]
        self.assertEqual(bank["domain"], "bank.social.example.com")
        self.assertEqual(bank["base_dir"], "/opt/custom/bank")
        self.assertEqual(bank["postgres"]["db"], "mastodon_bank")
        self.assertEqual(bank["postgres"]["password"], "SecretPass")
        self.assertEqual(bank["storage"]["uploads_dir"], "/srv/mastodon/bank/uploads")
        self.assertTrue(bank["storage"]["backups_dir"].endswith("/backups"))

    def test_cli_list(self) -> None:
        cfg = {
            "mastodon": {
                "instances": {
                    "a": {"domain": "a.example"},
                    "b": {"domain": "b.example"},
                }
            }
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            pillar_path = Path(tmpdir) / "mastodon.sls"
            pillar_path.write_text(json.dumps(cfg), encoding="utf-8")
            result = mastodon_helper.list_instances(mastodon_helper.load_config(pillar_path))
        self.assertEqual(result, ["a", "b"])


if __name__ == "__main__":
    unittest.main()
