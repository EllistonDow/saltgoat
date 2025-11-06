#!/usr/bin/env python3
"""Helper utilities for Mastodon multi-instance deployment."""

from __future__ import annotations

import argparse
import json
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, List

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PILLAR = REPO_ROOT / "salt" / "pillar" / "mastodon.sls"

DEFAULT_INSTANCE: Dict[str, Any] = {
    "domain": "",
    "base_dir": "",
    "image": "ghcr.io/mastodon/mastodon:v4.3.0",
    "admin": {"email": "admin@example.com"},
    "postgres": {
        "image": "postgres:15",
        "db": "",
        "user": "mastodon",
        "password": "",
    },
    "redis": {
        "image": "redis:7",
    },
    "smtp": {
        "host": "localhost",
        "port": 25,
        "username": "",
        "password": "",
        "from_email": "",
        "tls": True,
    },
    "storage": {
        "uploads_dir": "",
        "backups_dir": "",
    },
    "traefik": {
        "router": "",
        "entrypoints": ["web", "websecure"],
        "tls": {
            "enabled": False,
            "resolver": "saltgoat",
        },
        "extra_labels": [],
    },
    "threads": {},
    "sidekiq_queues": ["default", "push", "ingress", "mailers"],
    "extra_env": {},
}


def deep_merge(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
    result: Dict[str, Any] = deepcopy(base)
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def load_config(path: Path = DEFAULT_PILLAR) -> Dict[str, Any]:
    if not path.exists():
        return {"instances": {}}
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    root = data.get("mastodon") if isinstance(data, dict) else None
    if not isinstance(root, dict):
        root = {}
    instances_raw = root.get("instances", {})
    if not isinstance(instances_raw, dict):
        instances_raw = {}
    instances: Dict[str, Any] = {}
    for name, cfg in instances_raw.items():
        if not isinstance(cfg, dict):
            continue
        merged = deep_merge(DEFAULT_INSTANCE, cfg)
        if not merged.get("base_dir"):
            merged["base_dir"] = f"/opt/saltgoat/docker/mastodon-{name}"
        postgres = merged.setdefault("postgres", {})
        if not postgres.get("db"):
            postgres["db"] = f"mastodon_{name}"
        if not postgres.get("password"):
            postgres["password"] = "ChangeMePostgres"
        redis = merged.setdefault("redis", {})
        redis.setdefault("image", "redis:7")
        storage = merged.setdefault("storage", {})
        if not storage.get("uploads_dir"):
            storage["uploads_dir"] = f"/srv/mastodon/{name}/uploads"
        if not storage.get("backups_dir"):
            storage["backups_dir"] = f"/srv/mastodon/{name}/backups"
        traefik = merged.setdefault("traefik", {})
        if not traefik.get("router"):
            traefik["router"] = f"mastodon-{name}"
        instances[name] = merged
    return {"instances": instances}


def list_instances(cfg: Dict[str, Any]) -> List[str]:
    instances = cfg.get("instances", {})
    if not isinstance(instances, dict):
        return []
    return sorted(instances.keys())


def get_instance(cfg: Dict[str, Any], name: str) -> Dict[str, Any]:
    instances = cfg.get("instances", {})
    if isinstance(instances, dict) and name in instances:
        return instances[name]
    raise KeyError(f"Mastodon instance '{name}' not defined in pillar")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Mastodon pillar helper")
    parser.add_argument(
        "--pillar",
        default=str(DEFAULT_PILLAR),
        help="Path to mastodon pillar (default: salt/pillar/mastodon.sls)",
    )
    sub = parser.add_subparsers(dest="command")

    list_cmd = sub.add_parser("list", help="List configured Mastodon instances")
    list_cmd.set_defaults(func=handle_list)

    info_cmd = sub.add_parser("info", help="Print merged configuration as JSON")
    info_cmd.add_argument("--site", help="Specific site to print")
    info_cmd.set_defaults(func=handle_info)

    base_cmd = sub.add_parser("base-dir", help="Print base directory for a site")
    base_cmd.add_argument("site")
    base_cmd.set_defaults(func=handle_base_dir)

    compose_cmd = sub.add_parser("compose-path", help="Print docker-compose.yml path")
    compose_cmd.add_argument("site")
    compose_cmd.set_defaults(func=handle_compose_path)

    env_cmd = sub.add_parser("env-path", help="Print .env.production path")
    env_cmd.add_argument("site")
    env_cmd.set_defaults(func=handle_env_path)

    return parser


def _load(path_str: str) -> Dict[str, Any]:
    return load_config(Path(path_str))


def handle_list(args: argparse.Namespace) -> None:
    cfg = _load(args.pillar)
    print(json.dumps(list_instances(cfg)))


def handle_info(args: argparse.Namespace) -> None:
    cfg = _load(args.pillar)
    if args.site:
        try:
            instance = get_instance(cfg, args.site)
        except KeyError as exc:
            raise SystemExit(str(exc))
        print(json.dumps(instance, ensure_ascii=False, indent=2))
    else:
        print(json.dumps(cfg, ensure_ascii=False, indent=2))


def handle_base_dir(args: argparse.Namespace) -> None:
    cfg = _load(args.pillar)
    try:
        instance = get_instance(cfg, args.site)
    except KeyError as exc:
        raise SystemExit(str(exc))
    print(instance["base_dir"])


def handle_compose_path(args: argparse.Namespace) -> None:
    cfg = _load(args.pillar)
    try:
        instance = get_instance(cfg, args.site)
    except KeyError as exc:
        raise SystemExit(str(exc))
    print(str(Path(instance["base_dir"]) / "docker-compose.yml"))


def handle_env_path(args: argparse.Namespace) -> None:
    cfg = _load(args.pillar)
    try:
        instance = get_instance(cfg, args.site)
    except KeyError as exc:
        raise SystemExit(str(exc))
    print(str(Path(instance["base_dir"]) / ".env.production"))


def main(argv: List[str] | None = None) -> None:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "command", None):
        parser.print_help()
        return
    args.func(args)


if __name__ == "__main__":
    main()
