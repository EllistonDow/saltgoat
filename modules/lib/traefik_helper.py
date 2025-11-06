#!/usr/bin/env python3
"""
Helper utilities for Traefik docker deployment.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict

import yaml

DEFAULT_CONFIG: Dict[str, Any] = {
    "base_dir": "/opt/saltgoat/docker/traefik",
    "image": "traefik:v3.1",
    "project": "traefik",
    "http_port": 18080,
    "https_port": 0,
    "dashboard_port": 19080,
    "log_level": "INFO",
    "environment": {},
    "extra_args": [],
    "dashboard": {
        "enabled": True,
        "insecure": False,
        "basic_auth": {},
    },
    "acme": {
        "enabled": False,
        "resolver": "saltgoat",
        "email": "",
        "storage": "acme.json",
        "http_challenge": {
            "enabled": True,
            "entrypoint": "web",
        },
        "tls_challenge": False,
    },
}


def deep_merge(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
    result: Dict[str, Any] = dict(base)
    for key, value in override.items():
        if (
            key in result
            and isinstance(result[key], dict)
            and isinstance(value, dict)
        ):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def load_config(pillar_path: Path) -> Dict[str, Any]:
    if not pillar_path.exists():
        return dict(DEFAULT_CONFIG)
    data = yaml.safe_load(pillar_path.read_text(encoding="utf-8")) or {}
    traefik_cfg = (
        data.get("docker", {}).get("traefik") if isinstance(data, dict) else {}
    )
    if not isinstance(traefik_cfg, dict):
        traefik_cfg = {}
    return deep_merge(DEFAULT_CONFIG, traefik_cfg)


def cmd_info(args: argparse.Namespace) -> None:
    cfg = load_config(args.pillar)
    print(json.dumps(cfg, ensure_ascii=False, indent=2))


def cmd_base_dir(args: argparse.Namespace) -> None:
    cfg = load_config(args.pillar)
    print(cfg["base_dir"])


REPO_ROOT = Path(__file__).resolve().parents[2]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Traefik pillar helper")
    parser.add_argument(
        "--pillar",
        default=REPO_ROOT / "salt/pillar/docker.sls",
        type=Path,
        help="Path to docker pillar (default: salt/pillar/docker.sls)",
    )
    sub = parser.add_subparsers(dest="command")

    info = sub.add_parser("info", help="Print merged Traefik config as JSON")
    info.set_defaults(func=cmd_info)

    base = sub.add_parser("base-dir", help="Print Traefik base directory")
    base.set_defaults(func=cmd_base_dir)

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
