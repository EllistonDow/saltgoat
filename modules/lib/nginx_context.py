#!/usr/bin/env python3
"""Utility helpers for SaltGoat Nginx/Magento context management."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from typing import Dict, Iterable, List
import os

try:
    import yaml  # type: ignore
except ImportError as exc:  # pragma: no cover
    sys.stderr.write(f"[nginx_context] Missing dependency: {exc}\n")
    sys.exit(1)

SITES_AVAILABLE = pathlib.Path(os.environ.get("SALTGOAT_SITES_AVAILABLE", "/etc/nginx/sites-available"))


def _load_yaml(path: pathlib.Path) -> dict:
    if not path.exists():
        return {}
    with path.open(encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    if not isinstance(data, dict):
        return {}
    return data


def _server_names_from_config(data: str) -> List[str]:
    pattern = re.compile(r"server_name\s+([^;]+);", re.IGNORECASE)
    names: List[str] = []
    for match in pattern.finditer(data):
        for token in match.group(1).split():
            token = token.strip()
            if token and token not in names:
                names.append(token)
    return names


def cmd_run_context(args: argparse.Namespace) -> None:
    data = _load_yaml(args.pillar)
    sites = ((data.get("nginx") or {}).get("sites") or {})
    run_cfg = (sites.get(args.site, {}) or {}).get("magento_run") or {}
    if not isinstance(run_cfg, dict):
        run_cfg = {}
    values = {
        "type": str(run_cfg.get("type") or ""),
        "code": str(run_cfg.get("code") or ""),
        "mode": str(run_cfg.get("mode") or ""),
    }
    if args.format == "env":
        for key, value in values.items():
            print(f"{key}={value}")
    else:
        print(json.dumps(values))


def _read_site_config(site: str) -> tuple[pathlib.Path, str]:
    path = SITES_AVAILABLE / site
    if not path.exists():
        return path, ""
    return path, path.read_text(encoding="utf-8")


def cmd_server_names(args: argparse.Namespace) -> None:
    _, data = _read_site_config(args.site)
    if not data:
        return
    for name in _server_names_from_config(data):
        print(name)


_ROOT_PATTERNS = [
    re.compile(r"set\s+\$MAGE_ROOT\s+([^;]+);", re.IGNORECASE),
    re.compile(r"root\s+([^;]+);", re.IGNORECASE),
]


def _extract_root(data: str, default: str) -> str:
    for pattern in _ROOT_PATTERNS:
        match = pattern.search(data)
        if match:
            return match.group(1).strip().strip("\"'")
    return default


def cmd_site_root(args: argparse.Namespace) -> None:
    path, data = _read_site_config(args.site)
    _ = path  # unused, but kept for clarity
    if not data:
        print("")
        return
    default_root = f"/var/www/{args.site}"
    print(_extract_root(data, default_root))


def _discover_sites_from_pillar(pillar_path: pathlib.Path, root: str, current_site: str) -> List[str]:
    if not pillar_path.exists():
        return []
    data = _load_yaml(pillar_path)
    sites = ((data.get("nginx") or {}).get("sites") or {})
    results: set[str] = set()
    for name, cfg in sites.items():
        if not isinstance(cfg, dict):
            continue
        site_root = cfg.get("root")
        if not site_root and cfg.get("magento"):
            site_root = f"/var/www/{name}"
        if site_root and site_root == root:
            results.add(name)
    results.discard(current_site)
    return sorted(results)


def _discover_sites_from_configs(root: str, current_site: str) -> List[str]:
    results: set[str] = set()
    if not SITES_AVAILABLE.exists():
        return []
    pattern = re.compile(r"set\s+\$MAGE_ROOT\s+([^;]+);", re.IGNORECASE)
    for entry in SITES_AVAILABLE.iterdir():
        if not entry.is_file():
            continue
        try:
            data = entry.read_text(encoding="utf-8")
        except Exception:
            continue
        match = pattern.search(data)
        if match and match.group(1).strip().strip("\"'") == root:
            results.add(entry.name)
    results.discard(current_site)
    return sorted(results)


def cmd_related_sites(args: argparse.Namespace) -> None:
    items: List[str] = []
    if args.mode in {"pillar", "both"}:
        items.extend(_discover_sites_from_pillar(args.pillar, args.root, args.site))
    if args.mode in {"config", "both"}:
        items.extend(_discover_sites_from_configs(args.root, args.site))
    seen = set()
    for item in items:
        if item not in seen:
            seen.add(item)
            print(item)


def cmd_replace_include(args: argparse.Namespace) -> None:
    path, data = _read_site_config(args.site)
    if not data:
        sys.exit(1)
    snippet_line = f"    include {args.target};"
    if snippet_line in data:
        return
    sample_pattern = re.compile(r"^\s*include\s+" + re.escape(args.root) + r"/nginx\.conf\.sample;\s*$", re.MULTILINE)
    if sample_pattern.search(data):
        data = sample_pattern.sub(snippet_line, data, count=1)
    else:
        mage_pattern = re.compile(r"^\s*set\s+\$MAGE_ROOT.*$", re.MULTILINE)
        match = mage_pattern.search(data)
        if match:
            idx = match.end()
            data = data[:idx] + "\n" + snippet_line + data[idx:]
        else:
            data += "\n" + snippet_line + "\n"
    path.write_text(data, encoding="utf-8")


def cmd_restore_include(args: argparse.Namespace) -> None:
    path, data = _read_site_config(args.site)
    if not data:
        return
    snippet_pattern = re.compile(r"^\s*include\s+/etc/nginx/snippets/varnish-frontend-.*?\.conf;\s*$", re.MULTILINE)
    if snippet_pattern.search(data):
        data = snippet_pattern.sub(f"    include {args.root}/nginx.conf.sample;", data, count=1)
        path.write_text(data, encoding="utf-8")


def _collect_run_context_from_snippet(snippet_path: pathlib.Path) -> List[str]:
    try:
        snippet_lines = snippet_path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return []
    result: List[str] = []
    for line in snippet_lines:
        stripped = line.strip()
        if stripped.startswith("set $MAGE_RUN_TYPE") or stripped.startswith("set $MAGE_RUN_CODE") or stripped.startswith("set $MAGE_MODE"):
            result.append(stripped)
    return result


RUNTIME_POOLS_PATH = pathlib.Path("/etc/saltgoat/runtime/php-fpm-pools.json")


def _load_runtime_pools() -> list[dict]:
    try:
        data = json.loads(RUNTIME_POOLS_PATH.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, PermissionError):
        return []
    pools = data.get("pools") if isinstance(data, dict) else None
    if isinstance(pools, list):
        return [p for p in pools if isinstance(p, dict)]
    return []


def _normalize_fastcgi_socket(value: str) -> str:
    if not value:
        return ""
    value = value.strip()
    if not value:
        return ""
    if value.startswith("unix:") or value.startswith("unix:/"):
        return value
    if value.startswith("/"):
        return f"unix:{value}"
    return value


def cmd_sanitize_config(args: argparse.Namespace) -> None:
    path, data = _read_site_config(args.site)
    if not data:
        sys.exit(1)
    root = _extract_root(data, f"/var/www/{args.site}")
    snippet_pattern = re.compile(r"^(\s*)include\s+(/etc/nginx/snippets/varnish-frontend-[^;]+);\s*$", re.MULTILINE)
    has_run_context = bool(re.search(r"\$MAGE_RUN_(?:TYPE|CODE|MODE)", data))

    def replacer(match: re.Match[str]) -> str:
        indent = match.group(1)
        snippet = pathlib.Path(match.group(2))
        lines: List[str] = []
        nonlocal has_run_context
        if not has_run_context:
            snippet_lines = _collect_run_context_from_snippet(snippet)
            if snippet_lines:
                lines.extend(f"{indent}{line}" for line in snippet_lines)
            else:
                lines.extend(
                    [
                        indent + "set $MAGE_RUN_TYPE store;",
                        indent + f"set $MAGE_RUN_CODE {args.site};",
                        indent + "set $MAGE_MODE production;",
                    ]
                )
            has_run_context = True
        lines.append(f"{indent}include {root}/nginx.conf.sample;")
        return "\n".join(lines)

    new_data = snippet_pattern.sub(replacer, data)
    socket = _normalize_fastcgi_socket(getattr(args, "pool_socket", ""))
    if socket:
        fastcgi_pass_pattern = re.compile(r"(\bfastcgi_pass\s+)(fastcgi_backend)(\s*;)", re.IGNORECASE)
        upstream_pattern = re.compile(
            r"(upstream\s+fastcgi_backend\s*\{[^}]*?server\s+)([^;\s]+)(\s*;)",
            re.IGNORECASE | re.DOTALL,
        )

        def pass_replacer(match: re.Match[str]) -> str:
            return f"{match.group(1)}{socket}{match.group(3)}"

        def upstream_replacer(match: re.Match[str]) -> str:
            return f"{match.group(1)}{socket}{match.group(3)}"

        new_data = fastcgi_pass_pattern.sub(pass_replacer, new_data)
        new_data = upstream_pattern.sub(upstream_replacer, new_data)
    sys.stdout.write(new_data)


def cmd_ensure_run_context(args: argparse.Namespace) -> None:
    config_path = pathlib.Path(args.config)
    if not config_path.exists():
        return
    data = config_path.read_text(encoding="utf-8")
    if re.search(r"\$MAGE_RUN_(?:TYPE|CODE|MODE)", data):
        return
    pattern = re.compile(r"^(\s*)include\s+([^;]*nginx\.conf\.sample);\s*$", re.MULTILINE)
    map_prefix = f"mage_{args.ident}"

    def replacer(match: re.Match[str]) -> str:
        indent = match.group(1)
        include_target = match.group(2).strip()
        lines = [
            f"{indent}set $MAGE_RUN_TYPE {args.type};",
            f"{indent}set $MAGE_RUN_CODE {args.code};",
            f"{indent}set $MAGE_MODE {args.mode};",
            f"{indent}set $MAGE_RUN_TYPE ${map_prefix}_run_type;",
            f"{indent}set $MAGE_RUN_CODE ${map_prefix}_run_code;",
            f"{indent}set $MAGE_MODE ${map_prefix}_run_mode;",
            f"{indent}include {include_target};",
        ]
        return "\n".join(lines)

    new_data, count = pattern.subn(replacer, data, count=1)
    if count:
        if not new_data.endswith("\n"):
            new_data += "\n"
        config_path.write_text(new_data, encoding="utf-8")


def get_site_metadata(site: str, pillar_path: pathlib.Path) -> dict:
    path, data = _read_site_config(site)
    default_root = f"/var/www/{site}"
    root = _extract_root(data, default_root)
    server_names = _server_names_from_config(data)
    https_enabled = bool(re.search(r"listen\s+[^;]*443", data, re.IGNORECASE)) if data else False
    snippet = pathlib.Path(f"/etc/nginx/snippets/varnish-frontend-{site}.conf")
    metadata: Dict[str, object] = {
        "site": site,
        "config_path": str(path),
        "exists": bool(data),
        "root": root,
        "server_names": server_names,
        "https_enabled": https_enabled,
        "varnish_snippet": str(snippet),
        "varnish_enabled": snippet.exists(),
        "run_context": {},
        "magento": False,
        "related_sites": [],
    }
    if pillar_path.exists():
        pillar = _load_yaml(pillar_path)
        site_cfg = ((pillar.get("nginx") or {}).get("sites") or {}).get(site, {})
        if isinstance(site_cfg, dict):
            metadata["magento"] = bool(site_cfg.get("magento"))
            if site_cfg.get("root"):
                metadata["root"] = str(site_cfg.get("root"))
            run_ctx = site_cfg.get("magento_run") or {}
            if isinstance(run_ctx, dict):
                metadata["run_context"] = {
                    "type": run_ctx.get("type"),
                    "code": run_ctx.get("code"),
                    "mode": run_ctx.get("mode"),
                }
        metadata["related_sites"] = _discover_sites_from_pillar(pillar_path, metadata["root"], site)
    pools = _load_runtime_pools()
    pool_info = None
    for pool in pools:
        if pool.get("site_id") == site:
            pool_info = pool
            break
    if pool_info is None:
        for pool in pools:
            if pool.get("site_root") == metadata["root"]:
                pool_info = pool
                break
    if pool_info:
        listen = str(pool_info.get("listen") or "")
        metadata["fpm_pool"] = {
            "name": pool_info.get("pool_name"),
            "listen": listen,
            "socket": _normalize_fastcgi_socket(pool_info.get("fastcgi_pass") or listen),
        }
    else:
        metadata["fpm_pool"] = None
    return metadata


def cmd_site_metadata(args: argparse.Namespace) -> None:
    data = get_site_metadata(args.site, args.pillar)
    print(json.dumps(data, ensure_ascii=False))


def _load_env_json(var_name: str) -> dict:
    raw = os.environ.get(var_name, "")
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        sys.stderr.write(f"{var_name} 解析失败: {exc}\n")
        sys.exit(1)


def cmd_csp_status(args: argparse.Namespace) -> None:
    data = _load_env_json("JSON_DATA")
    enabled = bool(data.get("enabled"))
    level = int(data.get("level") or 0)
    policy = data.get("policy") or ""
    if enabled and level:
        print(f"CSP 已启用，等级 {level}")
        if policy:
            print(f"策略: {policy}")
    else:
        print("CSP 当前禁用")


def cmd_modsecurity_status(args: argparse.Namespace) -> None:
    data = _load_env_json("JSON_DATA")
    enabled = bool(data.get("enabled"))
    level = int(data.get("level") or 0)
    admin_path = data.get("admin_path") or "/admin"
    if enabled and level:
        print(f"ModSecurity 已启用，等级 {level}，后台路径 {admin_path}")
    else:
        print("ModSecurity 当前禁用")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="SaltGoat Nginx context helpers")
    sub = parser.add_subparsers(dest="command", required=True)

    run_ctx = sub.add_parser("run-context", help="Emit run context for a site")
    run_ctx.add_argument("--pillar", type=pathlib.Path, required=True)
    run_ctx.add_argument("--site", required=True)
    run_ctx.add_argument("--format", choices=["env", "json"], default="env")
    run_ctx.set_defaults(func=cmd_run_context)

    server = sub.add_parser("server-names", help="List server_name entries")
    server.add_argument("--site", required=True)
    server.set_defaults(func=cmd_server_names)

    site_root = sub.add_parser("site-root", help="Detect Magento root path")
    site_root.add_argument("--site", required=True)
    site_root.set_defaults(func=cmd_site_root)

    related = sub.add_parser("related-sites", help="Discover related sites sharing root")
    related.add_argument("--site", required=True)
    related.add_argument("--root", required=True)
    related.add_argument("--pillar", type=pathlib.Path, default=pathlib.Path("/etc/salt/pillar/nginx.sls"))
    related.add_argument("--mode", choices=["pillar", "config", "both"], default="both")
    related.set_defaults(func=cmd_related_sites)

    repl = sub.add_parser("replace-include", help="Swap nginx.conf.sample include with snippet")
    repl.add_argument("--site", required=True)
    repl.add_argument("--target", required=True)
    repl.add_argument("--root", required=True)
    repl.set_defaults(func=cmd_replace_include)

    restore = sub.add_parser("restore-include", help="Restore nginx.conf.sample include")
    restore.add_argument("--site", required=True)
    restore.add_argument("--root", required=True)
    restore.set_defaults(func=cmd_restore_include)

    sanitize = sub.add_parser("sanitize-config", help="Output sanitized config for rollback")
    sanitize.add_argument("--site", required=True)
    sanitize.add_argument("--pool-socket", default="", help="fastcgi socket to enforce (e.g. unix:/run/php/php8.3-fpm-magento-bank.sock)")
    sanitize.set_defaults(func=cmd_sanitize_config)

    ensure = sub.add_parser("ensure-run-context", help="Inject run context guards")
    ensure.add_argument("--config", required=True)
    ensure.add_argument("--type", required=True)
    ensure.add_argument("--code", required=True)
    ensure.add_argument("--mode", required=True)
    ensure.add_argument("--ident", required=True)
    ensure.set_defaults(func=cmd_ensure_run_context)

    csp_status = sub.add_parser("csp-status", help="打印 CSP 状态")
    csp_status.set_defaults(func=cmd_csp_status)

    modsec_status = sub.add_parser("modsecurity-status", help="打印 ModSecurity 状态")
    modsec_status.set_defaults(func=cmd_modsecurity_status)

    metadata = sub.add_parser("site-metadata", help="输出站点元数据 JSON")
    metadata.add_argument("--site", required=True)
    metadata.add_argument("--pillar", type=pathlib.Path, default=pathlib.Path("/etc/salt/pillar/nginx.sls"))
    metadata.set_defaults(func=cmd_site_metadata)

    return parser


def main(argv: Iterable[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
