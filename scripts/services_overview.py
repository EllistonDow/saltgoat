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
SECRET_DIR = PILLAR_DIR / "secret"
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


def deep_merge(base: Dict[str, Any], new: Dict[str, Any]) -> Dict[str, Any]:
    for key, value in new.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            deep_merge(base[key], value)
        else:
            base[key] = value
    return base


def load_secret_data() -> Dict[str, Any]:
    data: Dict[str, Any] = {}
    if not SECRET_DIR.exists():
        return data
    for path in sorted(SECRET_DIR.glob("*.sls")):
        chunk = read_yaml(path)
        if chunk:
            deep_merge(data, chunk)
    return data


def secret_lookup(path: str) -> str:
    if not SECRET_DATA:
        return ""
    cursor: Any = SECRET_DATA
    parts = [part for part in path.replace(":", ".").split(".") if part]
    for part in parts:
        if isinstance(cursor, dict) and part in cursor:
            cursor = cursor[part]
        else:
            return ""
    if isinstance(cursor, (dict, list)):
        return ""
    return str(cursor)


SECRET_DATA = load_secret_data()
SECRET_KEY_MAP = {
    "mysql_password": ["auth.mysql.root_password", "mysql_password", "secrets.mysql_password"],
    "valkey_password": ["auth.valkey.password", "valkey_password", "secrets.valkey_password"],
    "rabbitmq_password": ["auth.rabbitmq.password", "rabbitmq_password", "secrets.rabbitmq_password"],
    "webmin_password": ["auth.webmin.password", "webmin_password", "secrets.webmin_password"],
    "phpmyadmin_password": ["auth.phpmyadmin.password", "phpmyadmin_password", "secrets.phpmyadmin_password"],
    "opensearch_admin_password": ["auth.opensearch.admin_password", "opensearch_admin_password"],
}


def build_services() -> List[ServiceEntry]:
    services: List[ServiceEntry] = []
    ip = get_ip()
    host = socket.getfqdn()

    saltgoat_secret = SECRET_DIR / "saltgoat.sls"
    saltgoat_cfg = read_yaml(saltgoat_secret) or read_yaml(PILLAR_DIR / "saltgoat.sls")

    def pillar_value(key: str, default: str = "") -> str:
        for secret_path in SECRET_KEY_MAP.get(key, [key]):
            value = secret_lookup(secret_path)
            if value:
                return value
        value = saltgoat_cfg.get(key, default) if isinstance(saltgoat_cfg, dict) else default
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
