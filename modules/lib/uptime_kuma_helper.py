#!/usr/bin/env python3
"""Helper utilities for Uptime Kuma docker deployment."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PILLAR = REPO_ROOT / "salt" / "pillar" / "uptime_kuma.sls"

DEFAULT_CONFIG: Dict[str, Any] = {
    "enabled": True,
    "base_dir": "/opt/saltgoat/docker/uptime-kuma",
    "data_dir": "/opt/saltgoat/docker/uptime-kuma/data",
    "bind_host": "127.0.0.1",
    "http_port": 3001,
    "image": "louislam/uptime-kuma:1",
    "environment": {},
    "traefik": {
        "router": "uptime-kuma",
        "domain": "",
        "aliases": [],
        "entrypoints": ["web"],
        "tls": {
            "enabled": True,
            "resolver": "saltgoat",
        },
        "extra_labels": [],
    },
}


def deep_merge(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
    result = dict(base)
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def load_config(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return dict(DEFAULT_CONFIG)
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        return dict(DEFAULT_CONFIG)
    node = data.get("uptime_kuma", {})
    if not isinstance(node, dict):
        return dict(DEFAULT_CONFIG)
    return deep_merge(DEFAULT_CONFIG, node)


def build_host_rule(cfg: Dict[str, Any]) -> str:
    traefik = cfg.get("traefik") or {}
    domain = (traefik.get("domain") or "").strip()
    aliases = traefik.get("aliases") or []
    hosts = []
    if domain:
        hosts.append(domain)
    for alias in aliases:
        alias = (alias or "").strip()
        if alias:
            hosts.append(alias)
    return " || ".join(f"Host(`{host}`)" for host in hosts)


def cmd_info(args: argparse.Namespace) -> None:
    cfg = load_config(args.pillar)
    cfg["traefik_rule"] = build_host_rule(cfg)
    print(json.dumps(cfg, ensure_ascii=False, indent=2))


def cmd_base_dir(args: argparse.Namespace) -> None:
    cfg = load_config(args.pillar)
    print(cfg["base_dir"])


def cmd_compose_path(args: argparse.Namespace) -> None:
    cfg = load_config(args.pillar)
    base_dir = cfg["base_dir"]
    print(str(Path(base_dir) / "docker-compose.yml"))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Uptime Kuma pillar helper")
    parser.add_argument("--pillar", type=Path, default=DEFAULT_PILLAR, help="Path to uptime_kuma pillar")
    sub = parser.add_subparsers(dest="command")

    info = sub.add_parser("info", help="Print merged configuration as JSON")
    info.set_defaults(func=cmd_info)

    base = sub.add_parser("base-dir", help="Print base directory path")
    base.set_defaults(func=cmd_base_dir)

    compose = sub.add_parser("compose-path", help="Print docker-compose.yml path")
    compose.set_defaults(func=cmd_compose_path)

    return parser


def main(argv: list[str] | None = None) -> None:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "command", None):
        parser.print_help()
        return
    args.func(args)


if __name__ == "__main__":
    main()
