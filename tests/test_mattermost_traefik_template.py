import unittest
from pathlib import Path

from jinja2 import Environment, FileSystemLoader


class TestMattermostTraefikTemplate(unittest.TestCase):
    def setUp(self) -> None:
        template_dir = Path("salt/states/templates/mattermost")
        self.env = Environment(loader=FileSystemLoader(str(template_dir)))
        self.template = self.env.get_template("docker-compose.yml.jinja")

    def render(self, **kwargs) -> str:
        base_context = dict(
            mm_image="mattermost/mattermost-team-edition:latest",
            db_image="postgres:15",
            db_user="mattermost",
            db_password="pw",
            db_name="mattermost",
            base_dir="/opt/saltgoat/docker/mattermost",
            config_dir="/opt/saltgoat/docker/mattermost/config",
            data_dir="/opt/saltgoat/docker/mattermost/data",
            logs_dir="/opt/saltgoat/docker/mattermost/logs",
            plugins_dir="/opt/saltgoat/docker/mattermost/plugins",
            client_plugins_dir="/opt/saltgoat/docker/mattermost/client-plugins",
            http_port=8065,
            traefik={
                "router": "mattermost",
                "rule": "",
                "entrypoints": ["web"],
                "tls_enabled": False,
                "cert_resolver": "saltgoat",
                "service_port": 8065,
                "extra_labels": [],
            },
        )
        base_context.update(kwargs)
        return self.template.render(**base_context)

    def test_no_traefik_rule_skips_labels(self) -> None:
        output = self.render()
        self.assertIn("container_name: mattermost-app", output)
        self.assertNotIn("traefik.http.routers.mattermost", output)

    def test_traefik_labels_render(self) -> None:
        output = self.render(
            traefik={
                "router": "mattermost",
                "rule": "Host(`chat.example.com`) || Host(`chat-alt.example.com`)",
                "entrypoints": ["web", "websecure"],
                "tls_enabled": True,
                "cert_resolver": "saltgoat",
                "service_port": 8065,
                "extra_labels": ["traefik.http.routers.mattermost.middlewares=mattermost-auth"],
            }
        )
        self.assertIn('traefik.enable=true', output)
        self.assertIn('traefik.http.routers.mattermost.rule=Host(`chat.example.com`) || Host(`chat-alt.example.com`)', output)
        self.assertIn('traefik.http.routers.mattermost.entrypoints=web,websecure', output)
        self.assertIn('traefik.http.routers.mattermost.tls=true', output)
        self.assertIn('traefik.http.routers.mattermost.tls.certresolver=saltgoat', output)
        self.assertIn('traefik.http.routers.mattermost.middlewares=mattermost-auth', output)


if __name__ == "__main__":
    unittest.main()
