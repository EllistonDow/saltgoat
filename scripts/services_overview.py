#!/usr/bin/env python3
"""Show deployed services, addresses, and credentials."""

from __future__ import annotations

import argparse
import configparser
import json
import os
import re
import socket
import subprocess
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    import yaml  # type: ignore
except ImportError as exc:  # pragma: no cover
    raise SystemExit(f"[ERROR] PyYAML missing: {exc}")

REPO_ROOT = Path(__file__).resolve().parents[1]
PILLAR_DIR = REPO_ROOT / "salt" / "pillar"
UNIT_TEST = os.environ.get("SALTGOAT_UNIT_TEST") == "1"


@dataclass
class ServiceEntry:
    name: str
    address: str
    username: str
    password: str
    notes: str = ""


def run(cmd: List[str]) -> str:
    """Run command and return stdout."""
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=True)
        return proc.stdout.strip()
    except Exception:
        return ""


def get_ip() -> str:
    if UNIT_TEST:
        return "127.0.0.1"
    output = run(["hostname", "-I"])
    if output:
        for token in output.split():
            if ":" not in token:  # prefer IPv4
                return token
        return output.split()[0]
    try:
        return socket.gethostbyname(socket.gethostname())
    except Exception:
        return "127.0.0.1"


def read_yaml(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    try:
        with path.open(encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
            if isinstance(data, dict):
                return data
    except Exception:
        return {}
    return {}


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except Exception:
        return ""


def service_state(unit: str) -> str:
    if UNIT_TEST:
        return "unknown"
    try:
        proc = subprocess.run(
            ["systemctl", "is-active", unit],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
        state = proc.stdout.strip()
        return state or "inactive"
    except Exception:
        return "unknown"


def detect_grafana_config() -> Dict[str, str]:
    cfg_path = Path("/etc/grafana/grafana.ini")
    result = {
        "port": "3000",
        "admin_user": "admin",
        "admin_password": "(change via grafana-cli admin reset-admin-password)",
    }
    if not cfg_path.exists():
        return result
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        parser.read(cfg_path, encoding="utf-8")
        result["port"] = parser.get("server", "http_port", fallback=result["port"])
        result["admin_user"] = parser.get("security", "admin_user", fallback=result["admin_user"])
        admin_password = parser.get("security", "admin_password", fallback="")
        if admin_password:
            result["admin_password"] = admin_password
    except Exception:
        pass
    return result


def detect_prometheus_port() -> str:
    service_file = Path("/etc/systemd/system/prometheus.service")
    text = read_text(service_file)
    match = re.search(r"--web\.listen-address=([^\s\\]+)", text)
    if match:
        listen = match.group(1)
        if ":" in listen:
            return listen.split(":")[-1]
        return listen
    return "9090"


def build_services() -> List[ServiceEntry]:
    services: List[ServiceEntry] = []
    ip = get_ip()
    host = socket.getfqdn()

    saltgoat_cfg = read_yaml(PILLAR_DIR / "saltgoat.sls")
    docker_root = read_yaml(PILLAR_DIR / "docker.sls").get("docker", {})
    traefik_cfg = docker_root.get("traefik", {}) if isinstance(docker_root, dict) else {}
    minio_cfg = read_yaml(PILLAR_DIR / "minio.sls").get("minio", {})
    mattermost_cfg = read_yaml(PILLAR_DIR / "mattermost.sls").get("mattermost", {})
    kuma_cfg = read_yaml(PILLAR_DIR / "uptime_kuma.sls").get("uptime_kuma", {})

    def pillar_value(key: str, default: str = "") -> str:
        value = saltgoat_cfg.get(key, default)
        return str(value) if value is not None else default

    # MySQL
    services.append(
        ServiceEntry(
            name="MySQL",
            address=f"{ip}:3306",
            username="root",
            password=pillar_value("mysql_password", "<unknown>"),
            notes="CLI: mysql -u root -p",
        )
    )

    # Valkey
    services.append(
        ServiceEntry(
            name="Valkey (Redis)",
            address=f"{ip}:6379",
            username="default",
            password=pillar_value("valkey_password", "<unknown>"),
            notes="Bind 127.0.0.1 (use valkey-cli -a <password>)",
        )
    )

    # RabbitMQ (AMQP + UI)
    rabbit_pass = pillar_value("rabbitmq_password", "<unknown>")
    services.append(
        ServiceEntry(
            name="RabbitMQ (AMQP)",
            address=f"{ip}:5672",
            username="admin",
            password=rabbit_pass,
            notes="Hostname: / (default vhost)",
        )
    )
    services.append(
        ServiceEntry(
            name="RabbitMQ Management",
            address=f"http://{host}:15672",
            username="admin",
            password=rabbit_pass,
            notes="Web UI",
        )
    )

    # Webmin
    services.append(
        ServiceEntry(
            name="Webmin",
            address=f"https://{host}:10000",
            username="root",
            password=pillar_value("webmin_password", "<unknown>"),
            notes="Web UI",
        )
    )

    # phpMyAdmin
    services.append(
        ServiceEntry(
            name="phpMyAdmin",
            address=f"https://{host}/phpmyadmin",
            username="phpmyadmin",
            password=pillar_value("phpmyadmin_password", "<unknown>"),
            notes="Browser access",
        )
    )

    # MinIO
    minio_root = (minio_cfg.get("root_credentials") or {}) if isinstance(minio_cfg, dict) else {}
    minio_user = str(minio_root.get("access_key", "minioadmin"))
    minio_pass = str(minio_root.get("secret_key", "minioadmin"))
    bind_host = str(minio_cfg.get("bind_host", "127.0.0.1") or "0.0.0.0")
    api_port = str(minio_cfg.get("api_port", "9000"))
    console_port = str(minio_cfg.get("console_port", "9001"))
    minio_address = f"http://{ip}:{api_port}"
    services.append(
        ServiceEntry(
            name="MinIO API",
            address=minio_address,
            username=minio_user,
            password=minio_pass,
            notes=f"S3-compatible (bind {bind_host}:{api_port})"
        )
    )
    services.append(
        ServiceEntry(
            name="MinIO Console",
            address=f"http://{ip}:{console_port}",
            username=minio_user,
            password=minio_pass,
            notes=f"Web UI (bind {bind_host}:{console_port})",
        )
    )

    # Traefik
    if isinstance(traefik_cfg, dict) and traefik_cfg:
        traefik_http = str(traefik_cfg.get("http_port", "18080"))
        traefik_https = traefik_cfg.get("https_port")
        traefik_https_str = str(traefik_https) if traefik_https else "-"
        dashboard_port = str(traefik_cfg.get("dashboard_port", "19080"))
        dashboard_cfg = traefik_cfg.get("dashboard", {}) if isinstance(traefik_cfg.get("dashboard"), dict) else {}
        dashboard_enabled = bool(dashboard_cfg.get("enabled", True))
        dashboard_insecure = bool(dashboard_cfg.get("insecure", False))
        dashboard_auth = dashboard_cfg.get("basic_auth", {}) if isinstance(dashboard_cfg.get("basic_auth"), dict) else {}
        dash_user = dash_pass = "-"
        if dashboard_auth:
            dash_user, dash_pass = next(iter(dashboard_auth.items()))
        notes = f"HTTP {traefik_http}"
        if traefik_https:
            notes += f" / HTTPS {traefik_https_str}"
        notes += f"; Dashboard {'enabled' if dashboard_enabled else 'disabled'}"
        if dashboard_enabled and not dashboard_insecure and not dashboard_auth:
            notes += " (api@internal only; configure auth to expose)"
        services.append(
            ServiceEntry(
                name="Traefik",
                address=f"http://{host}:{dashboard_port}",
                username=dash_user,
                password=dash_pass,
                notes=notes,
            )
        )

    # Cockpit
    services.append(
        ServiceEntry(
            name="Cockpit",
            address=f"https://{host}:9091",
            username="root",
            password=pillar_value("webmin_password", "<system root password>"),
            notes="System dashboard",
        )
    )

    # Grafana
    grafana_cfg = detect_grafana_config()
    grafana_state = service_state("grafana-server")
    services.append(
        ServiceEntry(
            name="Grafana",
            address=f"http://{host}:{grafana_cfg['port']}",
            username=grafana_cfg["admin_user"],
            password=grafana_cfg["admin_password"],
            notes=f"Dashboards & alerts (state: {grafana_state})",
        )
    )

    # Prometheus
    prom_port = detect_prometheus_port()
    prom_state = service_state("prometheus")
    services.append(
        ServiceEntry(
            name="Prometheus",
            address=f"http://{host}:{prom_port}",
            username="-",
            password="-",
            notes=f"Metrics explorer (state: {prom_state})",
        )
    )

    # Uptime Kuma
    kuma_bind = "127.0.0.1"
    kuma_port = "3001"
    kuma_state = "docker"
    if isinstance(kuma_cfg, dict) and kuma_cfg:
        kuma_bind = str(kuma_cfg.get("bind_host", kuma_bind))
        kuma_port = str(kuma_cfg.get("http_port", kuma_port))
        traefik = kuma_cfg.get("traefik", {}) if isinstance(kuma_cfg.get("traefik"), dict) else {}
        domain = (traefik.get("domain") or "").strip()
        tls_enabled = bool(traefik.get("tls", {}).get("enabled", True)) if isinstance(traefik.get("tls"), dict) else True
        scheme = "https" if tls_enabled else "http"
        address = f"{scheme}://{domain}" if domain else f"http://{host}:{kuma_port}"
        notes = f"Bind {kuma_bind}:{kuma_port}; data dir {kuma_cfg.get('data_dir', '/opt/saltgoat/docker/uptime-kuma/data')}"
    else:
        address = f"http://{host}:{kuma_port}"
        notes = "docker-compose (defaults)"
    services.append(
        ServiceEntry(
            name="Uptime Kuma",
            address=address,
            username="admin",
            password="(set via UI)",
            notes=notes,
        )
    )

    if isinstance(mattermost_cfg, dict) and mattermost_cfg:
        mm_enabled = mattermost_cfg.get("enabled", True)
        if mm_enabled:
            mm_port = str(mattermost_cfg.get("http_port", "8065"))
            mm_site = mattermost_cfg.get("site_url") or f"http://{host}:{mm_port}"
            mm_admin = mattermost_cfg.get("admin", {}) if isinstance(mattermost_cfg.get("admin"), dict) else {}
            mm_user = str(mm_admin.get("username", "sysadmin"))
            mm_pass = str(mm_admin.get("password", "<see pillar>"))
            mm_base = mattermost_cfg.get("base_dir", "/opt/saltgoat/docker/mattermost")
            services.append(
                ServiceEntry(
                    name="Mattermost",
                    address=mm_site,
                    username=mm_user,
                    password=mm_pass,
                    notes=f"Docker compose @ {mm_base}",
                )
            )

    return services


def print_table(entries: List[ServiceEntry]) -> None:
    headers = ["Service", "Address", "Username", "Password", "Notes"]
    rows = [headers]
    for entry in entries:
        rows.append([entry.name, entry.address, entry.username, entry.password, entry.notes])
    widths = [max(len(str(row[i])) for row in rows) for i in range(len(headers))]
    separators = " | ".join("-" * w for w in widths)
    print(" | ".join(str(headers[i]).ljust(widths[i]) for i in range(len(headers))))
    print(separators)
    for row in rows[1:]:
        print(" | ".join(str(row[i]).ljust(widths[i]) for i in range(len(headers))))


def main() -> int:
    parser = argparse.ArgumentParser(description="Show SaltGoat service endpoints")
    parser.add_argument("--format", choices=["table", "json"], default="table")
    args = parser.parse_args()

    services = build_services()
    if args.format == "json":
        print(json.dumps([asdict(s) for s in services], ensure_ascii=False, indent=2))
    else:
        print_table(services)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
