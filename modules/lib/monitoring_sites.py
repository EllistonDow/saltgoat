#!/usr/bin/env python3
"""Helpers to manage SaltGoat monitoring pillar site entries."""

from __future__ import annotations

import argparse
from dataclasses import dataclass, asdict
import pathlib
import sys
from typing import Iterable, List

try:
    import yaml  # type: ignore
except ImportError as exc:  # pragma: no cover
    sys.stderr.write(f"[monitoring_sites] Missing dependency: {exc}\n")
    sys.exit(1)


@dataclass
class SiteEntry:
    name: str
    url: str
    timeout: int = 6
    retries: int = 2
    expect: int = 200
    tls_warn_days: int = 14
    tls_critical_days: int = 7
    timeout_services: List[str] | None = None
    server_error_services: List[str] | None = None
    failure_services: List[str] | None = None
    auto: bool = True

    def to_dict(self) -> dict:
        data = asdict(self)
        # Remove None lists so pillar stays clean
        for key in ("timeout_services", "server_error_services", "failure_services"):
            if not data.get(key):
                data.pop(key, None)
        return data


def _load_yaml(path: pathlib.Path) -> dict:
    if not path.exists():
        return {}
    with path.open(encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    if not isinstance(data, dict):
        return {}
    return data


def _dump_yaml(path: pathlib.Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)


def _site_list(data: dict) -> List[dict]:
    saltgoat = data.setdefault("saltgoat", {})
    monitor = saltgoat.setdefault("monitor", {})
    sites = monitor.setdefault("sites", [])
    if not isinstance(sites, list):
        monitor["sites"] = []
        return monitor["sites"]
    return sites


def cmd_upsert(args: argparse.Namespace) -> None:
    path = pathlib.Path(args.file)
    data = _load_yaml(path)
    sites = _site_list(data)
    url = args.url or f"https://{args.domain.strip().rstrip('/')}/"
    entry = SiteEntry(
        name=args.site,
        url=url,
        timeout=args.timeout,
        retries=args.retries,
        expect=args.expect,
        tls_warn_days=args.tls_warn_days,
        tls_critical_days=args.tls_critical_days,
        timeout_services=args.timeout_services,
        server_error_services=args.server_error_services,
        failure_services=args.failure_services,
        auto=not args.manual,
    ).to_dict()

    updated = False
    for idx, item in enumerate(sites):
        if isinstance(item, dict) and item.get("name") == args.site:
            sites[idx] = entry
            updated = True
            break
    if not updated:
        sites.append(entry)
    _dump_yaml(path, data)


def cmd_remove(args: argparse.Namespace) -> None:
    path = pathlib.Path(args.file)
    data = _load_yaml(path)
    sites = _site_list(data)
    new_sites = [
        item for item in sites if not (isinstance(item, dict) and item.get("name") == args.site)
    ]
    if len(new_sites) == len(sites):
        return
    saltgoat = data.setdefault("saltgoat", {})
    monitor = saltgoat.setdefault("monitor", {})
    monitor["sites"] = new_sites
    _dump_yaml(path, data)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manage SaltGoat monitoring sites pillar entries")
    sub = parser.add_subparsers(dest="command", required=True)

    upsert = sub.add_parser("upsert", help="Create or update a monitoring site entry")
    upsert.add_argument("--file", required=True, help="Path to monitoring pillar file")
    upsert.add_argument("--site", required=True, help="Site name identifier")
    upsert.add_argument("--domain", required=True, help="Primary domain (without scheme)")
    upsert.add_argument("--url", help="Override URL (defaults to https://<domain>/)")
    upsert.add_argument("--timeout", type=int, default=6)
    upsert.add_argument("--retries", type=int, default=2)
    upsert.add_argument("--expect", type=int, default=200)
    upsert.add_argument("--tls-warn-days", type=int, default=14)
    upsert.add_argument("--tls-critical-days", type=int, default=7)
    upsert.add_argument(
        "--timeout-services",
        nargs="+",
        default=["php8.3-fpm", "varnish"],
        help="Services to restart when requests time out",
    )
    upsert.add_argument(
        "--server-error-services",
        nargs="+",
        default=["php8.3-fpm", "nginx", "varnish"],
        help="Services to restart on 5xx errors",
    )
    upsert.add_argument(
        "--failure-services",
        nargs="+",
        default=["php8.3-fpm", "nginx", "varnish"],
        help="Services to restart on general failure",
    )
    upsert.add_argument("--manual", action="store_true", help="Mark entry as non-auto managed")
    upsert.set_defaults(func=cmd_upsert)

    remove = sub.add_parser("remove", help="Delete monitoring site entry")
    remove.add_argument("--file", required=True)
    remove.add_argument("--site", required=True)
    remove.set_defaults(func=cmd_remove)

    return parser


def main(argv: Iterable[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
