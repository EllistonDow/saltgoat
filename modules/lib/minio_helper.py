#!/usr/bin/env python3
"""Read MinIO pillar and emit helper info for SaltGoat tooling."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional

try:
    import yaml  # type: ignore
except ImportError as exc:  # pragma: no cover
    sys.stderr.write(f"[minio_helper] Missing dependency: {exc}\n")
    sys.exit(1)


@dataclass
class MinioConfig:
    enabled: bool
    binary: str
    service_name: str
    data_dir: str
    config_dir: str
    listen_host: str
    listen_port: int
    console_address: str
    tls_enabled: bool
    root_user: str
    root_password: str
    health_scheme: str
    health_host: str
    health_port: int
    health_endpoint: str
    health_timeout: int
    health_verify: bool

    @property
    def listen_address(self) -> str:
        return f"{self.listen_host}:{self.listen_port}"

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


def _save_pillar(path: Path, data: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True), encoding="utf-8")


def _parse_address(value: str, default_port: int) -> tuple[str, int]:
    host = value
    port = default_port
    if ":" in value:
        host_part, port_part = value.rsplit(":", 1)
        host = host_part or host
        try:
            port = int(port_part)
        except ValueError:
            port = default_port
    return host or "0.0.0.0", port


def build_config(data: Dict[str, Any]) -> MinioConfig:
    cfg = data.get("minio") or {}
    listen = cfg.get("listen_address", "0.0.0.0:9000")
    listen_host, listen_port = _parse_address(listen, 9000)
    health = cfg.get("health") or {}
    health_host = health.get("host") or listen_host or "127.0.0.1"
    health_port = int(health.get("port") or listen_port or 9000)
    health_scheme = health.get("scheme") or ("https" if (cfg.get("tls") or {}).get("enabled") else "http")
    health_endpoint = health.get("endpoint") or "/minio/health/live"
    health_timeout = int(health.get("timeout", 5) or 5)
    health_verify = bool(health.get("verify", True))
    tls = cfg.get("tls") or {}
    creds = cfg.get("root_credentials") or {}
    return MinioConfig(
        enabled=bool(cfg.get("enabled", True)),
        binary=cfg.get("binary", "/usr/local/bin/minio"),
        service_name=cfg.get("service_name", "minio"),
        data_dir=cfg.get("data_dir", "/var/lib/minio/data"),
        config_dir=cfg.get("config_dir", "/etc/minio"),
        listen_host=listen_host,
        listen_port=int(listen_port),
        console_address=cfg.get("console_address", "0.0.0.0:9001"),
        tls_enabled=bool(tls.get("enabled", False)),
        root_user=creds.get("access_key", "minioadmin"),
        root_password=creds.get("secret_key", "minioadmin"),
        health_scheme=health_scheme,
        health_host=health_host,
        health_port=health_port,
        health_endpoint=health_endpoint,
        health_timeout=health_timeout,
        health_verify=health_verify,
    )


def cmd_info(args: argparse.Namespace) -> int:
    cfg = load_enabled_config(args.pillar)
    if cfg is None:
        print(json.dumps({"enabled": False}))
        return 0
    print(
        json.dumps(
            {
                "enabled": cfg.enabled,
                "binary": cfg.binary,
                "service": cfg.service_name,
                "data_dir": cfg.data_dir,
                "config_dir": cfg.config_dir,
                "listen": cfg.listen_address,
                "console": cfg.console_address,
                "tls_enabled": cfg.tls_enabled,
                "root_user": cfg.root_user,
                "health_url": cfg.health_url,
                "health_timeout": cfg.health_timeout,
                "health_verify": cfg.health_verify,
            },
            ensure_ascii=False,
        )
    )
    return 0


def cmd_health_url(args: argparse.Namespace) -> int:
    cfg = load_enabled_config(args.pillar)
    if cfg is None:
        print("")
    else:
        print(cfg.health_url)
    return 0


def cmd_set_proxy(args: argparse.Namespace) -> int:
    update_proxy(
        args.pillar,
        domain=args.domain,
        console_domain=args.console_domain,
        ssl_email=args.ssl_email,
        console_enabled=not args.disable_console,
        site_id=args.site_id,
    )
    return 0


def load_enabled_config(path: Path) -> MinioConfig | None:
    data = _load_pillar(path)
    cfg = data.get("minio")
    if not isinstance(cfg, dict):
        return None
    if not cfg.get("enabled", True):
        return None
    return build_config(data)


def update_proxy(path: Path, *, domain: Optional[str], console_domain: Optional[str], ssl_email: Optional[str], console_enabled: bool, site_id: Optional[str]) -> None:
    data = _load_pillar(path)
    minio = data.setdefault("minio", {})
    proxy = minio.setdefault("proxy", {})
    if domain:
        proxy["enabled"] = True
        proxy["domain"] = domain
        proxy["console_enabled"] = console_enabled
        if console_domain:
            proxy["console_domain"] = console_domain
        elif console_enabled:
            proxy.setdefault("console_domain", domain)
        else:
            proxy["console_domain"] = ""
        if ssl_email:
            proxy["ssl_email"] = ssl_email
        proxy.setdefault("acme_webroot", "/var/lib/saltgoat/minio-proxy/acme")
        if site_id:
            proxy["site_id"] = site_id
        else:
            slug = domain.replace(".", "-")
            proxy.setdefault("site_id", f"minio-{slug}")
        minio.setdefault("proxy", proxy)
    else:
        proxy["enabled"] = False
    _save_pillar(path, data)


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

    proxy = sub.add_parser("set-proxy", help="更新 MinIO 代理域名配置")
    proxy.add_argument("--domain", required=False, help="公网域名 (例如 minio.example.com)")
    proxy.add_argument("--console-domain", help="控制台域名，可选")
    proxy.add_argument("--ssl-email", help="申请证书邮箱，可选")
    proxy.add_argument("--site-id", help="Nginx 站点 ID，可选")
    proxy.add_argument("--disable-console", action="store_true", help="禁用 MinIO Console 反代")
    proxy.set_defaults(func=cmd_set_proxy)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
