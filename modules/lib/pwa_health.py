#!/usr/bin/env python3
"""Format PWA status payloads for SaltGoat."""

from __future__ import annotations

import argparse
import json
import os
from typing import Any, Dict, List

BOOL_TRUE = {"1", "true", "yes", "on", "enabled", "present", "active"}


def _as_bool(value: str | None) -> bool:
    if value is None:
        return False
    return value.strip().lower() in BOOL_TRUE


def _split_lines(value: str | None) -> List[str]:
    if not value:
        return []
    return [line.strip() for line in value.splitlines() if line.strip()]


def build_payload(data: Dict[str, str]) -> Dict[str, Any]:
    payload: Dict[str, Any] = {
        "site": data.get("site"),
        "paths": {
            "magento_root": data.get("magento_root"),
            "pwa_studio_dir": data.get("pwa_dir"),
            "pwa_studio_dir_exists": _as_bool(data.get("pwa_dir_exists")),
            "env_file": data.get("env_file"),
            "env_file_exists": _as_bool(data.get("env_exists")),
        },
        "cms": {
            "home_identifier": data.get("home_identifier"),
            "template": data.get("template"),
        },
        "frontend": {
            "pillar_enabled": _as_bool(data.get("pillar_frontend")),
        },
        "service": {
            "name": data.get("service_name"),
            "exists": _as_bool(data.get("service_exists")),
            "active": data.get("service_active"),
            "enabled": data.get("service_enabled"),
        },
        "graphql": {
            "status": data.get("graphql_status", "skipped"),
            "message": data.get("graphql_message", ""),
        },
        "react": {
            "status": data.get("react_status", "skipped"),
            "message": data.get("react_message", ""),
        },
        "port": {
            "value": data.get("port"),
            "status": data.get("port_status", "unknown"),
            "message": data.get("port_message", ""),
        },
        "suggestions": _split_lines(data.get("suggestions")),
        "health": {
            "level": data.get("health_level", "unknown"),
        },
    }
    port_value = data.get("port")
    if port_value:
        try:
            payload["port"]["value"] = int(port_value)
        except ValueError:
            payload["port"]["value"] = port_value
    return payload


def collect_env() -> Dict[str, str]:
    collected: Dict[str, str] = {}
    prefix = "PWA_STATUS_"
    for key, value in os.environ.items():
        if key.startswith(prefix):
            collected[key[len(prefix) :].lower()] = value
    return collected


def cmd_format(_: argparse.Namespace) -> int:
    payload = build_payload(collect_env())
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="SaltGoat PWA health formatter")
    sub = parser.add_subparsers(dest="command", required=True)
    fmt = sub.add_parser("format", help="Print JSON payload from environment variables")
    fmt.set_defaults(func=cmd_format)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
