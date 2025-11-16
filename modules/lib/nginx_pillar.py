#!/usr/bin/env python3
"""Manage nginx pillar definitions for SaltGoat."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Any

try:
    import yaml  # type: ignore
except ImportError as exc:  # pragma: no cover
    sys.stderr.write(f"[ERROR] 需要 PyYAML: {exc}\n")
    sys.exit(1)


def load_pillar(path: Path) -> Dict:
    if not path.exists():
        return {}
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        raise ValueError("pillar 文件必须是 YAML 对象")
    return data


def save_pillar(path: Path, data: Dict) -> None:
    path.write_text(
        yaml.safe_dump(data, sort_keys=False, default_flow_style=False),
        encoding="utf-8",
    )


def ensure_site_entry(sites: Dict, site: str) -> Dict:
    entry = sites.get(site)
    if not isinstance(entry, dict):
        raise ValueError(f"站点 {site} 不存在")
    return entry


def cmd_create(args: argparse.Namespace) -> int:
    pillar = load_pillar(args.pillar)
    nginx = pillar.setdefault("nginx", {})
    sites = nginx.setdefault("sites", {})
    if args.site in sites:
        raise ValueError(f"站点 {args.site} 已存在")
    domains = args.domains or []
    if not domains:
        raise ValueError("至少提供一个域名")
    root = args.root or f"/var/www/{args.site}"
    entry: Dict[str, Any] = {
        "enabled": True,
        "server_name": domains,
        "listen": [{"port": 80}],
        "root": root,
        "index": ["index.php", "index.html"],
        "php": {
            "enabled": True,
            "fastcgi_pass": "unix:/run/php/php8.3-fpm.sock",
        },
        "headers": {
            "X-Frame-Options": "SAMEORIGIN",
            "X-Content-Type-Options": "nosniff",
        },
    }
    php_cfg = entry["php"]
    if args.php_pool:
        php_cfg.pop("fastcgi_pass", None)
        php_cfg["pool"] = args.php_pool
    elif args.php_fastcgi:
        php_cfg["fastcgi_pass"] = args.php_fastcgi

    if args.magento:
        entry["magento"] = True
    if args.magento_run_code:
        run_ctx: Dict[str, Any] = {
            "type": args.magento_run_type or "store",
            "code": args.magento_run_code,
        }
        if args.magento_run_mode:
            run_ctx["mode"] = args.magento_run_mode
        entry["magento_run"] = run_ctx
    sites[args.site] = entry
    save_pillar(args.pillar, pillar)
    return 0


def cmd_delete(args: argparse.Namespace) -> int:
    pillar = load_pillar(args.pillar)
    nginx = pillar.setdefault("nginx", {})
    sites = nginx.setdefault("sites", {})
    if args.site not in sites:
        raise ValueError(f"站点 {args.site} 不存在")
    sites.pop(args.site, None)
    save_pillar(args.pillar, pillar)
    return 0


def cmd_toggle(args: argparse.Namespace) -> int:
    pillar = load_pillar(args.pillar)
    nginx = pillar.setdefault("nginx", {})
    sites = nginx.setdefault("sites", {})
    entry = ensure_site_entry(sites, args.site)
    entry["enabled"] = args.action == "enable"
    save_pillar(args.pillar, pillar)
    return 0


def cmd_ssl(args: argparse.Namespace) -> int:
    pillar = load_pillar(args.pillar)
    nginx = pillar.setdefault("nginx", {})
    sites = nginx.setdefault("sites", {})
    entry = ensure_site_entry(sites, args.site)
    candidates = entry.get("server_name", [])
    if not candidates and not args.domain:
        raise ValueError("未找到可用域名，请通过 --domain 指定")
    domain = args.domain or candidates[0]
    ssl = entry.setdefault("ssl", {})
    ssl.update(
        {
            "enabled": True,
            "cert": f"/etc/letsencrypt/live/{domain}/fullchain.pem",
            "key": f"/etc/letsencrypt/live/{domain}/privkey.pem",
            "protocols": "TLSv1.2 TLSv1.3",
            "prefer_server_ciphers": False,
        }
    )
    listen = entry.setdefault("listen", [{"port": 80}])
    normalized: List[tuple] = []
    for idx, item in enumerate(listen):
        if isinstance(item, dict):
            normalized.append((item.get("port"), item.get("ssl", False)))
            listen[idx].pop("http2", None)
            listen[idx].pop("http_2", None)
        else:
            normalized.append((item, False))
    if not any(port == 443 and ssl_flag for port, ssl_flag in normalized):
        listen.append({"port": 443, "ssl": True})
    if not any(port == 80 for port, _ in normalized):
        listen.insert(0, {"port": 80})
    ssl.setdefault("redirect", True)
    if args.email:
        nginx["ssl_email"] = args.email
    save_pillar(args.pillar, pillar)
    return 0


def cmd_csp(args: argparse.Namespace) -> int:
    levels = {
        1: "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'",
        2: "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'; script-src 'self' 'unsafe-inline' 'unsafe-eval'",
        3: "default-src 'self' http: https: data: blob: 'unsafe-inline'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'",
        4: "default-src 'self' http: https: data: blob:; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' http: https: data:; font-src 'self' http: https: data:",
        5: "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' http: https: data:; font-src 'self' http: https: data:; connect-src 'self' http: https:; frame-src 'self'",
    }
    pillar = load_pillar(args.pillar)
    nginx = pillar.setdefault("nginx", {})
    cfg = nginx.setdefault("csp", {})
    if args.level <= 0 or not args.enabled:
        cfg.update({"enabled": False, "level": 0, "policy": ""})
    else:
        if args.level not in levels:
            raise ValueError("不支持的 CSP 等级 (1-5)")
        cfg.update({"enabled": True, "level": args.level, "policy": levels[args.level]})
    save_pillar(args.pillar, pillar)
    return 0


def cmd_modsecurity(args: argparse.Namespace) -> int:
    pillar = load_pillar(args.pillar)
    nginx = pillar.setdefault("nginx", {})
    cfg = nginx.setdefault("modsecurity", {})
    if args.level <= 0 or not args.enabled:
        cfg.update({"enabled": False, "level": 0, "admin_path": args.admin_path})
    else:
        if not 1 <= args.level <= 10:
            raise ValueError("ModSecurity 等级必须在 1-10 之间")
        cfg.update({"enabled": True, "level": args.level, "admin_path": args.admin_path})
    save_pillar(args.pillar, pillar)
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    pillar = load_pillar(args.pillar)
    nginx = pillar.get("nginx", {})
    sites = nginx.get("sites", {})
    for name, cfg in sites.items():
        enabled = cfg.get("enabled", True)
        domains = ", ".join(cfg.get("server_name", []))
        root = cfg.get("root", "")
        ssl_enabled = (cfg.get("ssl") or {}).get("enabled", False)
        print(f"{name}: enabled={enabled}, ssl={ssl_enabled}, root={root}, domains=[{domains}]")
    return 0


def _get_by_path(data: Dict, key_path: str) -> Any:
    cur: Any = data
    for part in key_path.split(":"):
        if not isinstance(cur, dict):
            return None
        if part not in cur:
            return None
        cur = cur[part]
    return cur


def cmd_get(args: argparse.Namespace) -> int:
    pillar = load_pillar(args.pillar)
    value = _get_by_path(pillar, args.key)
    if value is None:
        return 1
    print(json.dumps(value, ensure_ascii=False))
    return 0


def cmd_site_info(args: argparse.Namespace) -> int:
    pillar = load_pillar(args.pillar)
    nginx = pillar.get("nginx") or {}
    sites = nginx.get("sites") or {}
    site_cfg = sites.get(args.site, {})
    if not isinstance(site_cfg, dict):
        site_cfg = {}
    root = site_cfg.get("root") or nginx.get("default_site_root") or f"/var/www/{args.site}"
    domains = site_cfg.get("server_name") or ([args.site] if args.site else [])
    email = site_cfg.get("ssl_email") or nginx.get("ssl_email") or pillar.get("ssl_email") or ""
    magento_flag = bool(site_cfg.get("magento"))
    ssl_webroot = site_cfg.get("ssl_webroot") or ""
    if args.format == "env":
        print(f"root={root}")
        print(f"domains={','.join(str(d) for d in domains if d)}")
        print(f"email={email}")
        print(f"magento={'1' if magento_flag else '0'}")
        print(f"ssl_webroot={ssl_webroot}")
    else:
        info = {
            "root": root,
            "domains": domains,
            "email": email,
            "magento": magento_flag,
            "ssl_webroot": ssl_webroot,
        }
        print(json.dumps(info, ensure_ascii=False))
    return 0


def cmd_magento_roots(args: argparse.Namespace) -> int:
    pillar = load_pillar(args.pillar)
    nginx = pillar.get("nginx") or {}
    sites = nginx.get("sites") or {}
    for name, cfg in sites.items():
        if not isinstance(cfg, dict):
            continue
        if not cfg.get("magento"):
            continue
        root = cfg.get("root") or f"/var/www/{name}"
        print(root)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manage nginx pillar configuration")
    parser.add_argument("--pillar", type=Path, required=True, help="nginx pillar 文件路径")
    sub = parser.add_subparsers(dest="command", required=True)

    create = sub.add_parser("create", help="创建站点条目")
    create.add_argument("--site", required=True)
    create.add_argument("--domains", nargs="+", required=True)
    create.add_argument("--root", help="站点根目录，可选")
    create.add_argument("--email", help="SSL 邮箱，可选")
    create.add_argument("--ssl-domain", help="SSL 域名，默认取第一个域名")
    create.add_argument("--magento", action="store_true", help="标记站点为 Magento")
    create.add_argument("--magento-run-type", help="Magento run type，例如 store 或 website")
    create.add_argument("--magento-run-code", help="Magento run code，例如 default/duobank_ws")
    create.add_argument("--magento-run-mode", default="production", help="Magento MAGE_MODE，默认 production")
    create.add_argument("--php-pool", help="关联 PHP-FPM 池名 (magento-xxx)")
    create.add_argument("--php-fastcgi", help="自定义 fastcgi_pass，覆盖默认值")
    create.set_defaults(func=cmd_create)

    delete = sub.add_parser("delete", help="删除站点")
    delete.add_argument("--site", required=True)
    delete.set_defaults(func=cmd_delete)

    enable = sub.add_parser("enable", help="启用站点")
    enable.add_argument("--site", required=True)
    enable.set_defaults(func=cmd_toggle, action="enable")

    disable = sub.add_parser("disable", help="禁用站点")
    disable.add_argument("--site", required=True)
    disable.set_defaults(func=cmd_toggle, action="disable")

    ssl = sub.add_parser("ssl", help="配置 SSL 条目")
    ssl.add_argument("--site", required=True)
    ssl.add_argument("--domain", help="SSL 域名，可选")
    ssl.add_argument("--email", help="通知邮箱，可选")
    ssl.set_defaults(func=cmd_ssl)

    csp = sub.add_parser("csp-level", help="设置 CSP 等级")
    csp.add_argument("--level", type=int, required=True)
    csp.add_argument("--enabled", type=int, choices=[0, 1], default=1)
    csp.set_defaults(func=cmd_csp)

    modsec = sub.add_parser("modsecurity-level", help="设置 ModSecurity 等级")
    modsec.add_argument("--level", type=int, required=True)
    modsec.add_argument("--enabled", type=int, choices=[0, 1], default=1)
    modsec.add_argument("--admin-path", default="/admin")
    modsec.set_defaults(func=cmd_modsecurity)

    lst = sub.add_parser("list", help="列出站点信息")
    lst.set_defaults(func=cmd_list)

    getter = sub.add_parser("get", help="按路径读取配置 (冒号分隔)")
    getter.add_argument("--key", required=True, help="例如 nginx:csp")
    getter.set_defaults(func=cmd_get)

    info = sub.add_parser("site-info", help="输出站点信息 (JSON 或 env)")
    info.add_argument("--site", required=True)
    info.add_argument("--format", choices=["json", "env"], default="json")
    info.set_defaults(func=cmd_site_info)

    roots = sub.add_parser("magento-roots", help="列出标记为 Magento 的站点根目录")
    roots.set_defaults(func=cmd_magento_roots)

    return parser


def main(argv: Iterable[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    try:
        return args.func(args)
    except ValueError as exc:
        parser.error(str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
