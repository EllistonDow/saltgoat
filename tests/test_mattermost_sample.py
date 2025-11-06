import unittest
from pathlib import Path

import yaml


class TestMattermostSample(unittest.TestCase):
    def setUp(self) -> None:
        sample_path = Path("salt/pillar/mattermost.sls.sample")
        self.assertTrue(sample_path.exists(), "mattermost pillar sample missing")
        self.data = yaml.safe_load(sample_path.read_text(encoding="utf-8"))

    def test_structure(self) -> None:
        self.assertIn("mattermost", self.data)
        mm = self.data["mattermost"]
        self.assertIn("site_url", mm)
        self.assertIn("admin", mm)
        self.assertIn("db", mm)
        self.assertTrue(mm["admin"]["username"])
        self.assertTrue(mm["db"]["user"])
        self.assertTrue(mm["db"]["password"])

    def test_defaults(self) -> None:
        mm = self.data["mattermost"]
        self.assertEqual(mm.get("http_port"), 8065)
        self.assertEqual(mm.get("file_store", {}).get("type"), "local")
        traefik = mm.get("traefik", {})
        self.assertIn("entrypoints", traefik)
        self.assertIn("tls", traefik)
        self.assertTrue(isinstance(traefik.get("entrypoints"), list))
        self.assertIn("router", traefik)


if __name__ == "__main__":
    unittest.main()
