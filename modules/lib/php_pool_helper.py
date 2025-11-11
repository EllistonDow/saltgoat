#!/usr/bin/env python3
"""Manage PHP-FPM pool weights for Magento multisite installs."""
from __future__ import annotations

import argparse
import json
import socket
import sys
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Tuple

try:
    import yaml  # type: ignore
except ImportError as exc:  # pragma: no cover - dependency missing
    sys.stderr.write(f"[php_pool_helper] Missing PyYAML dependency: {exc}\n")
    raise SystemExit(1)

try:
    from salt.client import Caller  # type: ignore
except Exception:  # pragma: no cover - salt 不可用时降级
    Caller = None  # type: ignore

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PILLAR = REPO_ROOT / "salt" / "pillar" / "magento-optimize.sls"
RUNTIME_DIR = Path(os.environ.get("SALTGOAT_RUNTIME_DIR", "/etc/saltgoat/runtime"))
TRACK_FILE_NAME = "multisite-pools.json"
ALERT_LOG = Path(os.environ.get("SALTGOAT_ALERT_LOG", "/var/log/saltgoat/alerts.log"))
HOSTNAME = socket.getfqdn()
SKIP_SALT_EVENT = os.environ.get("SALTGOAT_SKIP_SALT_EVENT") == "1"


