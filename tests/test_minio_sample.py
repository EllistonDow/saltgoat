import unittest
from pathlib import Path

import yaml


class MinioSampleTest(unittest.TestCase):
    def test_sample_pillar_structure(self):
        sample = Path("salt/pillar/minio.sls.sample")
        data = yaml.safe_load(sample.read_text(encoding="utf-8"))
        self.assertIn("minio", data)
        cfg = data["minio"]
        self.assertTrue(cfg.get("enabled"))
        self.assertEqual(cfg.get("base_dir"), "/opt/saltgoat/docker/minio")
        self.assertIn("data_dir", cfg)
        self.assertIn("root_credentials", cfg)
        self.assertIn("health", cfg)
        self.assertTrue(cfg["health"].get("verify"))
        self.assertIn("api_port", cfg)
        self.assertIn("console_port", cfg)


if __name__ == "__main__":
    unittest.main()
