import unittest

from modules.lib import pwa_health


class PwaHealthTest(unittest.TestCase):
    def test_build_payload_boolean_and_list(self) -> None:
        data = {
            "site": "bank",
            "magento_root": "/var/www/bank",
            "pwa_dir": "/var/www/bank/pwa",
            "pwa_dir_exists": "present",
            "env_file": "/var/www/bank/pwa/.env",
            "env_exists": "present",
            "home_identifier": "pwa_home",
            "template": "/tmp/template.html",
            "pillar_frontend": "enabled",
            "service_name": "pwa-frontend-bank",
            "service_exists": "yes",
            "service_active": "inactive",
            "service_enabled": "disabled",
            "graphql_status": "error",
            "graphql_message": "timeout",
            "react_status": "warn",
            "react_message": "multi versions",
            "port": "8082",
            "port_status": "warn",
            "port_message": "not listening",
            "suggestions": "fix port\ncheck react\n",
            "health_level": "warning",
        }
        payload = pwa_health.build_payload(data)
        self.assertTrue(payload["paths"]["pwa_studio_dir_exists"])
        self.assertEqual(payload["service"]["name"], "pwa-frontend-bank")
        self.assertEqual(payload["graphql"]["status"], "error")
        self.assertEqual(payload["port"]["value"], 8082)
        self.assertEqual(payload["health"]["level"], "warning")
        self.assertEqual(payload["suggestions"], ["fix port", "check react"])


if __name__ == "__main__":
    unittest.main()
