#!/usr/bin/env python3
"""Automate SaltGoat monitoring site configuration."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
from collections import OrderedDict
from pathlib import Path
from typing import Iterable, List, Tuple

try:
    import yaml  # type: ignore
except ImportError as exc:  # pragma: no cover
    raise SystemExit(f"[monitor_auto_sites] Missing dependency: {exc}")


def to_ordered(value):
    if isinstance(value, dict):
        return OrderedDict((k, to_ordered(v)) for k, v in value.items())
    if isinstance(value, list):
        return [to_ordered(v) for v in value]
    return value


def service_exists(name: str, skip_systemctl: bool) -> bool:
    if skip_systemctl:
        return False
    try:
        proc = subprocess.run(
            ["systemctl", "show", f"{name}.service", "--property", "LoadState"],
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        return False
    if proc.returncode != 0:
        return False
    return "not-found" not in proc.stdout


def load_existing(path: Path, skip_salt_call: bool) -> OrderedDict:
    if not path.exists():
        return OrderedDict()
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception:
        return OrderedDict()
    return to_ordered(data)


def detect_sites(site_root: Path, nginx_dir: Path) -> List[dict]:
    sites: List[dict] = []
    if not site_root.exists():
        return sites
    for entry in sorted(site_root.iterdir()):
        if not entry.is_dir():
            continue
        root = None
        if (entry / "app/etc/env.php").is_file():
            root = entry
        elif (entry / "current/app/etc/env.php").is_file():
            root = entry / "current"
        if root is None:
            continue
        sites.append({"name": entry.name, "root": str(root)})
    if not sites:
        return []

    if nginx_dir.exists():
        for conf in nginx_dir.glob("*"):
            try:
                text = conf.read_text(encoding="utf-8")
            except Exception:
                continue
            https = bool(re.search(r"listen\s+[^;]*443", text))
            server_names: List[str] = []
            for match in re.findall(r"server_name\s+([^;]+);", text):
                for token in match.split():
                    token = token.strip()
                    if token and token != "_":
                        server_names.append(token)
            for site in sites:
                root = site["root"].rstrip("/")
                parent = str(Path(root).parent).rstrip("/")
                if root not in text and parent not in text:
                    continue
                if "url" not in site and server_names:
                    domain = server_names[0].lstrip("*.")
                    scheme = "https" if https else "http"
                    site["url"] = f"{scheme}://{domain}/"
    for site in sites:
        site.setdefault("url", f"http://127.0.0.1/{site['name']}/")
    return sites


def ensure_structure(data: OrderedDict) -> Tuple[List[dict], OrderedDict]:
    saltgoat = data.setdefault("saltgoat", OrderedDict())
    monitor = saltgoat.setdefault("monitor", OrderedDict())
    sites = monitor.setdefault("sites", [])
    if not isinstance(sites, list):
        monitor["sites"] = []
        sites = monitor["sites"]
    beacons = saltgoat.setdefault("beacons", OrderedDict())
    service = beacons.setdefault("service", OrderedDict())
    services = service.setdefault("services", OrderedDict())
    if not isinstance(services, dict):
        service["services"] = OrderedDict()
        services = service["services"]
    return sites, services


def format_scalar(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if value is None:
        return "null"
    text = str(value)
    if text == "" or re.search(r"[\s:#]", text):
        return json.dumps(text, ensure_ascii=False)
    return text


def dump_yaml(obj, indent=0, lines=None):
    if lines is None:
        lines = []
    if isinstance(obj, dict):
        for key, value in obj.items():
            lines.append(" " * indent + f"{key}:")
            dump_yaml(value, indent + 2, lines)
    elif isinstance(obj, list):
        if not obj:
            lines.append(" " * indent + "[]")
        for item in obj:
            if isinstance(item, (dict, list)):
                lines.append(" " * indent + "-")
                dump_yaml(item, indent + 2, lines)
            else:
                lines.append(" " * indent + "- " + format_scalar(item))
    else:
        lines.append(" " * indent + format_scalar(obj))
    return lines


def default_services(varnish_exists: bool) -> Tuple[List[str], List[str], List[str]]:
    timeout_services = ["php8.3-fpm"]
    server_error_services = ["php8.3-fpm", "nginx"]
    failure_services = ["php8.3-fpm", "nginx"]
    if varnish_exists:
        timeout_services.append("varnish")
        server_error_services.append("varnish")
        failure_services.append("varnish")
    return timeout_services, server_error_services, failure_services


def reconcile_sites(
    data: OrderedDict,
    detected_sites: List[dict],
    varnish_exists: bool,
) -> Tuple[List[str], List[str], List[str]]:
    sites_list, beacon_services = ensure_structure(data)
    detected_map = {site["name"].lower(): site for site in detected_sites}
    new_entries: List[str] = []
    removed_entries: List[str] = []
    updates: List[str] = []
    manual_names = set()
    manual_urls = set()
    manual_entries: List[dict] = []
    updated_sites: List[dict] = []

    for entry in list(sites_list):
        if not isinstance(entry, dict):
            continue
        name_value = (entry.get("name") or "").strip()
        url_value = (entry.get("url") or "").strip()
        name_lower = name_value.lower()
        url_lower = url_value.rstrip("/").lower()
        is_auto = entry.get("auto", True)
        if is_auto:
            site_info = detected_map.pop(name_lower, None)
            if site_info:
                entry["name"] = site_info["name"]
                entry["url"] = site_info["url"]
                entry["timeout"] = 6
                entry["retries"] = 2
                entry["expect"] = 200
                entry["tls_warn_days"] = 14
                entry["tls_critical_days"] = 7
                timeout_services, server_error_services, failure_services = default_services(varnish_exists)
                entry["timeout_services"] = timeout_services
                entry["server_error_services"] = server_error_services
                entry["failure_services"] = failure_services
                entry["auto"] = True
                updated_sites.append(entry)
            else:
                sites_list.remove(entry)
                removed_entries.append(name_value or name_lower)
        else:
            if name_lower:
                manual_names.add(name_lower)
            if url_lower:
                manual_urls.add(url_lower)
            manual_entries.append(entry)

    sites_list.clear()
    sites_list.extend(updated_sites)
    sites_list.extend(manual_entries)

    for name_lower, site in detected_map.items():
        url_lower = site["url"].rstrip("/").lower()
        if name_lower in manual_names or url_lower in manual_urls:
            continue
        entry = OrderedDict()
        entry["name"] = site["name"]
        entry["url"] = site["url"]
        entry["timeout"] = 6
        entry["retries"] = 2
        entry["expect"] = 200
        entry["tls_warn_days"] = 14
        entry["tls_critical_days"] = 7
        timeout_services, server_error_services, failure_services = default_services(varnish_exists)
        entry["timeout_services"] = timeout_services
        entry["server_error_services"] = server_error_services
        entry["failure_services"] = failure_services
        entry["auto"] = True
        sites_list.append(entry)
        new_entries.append(site["name"])

    if varnish_exists:
        services_dict = beacon_services
        if not isinstance(services_dict, OrderedDict):
            services_dict = OrderedDict(services_dict)
            beacon_services.clear()
            beacon_services.update(services_dict)
        if "varnish" not in services_dict:
            services_dict["varnish"] = OrderedDict([("interval", 20)])
            updates.append("varnish-beacon")

    return new_entries, removed_entries, updates


def write_monitor_file(path: Path, data: OrderedDict) -> None:
    ordered = to_ordered(data)
    ordered.setdefault("saltgoat", OrderedDict())
    if path.exists():
        backup = path.with_suffix(path.suffix + ".bak")
        shutil.copy2(path, backup)
    lines = dump_yaml(ordered)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def run(args: argparse.Namespace) -> Tuple[List[str], List[str], List[str]]:
    site_root = Path(args.site_root)
    nginx_dir = Path(args.nginx_dir)
    monitor_file = Path(args.monitor_file)
    data = load_existing(monitor_file, args.skip_salt_call)
    detected = detect_sites(site_root, nginx_dir)
    varnish_exists = service_exists("varnish", args.skip_systemctl)
    new_entries, removed_entries, updates = reconcile_sites(data, detected, varnish_exists)
    write_monitor_file(monitor_file, data)
    return new_entries, removed_entries, updates


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Auto-generate SaltGoat monitoring site entries")
    parser.add_argument("--site-root", default=os.environ.get("SALTGOAT_SITE_ROOT", "/var/www"))
    parser.add_argument(
        "--nginx-dir",
        default=os.environ.get("SALTGOAT_NGINX_DIR", "/etc/nginx/sites-enabled"),
    )
    parser.add_argument(
        "--monitor-file",
        default=os.environ.get("SALTGOAT_MONITOR_FILE"),
    )
    parser.add_argument(
        "--script-dir",
        default=os.environ.get("SCRIPT_DIR", str(Path(__file__).resolve().parents[2])),
    )
    parser.add_argument("--skip-salt-call", action="store_true")
    parser.add_argument("--skip-systemctl", action="store_true")
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    if not args.monitor_file:
        args.monitor_file = str(Path(args.script_dir) / "salt/pillar/monitoring.sls")
    new_entries, removed_entries, updates = run(args)
    if new_entries:
        print("ADDED_SITES " + ", ".join(new_entries))
    else:
        print("ADDED_SITES NONE")
    if removed_entries:
        print("REMOVED_SITES " + ", ".join(removed_entries))
    else:
        print("REMOVED_SITES NONE")
    if updates:
        print("UPDATED " + ", ".join(updates))
    else:
        print("UPDATED NONE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
