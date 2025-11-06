#!/usr/bin/env python3
"""Read MinIO pillar and emit helper info for SaltGoat tooling."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict

try:
    import yaml  # type: ignore
except ImportError as exc:  # pragma: no cover
    sys.stderr.write(f"[minio_helper] Missing dependency: {exc}\n")
    sys.exit(1)


@dataclass
class MinioConfig:
    enabled: bool
    base_dir: str
    data_dir: str
    bind_host: str | None
    api_port: int
    console_port: int
    image: str
    root_user: str
    root_password: str
    health_scheme: str
    health_host: str
    health_port: int
    health_endpoint: str
    health_timeout: int
    health_verify: bool
    extra_env: Dict[str, Any]

    @property
    def health_url(self) -> str:
        endpoint = self.health_endpoint if self.health_endpoint.startswith("/") else f"/{self.health_endpoint}"
        return f"{self.health_scheme}://{self.health_host}:{self.health_port}{endpoint}"


def _load_pillar(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        raise ValueError("pillar must be a mapping")
    return data


def load_enabled_config(path: Path) -> MinioConfig | None:
    data = _load_pillar(path)
    cfg = data.get("minio") or {}
    if not isinstance(cfg, dict) or not cfg.get("enabled", True):
        return None

    health = cfg.get("health") or {}
    extra_env = cfg.get("extra_env") or {}
    return MinioConfig(
        enabled=True,
        base_dir=cfg.get("base_dir", "/opt/saltgoat/docker/minio"),
        data_dir=cfg.get("data_dir", "/var/lib/minio/data"),
        bind_host=cfg.get("bind_host", "127.0.0.1") or None,
        api_port=int(cfg.get("api_port", 9000) or 9000),
        console_port=int(cfg.get("console_port", 9001) or 9001),
        image=cfg.get("image", "quay.io/minio/minio:latest"),
        root_user=(cfg.get("root_credentials") or {}).get("access_key", "minioadmin"),
        root_password=(cfg.get("root_credentials") or {}).get("secret_key", "minioadmin"),
        health_scheme=health.get("scheme", "http"),
        health_host=health.get("host", "127.0.0.1"),
        health_port=int(health.get("port", cfg.get("api_port", 9000)) or 9000),
        health_endpoint=health.get("endpoint", "/minio/health/live"),
        health_timeout=int(health.get("timeout", 5) or 5),
        health_verify=bool(health.get("verify", True)),
        extra_env=extra_env if isinstance(extra_env, dict) else {},
    )


def cmd_info(args: argparse.Namespace) -> int:
    cfg = load_enabled_config(args.pillar)
    if cfg is None:
        print(json.dumps({"enabled": False}))
        return 0

    print(
        json.dumps(
            {
                "enabled": True,
                "base_dir": cfg.base_dir,
                "data_dir": cfg.data_dir,
                "bind_host": cfg.bind_host,
                "api_port": cfg.api_port,
                "console_port": cfg.console_port,
                "image": cfg.image,
                "root_user": cfg.root_user,
                "health_url": cfg.health_url,
                "health_timeout": cfg.health_timeout,
                "health_verify": cfg.health_verify,
                "extra_env_keys": sorted(cfg.extra_env.keys()),
            },
            ensure_ascii=False,
        )
    )
    return 0


def cmd_health_url(args: argparse.Namespace) -> int:
    cfg = load_enabled_config(args.pillar)
    print(cfg.health_url if cfg else "")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="MinIO pillar helper")
    parser.add_argument(
        "--pillar",
        type=Path,
        default=Path("salt/pillar/minio.sls"),
        help="MinIO pillar 文件路径",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    info = sub.add_parser("info", help="输出 MinIO JSON 配置摘要")
    info.set_defaults(func=cmd_info)

    health = sub.add_parser("health-url", help="输出健康检查 URL")
    health.set_defaults(func=cmd_health_url)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
