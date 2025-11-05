import contextlib
import importlib.util
import io
import os
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
GOAT_PULSE_PATH = REPO_ROOT / "scripts" / "goat_pulse.py"

spec = importlib.util.spec_from_file_location("goat_pulse", GOAT_PULSE_PATH)
goat_pulse = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(goat_pulse)


class GoatPulseTests(unittest.TestCase):
    def test_write_metrics_generates_expected_lines(self) -> None:
        services = [
            {"label": "nginx", "unit": "nginx", "state": "active", "enabled": "enabled"},
            {"label": "php8.3-fpm", "unit": "php8.3-fpm", "state": "inactive", "enabled": "disabled"},
        ]
        sites = [
            {"site": "bank", "status": "200", "duration": 0.123, "varnish": True},
            {"site": "tank", "status": "503", "duration": 1.5, "varnish": False},
        ]
        metrics_file = Path(tempfile.mkdtemp()) / "goat.prom"
        goat_pulse.write_metrics(metrics_file, services, sites, (10, 5, 66.6), 3, {"enabled": False})
        content = metrics_file.read_text(encoding="utf-8")
        self.assertIn('saltgoat_service_active{service="nginx"} 1', content)
        self.assertIn('saltgoat_site_http_status{site="tank"} 503', content)
        self.assertIn("saltgoat_varnish_hit_ratio_percent 66.60", content)
        self.assertIn("saltgoat_fail2ban_banned_total 3", content)

    def test_loop_plain_mode_has_no_ansi(self) -> None:
        original_services = goat_pulse.gather_services
        original_sites = goat_pulse.gather_sites
        original_varnish = goat_pulse.varnish_stats
        original_fail2ban = goat_pulse.fail2ban_summary
        original_minio = goat_pulse.gather_minio_health

        goat_pulse.gather_services = lambda: [
            {"label": "nginx", "unit": "nginx", "state": "active", "enabled": "enabled"}
        ]
        goat_pulse.gather_sites = lambda: [
            {"site": "bank", "status": "200", "duration": 0.11, "varnish": True}
        ]
        goat_pulse.varnish_stats = lambda: (1, 0, 100.0)
        goat_pulse.fail2ban_summary = lambda: (0, {})
        goat_pulse.gather_minio_health = lambda: {"enabled": False}

        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                goat_pulse.loop(interval=1, once=True, metrics_file=None, plain=True)
        finally:
            goat_pulse.gather_services = original_services
            goat_pulse.gather_sites = original_sites
            goat_pulse.varnish_stats = original_varnish
            goat_pulse.fail2ban_summary = original_fail2ban
            goat_pulse.gather_minio_health = original_minio

        output = buf.getvalue()
        self.assertIn("Goat Pulse @", output)
        self.assertNotIn("\033[", output)


if __name__ == "__main__":
    unittest.main()
