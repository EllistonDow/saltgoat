#!/usr/bin/env python3
"""Helper to build rabbitmq pillar payloads."""
from __future__ import annotations

import argparse
import json
import os
from typing import Iterable


def env(name: str, fallback: str = "") -> str:
    value = os.environ.get(name)
    return value if value not in (None, "") else fallback


def cmd_build(args: argparse.Namespace) -> int:
    data = {
        "site_name": env("PILLAR_SITE_NAME"),
        "site_path": env("PILLAR_SITE_PATH"),
        "mode": env("PILLAR_MODE"),
        "threads": int(env("PILLAR_THREADS", "4")),
        "amqp_host": env("PILLAR_AMQP_HOST"),
        "amqp_port": int(env("PILLAR_AMQP_PORT", "5672")),
        "amqp_user": env("PILLAR_AMQP_USER"),
        "amqp_password": env("PILLAR_AMQP_PASSWORD"),
        "amqp_vhost": env("PILLAR_AMQP_VHOST"),
        "service_user": env("PILLAR_SERVICE_USER", "www-data"),
        "php_memory_limit": env("PILLAR_PHP_MEMORY_LIMIT", "512M"),
        "cpu_quota": env("PILLAR_CPU_QUOTA"),
        "nice": env("PILLAR_NICE"),
    }
    print(json.dumps(data, ensure_ascii=False))
    return 0


def cmd_remove(args: argparse.Namespace) -> int:
    data = {
        "site_name": env("PILLAR_SITE_NAME"),
        "site_path": env("PILLAR_SITE_PATH"),
        "service_user": env("PILLAR_SERVICE_USER", "www-data"),
    }
    print(json.dumps(data, ensure_ascii=False))
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    name = env("PILLAR_SITE_NAME")
    if name == "__ALL__":
        payload = {"site_name": None, "list_all": True}
    else:
        payload = {"site_name": name, "list_all": False}
    print(json.dumps(payload, ensure_ascii=False))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="RabbitMQ pillar helper")
    sub = parser.add_subparsers(dest="command", required=True)

    build = sub.add_parser("build", help="build standard action payload")
    build.set_defaults(func=cmd_build)

    remove = sub.add_parser("remove", help="build remove payload")
    remove.set_defaults(func=cmd_remove)

    list_parser = sub.add_parser("list", help="build list payload")
    list_parser.set_defaults(func=cmd_list)

    return parser


def main(argv: Iterable[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