def _load_yaml(path: Path) -> Dict[str, object]:
    if not path.exists():
        return {}
    with path.open(encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    if not isinstance(data, dict):
        return {}
    return data


def _dump_yaml(path: Path, data: Dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)


def _normalize_code(value: str | None) -> str:
    if not value:
        return ""
    return value.strip().lower()


def _load_runtime(path: Path) -> Dict[str, object]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _save_runtime(path: Path, data: Dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def _ensure_site_entry(
    data: Dict[str, object], site: str, site_root: str | None, pool_name: str | None
) -> Tuple[Dict[str, object], Dict[str, object]]:
    magento_optimize = data.setdefault("magento_optimize", {})
    if not isinstance(magento_optimize, dict):
        magento_optimize = {}
        data["magento_optimize"] = magento_optimize
    sites = magento_optimize.setdefault("sites", {})
    if not isinstance(sites, dict):
        sites = {}
        magento_optimize["sites"] = sites
    site_entry = sites.setdefault(site, {})
    if not isinstance(site_entry, dict):
        site_entry = {}
        sites[site] = site_entry
    if site_root:
        site_entry.setdefault("site_root", site_root)
    php_pool = site_entry.setdefault("php_pool", {})
    if not isinstance(php_pool, dict):
        php_pool = {}
        site_entry["php_pool"] = php_pool
    if pool_name:
        php_pool.setdefault("pool_name", pool_name)
    php_pool.setdefault("managed_by", "saltgoat-multisite")
    return data, php_pool


def _unique(seq: List[str]) -> List[str]:
    seen: Dict[str, None] = {}
    result: List[str] = []
    for item in seq:
        key = _normalize_code(item)
        if not key or key in seen:
            continue
        seen[key] = None
        result.append(key)
    return result


def _append_alert(tag: str, payload: Dict[str, object]) -> None:
    try:
        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        ALERT_LOG.parent.mkdir(parents=True, exist_ok=True)
        with ALERT_LOG.open("a", encoding="utf-8") as fh:
            fh.write(
                f"{timestamp} [AUTOSCALE] tag={tag} payload={json.dumps(payload, ensure_ascii=False)}\n"
            )
    except Exception:  # pragma: no cover
        pass


def _emit_salt_event(tag: str, payload: Dict[str, object]) -> bool:
    if SKIP_SALT_EVENT:
        return False
    if Caller is None:
        return False
    try:
        caller = Caller()  # type: ignore[call-arg]
        caller.cmd("event.send", tag, payload)
        return True
    except Exception:
        return False


def _build_payload(args: argparse.Namespace, result: Dict[str, object]) -> Dict[str, object]:
    return {
        "host": HOSTNAME,
        "site": args.site,
        "mode": args.action,
        "pool_name": result.get("pool_name"),
        "store_codes": result.get("store_codes", []),
        "weight_before": result.get("weight_before"),
        "weight_after": result.get("weight_after"),
        "explicit_weight": bool(args.set_weight is not None),
        "pillar_path": str(args.pillar),
        "changed": result.get("pillar_changed", False),
    }


def adjust(args: argparse.Namespace) -> Dict[str, object]:
    data = _load_yaml(args.pillar)
    data, php_pool = _ensure_site_entry(data, args.site, args.site_root, args.pool_name)

    store_codes: List[str] = []
    if isinstance(php_pool.get("store_codes"), list):
        store_codes = [_normalize_code(c) for c in php_pool.get("store_codes") or []]
    previous_codes = _unique(store_codes.copy())
    primary = _normalize_code(args.primary_store)
    if primary:
        store_codes.append(primary)
    store = _normalize_code(args.store_code)
    if args.action == "add" and store:
        store_codes.append(store)
    elif args.action == "remove" and store:
        store_codes = [code for code in store_codes if code != store or code == primary]
    store_codes = _unique(store_codes)
    php_pool["store_codes"] = store_codes

    previous_weight = int(php_pool.get("weight") or 0)
    if args.set_weight is not None:
        new_weight = max(1, int(args.set_weight))
    else:
        per_store = max(1, args.per_store)
        base_weight = max(1, args.base_weight)
        store_count = max(1, len(store_codes) if store_codes else 1)
        new_weight = max(base_weight, store_count * per_store)
        if args.max_weight:
            new_weight = min(new_weight, args.max_weight)
    php_pool["weight"] = new_weight
    php_pool["last_adjusted"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    stores_changed = previous_codes != store_codes
    pillar_changed = stores_changed or previous_weight != new_weight

    if not args.dry_run:
        if pillar_changed:
            _dump_yaml(args.pillar, data)
            runtime_path = RUNTIME_DIR / TRACK_FILE_NAME
            runtime_data = _load_runtime(runtime_path)
            runtime_entry = runtime_data.setdefault(args.site, {})
            if isinstance(runtime_entry, dict):
                runtime_entry.update(
                    {
                        "store_codes": store_codes,
                        "weight": new_weight,
                        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    }
                )
            _save_runtime(runtime_path, runtime_data)

    result = {
        "pillar_changed": pillar_changed,
        "pool_name": php_pool.get("pool_name"),
        "store_codes": store_codes,
        "weight_before": previous_weight,
        "weight_after": new_weight,
        "state_required": True,
        "pillar_changed": pillar_changed,
    }

    payload = _build_payload(args, result)
    host_slug = HOSTNAME.replace(".", "-").lower()
    tag = f"saltgoat/autoscale/{host_slug}"
    if not args.dry_run and (pillar_changed or args.set_weight is not None):
        _append_alert(tag, payload)
        _emit_salt_event(tag, payload | {"severity": "NOTICE"})
    return result


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Adjust PHP-FPM pools for Magento multisite")
    sub = parser.add_subparsers(dest="command", required=True)

    adjust_cmd = sub.add_parser("adjust", help="Adjust PHP pool weight based on store list")
    adjust_cmd.add_argument("--pillar", type=Path, default=DEFAULT_PILLAR)
    adjust_cmd.add_argument("--site", required=True, help="Root site identifier (e.g. bank)")
    adjust_cmd.add_argument("--site-root", help="Path to /var/www/<site>")
    adjust_cmd.add_argument("--pool-name", help="Pool name (defaults to magento-<site>)")
    adjust_cmd.add_argument("--store-code", help="Store code being added/removed")
    adjust_cmd.add_argument("--primary-store", help="Primary store code that must stay in the list")
    adjust_cmd.add_argument(
        "--action",
        choices=["add", "remove", "recalc"],
        default="add",
        help="How to apply the provided store code",
    )
    adjust_cmd.add_argument("--set-weight", type=int, help="Force pool weight to an exact value")
    adjust_cmd.add_argument("--base-weight", type=int, default=1, help="Minimum weight")
    adjust_cmd.add_argument(
        "--per-store",
        type=int,
        default=1,
        help="Additional weight per store (weight = max(base, stores * per_store))",
    )
    adjust_cmd.add_argument("--max-weight", type=int, help="Optional maximum weight")
    adjust_cmd.add_argument("--dry-run", action="store_true", help="Skip logging/emitting events")
    adjust_cmd.set_defaults(func=adjust)
    return parser


def main(argv: List[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.pool_name:
        args.pool_name = f"magento-{args.site}"
    result = args.func(args)
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
