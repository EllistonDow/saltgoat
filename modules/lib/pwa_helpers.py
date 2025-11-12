#!/usr/bin/env python3
"""Helpers for Magento PWA install workflow."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shutil
import socket
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Dict, Iterable, List

try:
    import yaml  # type: ignore
except Exception:  # pragma: no cover
    yaml = None  # type: ignore


def cmd_decode(args: argparse.Namespace) -> int:
    data = args.data or ""
    if not data:
        print("{}")
        return 0
    try:
        decoded = base64.b64decode(data).decode("utf-8")
    except Exception:
        print("{}")
        return 0
    try:
        json.loads(decoded)
    except Exception:
        print("{}")
        return 0
    print(decoded)
    return 0


def _load_package(path: Path) -> dict:
    if not path.exists():
        raise FileNotFoundError(f"{path} 不存在")
    try:
        data = json.loads(path.read_text(encoding="utf-8")) or {}
    except json.JSONDecodeError as exc:  # pragma: no cover - 配置损坏
        raise ValueError(f"{path} 不是有效的 JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError(f"{path} JSON 结构必须是对象")
    return data


def _write_package(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def _ensure_dependency_entry(pkg_path: Path, section: str, name: str, value: str) -> bool:
    data = _load_package(pkg_path)
    container = data.get(section)
    if not isinstance(container, dict):
        container = {}
        data[section] = container
    if container.get(name) == value:
        return False
    container[name] = value
    _write_package(pkg_path, data)
    return True


def _remove_dependency_entry(pkg_path: Path, sections: List[str], name: str) -> bool:
    data = _load_package(pkg_path)
    changed = False
    for section in sections:
        container = data.get(section)
        if isinstance(container, dict) and name in container:
            container.pop(name, None)
            changed = True
            if not container:
                data.pop(section, None)
    if changed:
        _write_package(pkg_path, data)
    return changed


def _should_remove_extension(path: Path) -> bool:
    name = path.name.lower()
    if "sample" in name or "example" in name:
        return True
    pkg = path / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text(encoding="utf-8"))
            pkg_name = str(data.get("name", "")).lower()
            if "sample" in pkg_name or "example" in pkg_name:
                return True
        except Exception:
            return False
    return False


def _get_unit_workdir(service: str) -> Path | None:
    try:
        output = subprocess.check_output(
            ["systemctl", "show", service, "--property=WorkingDirectory", "--value"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return None
    if not output or output == "-":
        return None
    candidate = Path(output)
    if candidate.exists():
        return candidate
    return None


GRAPHQL_BLOCK_FIELDS = (
    "is_confirmed",
    "ProductAttributeMetadata",
    "used_in_components",
    "selected_attribute_options",
    "entered_attribute_value",
    "custom_attributes",
)


def _strip_graphql_fields(text: str, fields: Iterable[str]) -> str:
    lines = text.splitlines()
    result: List[str] = []
    skipping = False
    depth = 0
    pending_field = None

    for line in lines:
        stripped = line.strip()
        if skipping:
            depth += line.count("{") - line.count("}")
            if depth <= 0:
                skipping = False
                pending_field = None
            continue
        for field in fields:
            if field in stripped:
                if "{" in line and not stripped.endswith("}"):
                    skipping = True
                    depth = line.count("{") - line.count("}")
                    pending_field = field
                else:
                    pending_field = field
                break
        if pending_field:
            if not skipping:
                pending_field = None
            continue
        result.append(line)

    return "\n".join(result)


def _safe_replace(text: str, old: str, new: str) -> tuple[str, bool]:
    if old not in text:
        return text, False
    return text.replace(old, new), True


def cmd_apply_env(args: argparse.Namespace) -> int:
    overrides = json.loads(args.overrides)
    env_path = Path(args.file)
    env_path.parent.mkdir(parents=True, exist_ok=True)
    if not env_path.exists():
        env_path.write_text("", encoding="utf-8")

    lines = env_path.read_text(encoding="utf-8").splitlines()
    existing = {}
    for idx, raw in enumerate(lines):
        if "=" in raw and not raw.strip().startswith("#"):
            key, _, _ = raw.partition("=")
            existing[key.strip()] = idx

    for key, value in overrides.items():
        new_line = f"{key}={value}"
        if key in existing:
            lines[existing[key]] = new_line
        else:
            lines.append(new_line)

    if lines:
        env_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    else:
        env_path.write_text("", encoding="utf-8")
    return 0


def cmd_ensure_workspace(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    pkg_path = root / "package.json"
    data = _load_package(pkg_path)
    workspace_entry = args.workspace
    changed = False

    workspaces = data.get("workspaces")
    if isinstance(workspaces, list):
        if workspace_entry not in workspaces:
            workspaces.append(workspace_entry)
            changed = True
    elif isinstance(workspaces, dict):
        packages = workspaces.setdefault("packages", [])
        if isinstance(packages, list) and workspace_entry not in packages:
            packages.append(workspace_entry)
            changed = True
    else:
        data["workspaces"] = [workspace_entry]
        changed = True

    dependency = args.dependency
    if dependency:
        value = args.value or f"link:{workspace_entry}"
        deps = data.setdefault("dependencies", {})
        if deps.get(dependency) != value:
            deps[dependency] = value
            changed = True

    if changed:
        _write_package(pkg_path, data)
        print("updated")
    else:
        print("unchanged")
    return 0


def cmd_ensure_workspace_dependency(args: argparse.Namespace) -> int:
    pkg_path = Path(args.file).resolve()
    package = args.package
    value = args.value
    if _ensure_dependency_entry(pkg_path, "dependencies", package, value):
        print("updated")
    else:
        print("unchanged")
    return 0


def cmd_set_field(args: argparse.Namespace) -> int:
    pkg_path = Path(args.file).resolve()
    data = _load_package(pkg_path)
    section = args.section
    name = args.name
    value = args.value
    container = data.setdefault(section, {})
    if not isinstance(container, dict):
        raise ValueError(f"{section} 不是对象，无法写入 {name}")
    if container.get(name) == value:
        print("unchanged")
        return 0
    container[name] = value
    _write_package(pkg_path, data)
    print("updated")
    return 0


def cmd_ensure_package_field(args: argparse.Namespace) -> int:
    pkg_path = Path(args.file).resolve()
    data = _load_package(pkg_path)
    current = data.get(args.field)
    if current == args.value:
        print("unchanged")
        return 0
    data[args.field] = args.value
    _write_package(pkg_path, data)
    print("updated")
    return 0


def cmd_remove_field(args: argparse.Namespace) -> int:
    pkg_path = Path(args.file).resolve()
    data = _load_package(pkg_path)
    section = data.get(args.section)
    if not isinstance(section, dict) or args.name not in section:
        print("absent")
        return 0
    section.pop(args.name, None)
    if not section:
        data.pop(args.section, None)
    _write_package(pkg_path, data)
    print("removed")
    return 0


def cmd_remove_package_field(args: argparse.Namespace) -> int:
    pkg_path = Path(args.file).resolve()
    data = _load_package(pkg_path)
    if args.field not in data:
        print("absent")
        return 0
    data.pop(args.field, None)
    _write_package(pkg_path, data)
    print("removed")
    return 0


def cmd_ensure_package_dependency(args: argparse.Namespace) -> int:
    pkg_path = Path(args.file).resolve()
    if _ensure_dependency_entry(pkg_path, "dependencies", args.package, args.version):
        print("updated")
    else:
        print("unchanged")
    return 0


def cmd_ensure_package_dev_dependency(args: argparse.Namespace) -> int:
    pkg_path = Path(args.file).resolve()
    if _ensure_dependency_entry(pkg_path, "devDependencies", args.package, args.version):
        print("updated")
    else:
        print("unchanged")
    return 0


def cmd_remove_package_dependency(args: argparse.Namespace) -> int:
    pkg_path = Path(args.file).resolve()
    if _remove_dependency_entry(pkg_path, ["dependencies", "devDependencies"], args.package):
        print("removed")
    else:
        print("absent")
    return 0


def _read_text(path: Path) -> str:
    if not path.exists():
        raise FileNotFoundError(f"{path} 不存在")
    return path.read_text(encoding="utf-8")


def cmd_prune_extensions(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    extensions_dir = root / "packages" / "extensions"
    if not extensions_dir.exists():
        print("absent")
        return 0
    removed: List[str] = []
    for child in extensions_dir.iterdir():
        if not child.is_dir():
            continue
        if _should_remove_extension(child):
            shutil.rmtree(child, ignore_errors=True)
            removed.append(child.name)
    if removed:
        print("removed:" + ",".join(sorted(removed)))
    else:
        print("unchanged")
    return 0


def cmd_ensure_peer_deps(args: argparse.Namespace) -> int:
    pkg_path = Path(args.file).resolve()
    data = _load_package(pkg_path)
    peers = data.get("peerDependencies")
    if not isinstance(peers, dict):
        peers = {}
        data["peerDependencies"] = peers

    deps = {}
    for section in ("dependencies", "devDependencies"):
        raw = data.get(section)
        if isinstance(raw, dict):
            deps.update(raw)

    keys = ["react", "react-dom"]
    changed = False
    for key in keys:
        value = deps.get(key)
        if not value:
            continue
        if peers.get(key) == value:
            continue
        peers[key] = value
        changed = True

    if changed:
        _write_package(pkg_path, data)
        print("updated")
    else:
        print("unchanged")
    return 0


def cmd_list_graphql_files(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    if not root.exists():
        print("absent")
        return 0
    patterns = ("*.gql.js", "*.gql.ts", "*.gql.tsx", "*.graphql")
    for pattern in patterns:
        for path in root.rglob(pattern):
            print(path)
    return 0


def cmd_sanitize_graphql(args: argparse.Namespace) -> int:
    path = Path(args.file).resolve()
    try:
        text = _read_text(path)
    except FileNotFoundError:
        print("absent")
        return 0
    sanitized = _strip_graphql_fields(text, GRAPHQL_BLOCK_FIELDS)
    if sanitized == text:
        print("unchanged")
        return 0
    if not sanitized.endswith("\n"):
        sanitized += "\n"
    path.write_text(sanitized, encoding="utf-8")
    print("patched")
    return 0


def cmd_sanitize_orders(args: argparse.Namespace) -> int:
    path = Path(args.file).resolve()
    try:
        text = _read_text(path)
    except FileNotFoundError:
        print("absent")
        return 0
    replacements = [
        ("state: order.state", "status: order.status ?? order.state"),
        ("order.state", "order.status"),
    ]
    changed = False
    updated = text
    for old, new in replacements:
        updated, replaced = _safe_replace(updated, old, new)
        changed = changed or replaced
    if not changed:
        print("unchanged")
        return 0
    path.write_text(updated, encoding="utf-8")
    print("patched")
    return 0


def cmd_sanitize_payment(args: argparse.Namespace) -> int:
    path = Path(args.file).resolve()
    try:
        text = _read_text(path)
    except FileNotFoundError:
        print("absent")
        return 0
    changed = False
    updated, replaced = _safe_replace(
        text,
        "const { selected_payment_method } = checkoutDetails;",
        "const { selected_payment_method = {} } = checkoutDetails || {};",
    )
    changed = changed or replaced
    updated, replaced = _safe_replace(
        updated,
        "const paymentMethod = selected_payment_method;",
        "const paymentMethod = selected_payment_method || {};",
    )
    changed = changed or replaced
    if not changed:
        print("unchanged")
        return 0
    path.write_text(updated, encoding="utf-8")
    print("patched")
    return 0


def cmd_sanitize_cart_trigger(args: argparse.Namespace) -> int:
    path = Path(args.file).resolve()
    try:
        text = _read_text(path)
    except FileNotFoundError:
        print("absent")
        return 0
    lines = text.splitlines()
    filtered = [line for line in lines if "total_summary_quantity_including_config" not in line]
    changed = len(filtered) != len(lines)
    updated = "\n".join(filtered)
    replacement_map = {
        "const totalItems = cartDetails.totalItems;": "const totalItems = cartDetails?.totalItems ?? 0;",
        "const totalQuantity = cartDetails.totalQuantity;": "const totalQuantity = cartDetails?.totalQuantity ?? 0;",
    }
    for old, new in replacement_map.items():
        updated, replaced = _safe_replace(updated, old, new)
        changed = changed or replaced
    if "const itemCount" not in updated:
        marker = "    const handleTriggerClick = useCallback(() => {"
        injection = "    const itemCount = data?.cart?.total_quantity ?? 0;\n\n"
        if marker in updated:
            updated = updated.replace(marker, f"{injection}{marker}", 1)
            changed = True
    if not changed:
        print("unchanged")
        return 0
    path.write_text(updated, encoding="utf-8")
    print("patched")
    return 0


def cmd_patch_product_custom_attributes(args: argparse.Namespace) -> int:
    path = Path(args.file).resolve()
    try:
        text = _read_text(path)
    except FileNotFoundError:
        print("absent")
        return 0

    variant_old = (
        "        return item && item.product\n"
        "            ? [...item.product.custom_attributes].sort(attributeLabelCompare)\n"
        "            : [];"
    )
    variant_new = (
        "        const variantAttributes = item?.product?.custom_attributes || [];\n"
        "        return variantAttributes.length\n"
        "            ? [...variantAttributes].sort(attributeLabelCompare)\n"
        "            : [];"
    )
    base_old = (
        "    return custom_attributes\n"
        "        ? [...custom_attributes].sort(attributeLabelCompare)\n"
        "        : [];"
    )
    base_new = (
        "    const baseAttributes = custom_attributes || [];\n"
        "    return baseAttributes.length\n"
        "        ? [...baseAttributes].sort(attributeLabelCompare)\n"
        "        : [];"
    )

    updated = text
    changed = False
    if variant_old in updated:
        updated = updated.replace(variant_old, variant_new)
        changed = True
    if base_old in updated:
        updated = updated.replace(base_old, base_new)
        changed = True

    if not changed:
        print("unchanged")
        return 0

    path.write_text(updated, encoding="utf-8")
    print("patched")
    return 0


def cmd_graphql_ping(args: argparse.Namespace) -> int:
    endpoint = args.endpoint
    query = args.query or "query Ping { storeConfig { id } }"
    payload = json.dumps({"query": query}).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    start = time.time()
    try:
        with urllib.request.urlopen(request, timeout=args.timeout) as resp:
            body = resp.read().decode("utf-8", errors="ignore")
    except urllib.error.URLError as exc:
        print(f"GraphQL 请求失败: {exc}")
        return 1
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        print("GraphQL 返回非 JSON。")
        return 1
    errors = data.get("errors")
    if errors:
        print(f"GraphQL 返回 errors: {errors}")
        return 1
    elapsed = time.time() - start
    store_config = data.get("data", {}).get("storeConfig") or {}
    store_id = store_config.get("id", "unknown")
    print(f"GraphQL OK (store={store_id}, {elapsed:.2f}s)")
    return 0


def cmd_port_check(args: argparse.Namespace) -> int:
    host = args.host
    port = int(args.port)
    timeout = args.timeout
    try:
        with socket.create_connection((host, port), timeout=timeout):
            pass
    except OSError as exc:
        print(f"{host}:{port} 不可访问 ({exc})")
        return 1
    print(f"{host}:{port} 可访问")
    return 0


def cmd_ensure_env_default(args: argparse.Namespace) -> int:
    path = Path(args.file).resolve()
    lines: List[str] = []
    if path.exists():
        raw_lines = path.read_text(encoding="utf-8").splitlines()
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        raw_lines = []

    found = False
    for raw in raw_lines:
        if raw.strip().startswith("#") or "=" not in raw:
            lines.append(raw)
            continue
        key, _, value = raw.partition("=")
        if key.strip() == args.key:
            lines.append(f"{key.strip()}={value}")
            found = True
        else:
            lines.append(raw)

    if not found:
        lines.append(f"{args.key}={args.value}")

    output = "\n".join(lines).rstrip() + "\n"
    path.write_text(output, encoding="utf-8")
    return 0


def cmd_get_env(args: argparse.Namespace) -> int:
    path = Path(args.file).resolve()
    if not path.exists():
        return 0
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.strip().startswith("#") or "=" not in raw:
            continue
        key, _, value = raw.partition("=")
        if key.strip() == args.key:
            print(value.strip())
            break
    return 0


def cmd_patch_talon(args: argparse.Namespace) -> int:
    path = Path(args.file).resolve()
    try:
        text = _read_text(path)
    except FileNotFoundError:
        print("absent")
        return 0

    old_compare = """const attributeLabelCompare = (attribute1, attribute2) => {
    const label1 = attribute1['attribute_metadata']['label'].toLowerCase();
    const label2 = attribute2['attribute_metadata']['label'].toLowerCase();
    if (label1 < label2) return -1;
    else if (label1 > label2) return 1;
    else return 0;
};"""

    new_compare = """const attributeLabelCompare = (attribute1, attribute2) => {
    const label1 =
        attribute1?.attribute_metadata?.label ??
        attribute1?.attribute_option?.label ??
        '';
    const label2 =
        attribute2?.attribute_metadata?.label ??
        attribute2?.attribute_option?.label ??
        '';
    const safeLabel1 = label1.toLowerCase();
    const safeLabel2 = label2.toLowerCase();
    if (safeLabel1 < safeLabel2) return -1;
    else if (safeLabel1 > safeLabel2) return 1;
    else return 0;
};"""

    old_custom = """const getCustomAttributes = (product, optionCodes, optionSelections) => {
    const { custom_attributes, variants } = product;
    const isConfigurable = isProductConfigurable(product);
    const optionsSelected =
        Array.from(optionSelections.values()).filter(value => !!value).length >
        0;

    if (isConfigurable && optionsSelected) {
        const item = findMatchingVariant({
            optionCodes,
            optionSelections,
            variants
        });

        return item && item.product
            ? [...item.product.custom_attributes].sort(attributeLabelCompare)
            : [];
    }

    return custom_attributes
        ? [...custom_attributes].sort(attributeLabelCompare)
        : [];
};"""

    new_custom = """const getCustomAttributes = (product, optionCodes, optionSelections) => {
    const {
        custom_attributes: baseAttributes = [],
        variants = []
    } = product;
    const isConfigurable = isProductConfigurable(product);
    const optionsSelected =
        Array.from(optionSelections.values()).filter(value => !!value).length >
        0;

    if (isConfigurable && optionsSelected) {
        const item = findMatchingVariant({
            optionCodes,
            optionSelections,
            variants
        });

        const variantAttributes = item?.product?.custom_attributes || [];

        return variantAttributes.length
            ? [...variantAttributes].sort(attributeLabelCompare)
            : [];
    }

    return baseAttributes.length
        ? [...baseAttributes].sort(attributeLabelCompare)
        : [];
};"""

    updated = text
    if old_compare in updated:
        updated = updated.replace(old_compare, new_compare)
    if old_custom in updated:
        updated = updated.replace(old_custom, new_custom)

    if updated != text:
        path.write_text(updated, encoding="utf-8")
        print("patched")
    else:
        print("unchanged")
    return 0


def cmd_sanitize_checkout(args: argparse.Namespace) -> int:
    path = Path(args.file).resolve()
    try:
        text = _read_text(path)
    except FileNotFoundError:
        print("absent")
        return 0

    lines = text.splitlines()
    result: List[str] = []
    i = 0
    modified = False
    fields_to_sanitize = {
        "selected_payment_method": ["__typename", "code", "title"],
        "available_payment_methods": ["__typename", "code", "title"],
    }

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        matched_field = None
        for field in fields_to_sanitize:
            if (
                field in stripped
                and f"{field}s" not in stripped
                and "{" in line
                and stripped.startswith(field)
            ):
                matched_field = field
                break

        if matched_field:
            block_lines = [line]
            depth = line.count("{") - line.count("}")
            i += 1
            while i < len(lines) and depth > 0:
                block_lines.append(lines[i])
                depth += lines[i].count("{") - lines[i].count("}")
                i += 1
            if any("... on " in blk for blk in block_lines[1:]):
                indent = line[: len(line) - len(line.lstrip())]
                result.append(f"{indent}{matched_field} {{")
                for field_line in fields_to_sanitize[matched_field]:
                    result.append(f"{indent}    {field_line}")
                result.append(f"{indent}}}")
                modified = True
            else:
                result.extend(block_lines)
            continue
        result.append(line)
        i += 1

    if modified:
        new_text = "\n".join(result).rstrip() + "\n"
        path.write_text(new_text, encoding="utf-8")
        print("patched")
    else:
        print("unchanged")
    return 0


def cmd_remove_line(args: argparse.Namespace) -> int:
    path = Path(args.file).resolve()
    try:
        text = _read_text(path)
    except FileNotFoundError:
        print("absent")
        return 0
    filtered = "\n".join(line for line in text.splitlines() if args.contains not in line)
    if filtered and not filtered.endswith("\n"):
        filtered += "\n"
    if filtered != text:
        path.write_text(filtered, encoding="utf-8")
        print("removed")
    else:
        print("unchanged")
    return 0


def cmd_replace_line(args: argparse.Namespace) -> int:
    path = Path(args.file).resolve()
    try:
        text = _read_text(path)
    except FileNotFoundError:
        print("absent")
        return 0
    if args.old not in text:
        print("unchanged")
        return 0
    if args.new in text:
        print("unchanged")
        return 0
    path.write_text(text.replace(args.old, args.new), encoding="utf-8")
    print("replaced")
    return 0


def cmd_add_guard(args: argparse.Namespace) -> int:
    path = Path(args.file).resolve()
    try:
        text = _read_text(path)
    except FileNotFoundError:
        print("absent")
        return 0
    guard = (
        "module.exports = targets => {\n"
        f"    if (process.env.{args.env_var} !== 'true') {{\n"
        "        return;\n"
        "    }\n"
    )
    if not text.startswith("module.exports = targets => {\n"):
        print("unchanged")
        return 0
    if guard in text:
        print("unchanged")
        return 0
    text = text.replace("module.exports = targets => {\n", guard, 1)
    path.write_text(text, encoding="utf-8")
    print("patched")
    return 0


def cmd_tune_webpack(args: argparse.Namespace) -> int:
    path = Path(args.file).resolve()
    try:
        text = _read_text(path)
    except FileNotFoundError:
        print("absent")
        return 0
    if "config.performance.hints = false" in text:
        print("unchanged")
        return 0
    marker = "    return [config];"
    snippet = (
        "    config.performance = config.performance || {};\n"
        "    config.performance.hints = false;\n"
        "    config.performance.maxEntrypointSize = 1200 * 1024;\n"
        "    config.performance.maxAssetSize = 800 * 1024;\n"
    )
    if marker not in text:
        print("unchanged")
        return 0
    updated = text.replace(marker, snippet + "\n" + marker)
    if updated == text:
        print("unchanged")
        return 0
    path.write_text(updated, encoding="utf-8")
    print("patched")
    return 0


def cmd_load_config(args: argparse.Namespace) -> int:
    if yaml is None:
        raise RuntimeError("PyYAML 未安装，无法解析配置")
    config_path = Path(args.config)
    if not config_path.exists():
        raise RuntimeError(f"配置文件不存在: {config_path}")
    try:
        data = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    except Exception as exc:
        raise RuntimeError(f"无法解析 {config_path}: {exc}") from exc

    sites = (data.get("magento_pwa") or {}).get("sites") or {}
    cfg = sites.get(args.site)
    if not isinstance(cfg, dict):
        raise RuntimeError(f"未在 {config_path} 中找到站点 {args.site}")

    def emit(key: str, value) -> None:
        if value is None:
            value = ""
        print(f'{key}={json.dumps(value)}')

    emit("PWA_SITE_NAME", args.site)
    emit("PWA_ROOT", cfg.get("root", f"/var/www/{args.site}"))
    emit("PWA_BASE_URL", cfg.get("base_url", f"http://{args.site}.example.com/"))
    emit("PWA_BASE_URL_SECURE", cfg.get("base_url_secure", cfg.get("base_url", f"https://{args.site}.example.com/")))

    admin = cfg.get("admin") or {}
    emit("PWA_ADMIN_FRONTNAME", admin.get("frontname", "admin"))
    emit("PWA_ADMIN_FIRSTNAME", admin.get("firstname", "Admin"))
    emit("PWA_ADMIN_LASTNAME", admin.get("lastname", "User"))
    emit("PWA_ADMIN_EMAIL", admin.get("email", f"{args.site}@example.com"))
    emit("PWA_ADMIN_USER", admin.get("user", args.site))
    emit("PWA_ADMIN_PASSWORD", admin.get("password", "ChangeMe!"))

    emit("PWA_CRYPT_KEY", cfg.get("crypt_key", ""))

    db = cfg.get("db") or {}
    emit("PWA_DB_HOST", db.get("host", "localhost"))
    emit("PWA_DB_NAME", db.get("name", f"{args.site}mage"))
    emit("PWA_DB_USER", db.get("user", args.site))
    emit("PWA_DB_PASSWORD", db.get("password", "ChangeMeDb!"))

    emit("PWA_TIMEZONE", cfg.get("timezone", "UTC"))
    emit("PWA_LOCALE", cfg.get("locale", "en_US"))
    emit("PWA_CURRENCY", cfg.get("currency", "USD"))

    composer = cfg.get("composer") or {}
    emit("PWA_REPO_USER", composer.get("repo_user", ""))
    emit("PWA_REPO_PASS", composer.get("repo_pass", ""))

    opensearch = cfg.get("opensearch") or {}
    emit("PWA_OPENSEARCH_HOST", opensearch.get("host", "localhost"))
    emit("PWA_OPENSEARCH_PORT", opensearch.get("port", 9200))
    emit("PWA_OPENSEARCH_SCHEME", opensearch.get("scheme", "http"))
    emit("PWA_OPENSEARCH_PREFIX", opensearch.get("index_prefix", args.site))
    emit("PWA_OPENSEARCH_USERNAME", opensearch.get("username", ""))
    emit("PWA_OPENSEARCH_PASSWORD", opensearch.get("password", ""))
    emit("PWA_OPENSEARCH_TIMEOUT", opensearch.get("timeout", 15))
    emit(
        "PWA_OPENSEARCH_AUTH",
        bool(opensearch.get("username") or opensearch.get("password") or opensearch.get("enable_auth", False)),
    )

    options = cfg.get("options") or {}
    emit("PWA_USE_SECURE", options.get("use_secure", True))
    emit("PWA_USE_SECURE_ADMIN", options.get("use_secure_admin", True))
    emit("PWA_USE_REWRITES", options.get("use_rewrites", True))
    emit("PWA_CLEANUP_DATABASE", options.get("cleanup_database", True))

    node_cfg = cfg.get("node") or {}
    emit("PWA_ENSURE_NODE", node_cfg.get("ensure", True))
    emit("PWA_NODE_VERSION", node_cfg.get("version", "18"))
    emit("PWA_INSTALL_YARN", node_cfg.get("install_yarn", True))
    emit("PWA_NODE_PROVIDER", node_cfg.get("provider", "nodesource"))

    services = cfg.get("services") or {}
    emit("PWA_INSTALL_CRON", services.get("install_cron", True))
    emit("PWA_CONFIGURE_VALKEY", services.get("configure_valkey", False))
    emit("PWA_CONFIGURE_RABBITMQ", services.get("configure_rabbitmq", False))

    pwa_studio = cfg.get("pwa_studio") or {}
    emit("PWA_STUDIO_ENABLE", pwa_studio.get("enable", False))
    emit("PWA_STUDIO_REPO", pwa_studio.get("repo", "https://github.com/magento/pwa-studio.git"))
    emit("PWA_STUDIO_BRANCH", pwa_studio.get("branch", "develop"))
    target_dir = pwa_studio.get("target_dir", f"{cfg.get('root', f'/var/www/{args.site}')}/pwa-studio")
    emit("PWA_STUDIO_DIR", target_dir)
    emit("PWA_STUDIO_INSTALL_COMMAND", pwa_studio.get("yarn_command", "yarn install"))
    emit("PWA_STUDIO_BUILD_COMMAND", pwa_studio.get("build_command", "yarn build"))
    emit(
        "PWA_STUDIO_SERVE_COMMAND",
        pwa_studio.get(
            "serve_command",
            "/usr/bin/env yarn workspace @magento/venia-concept run start",
        ),
    )
    emit("PWA_STUDIO_ENV_TEMPLATE", pwa_studio.get("env_template", "packages/venia-concept/.env.dist"))
    env_file_default = pwa_studio.get("env_file", f"{target_dir}/.env")
    emit("PWA_STUDIO_ENV_FILE", env_file_default)
    emit("PWA_STUDIO_PORT", pwa_studio.get("serve_port", 8082))

    overrides = pwa_studio.get("env_overrides", {})
    encoded = base64.b64encode(json.dumps(overrides).encode()).decode()
    print(f'PWA_STUDIO_ENV_OVERRIDES_B64="{encoded}"')

    cms_cfg = ((cfg.get("cms") or {}).get("home")) or {}

    def normalize_store_ids(value) -> List[str]:
        if value is None:
            return ["0"]
        if isinstance(value, (list, tuple)):
            return [str(v) for v in value] or ["0"]
        return [str(value)]

    emit("PWA_HOME_TITLE", cms_cfg.get("title", "PWA Home"))
    emit("PWA_HOME_TEMPLATE", cms_cfg.get("template", ""))
    emit("PWA_HOME_STORE_IDS", ",".join(normalize_store_ids(cms_cfg.get("store_ids"))))
    emit("PWA_HOME_IDENTIFIER", cms_cfg.get("identifier", ""))
    emit("PWA_HOME_FORCE_TEMPLATE", cms_cfg.get("force_template", True))
    return 0


def cmd_patch_product_fragment(args: argparse.Namespace) -> int:
    path = Path(args.file).resolve()
    try:
        original = _read_text(path)
    except FileNotFoundError:
        print("absent")
        return 0

    text = original

    def strip_block(source: str, marker: str) -> str:
        while True:
            idx = source.find(marker)
            if idx == -1:
                return source
            start = source.rfind("\n", 0, idx)
            if start == -1:
                start = idx
            depth = 0
            i = idx
            while i < len(source):
                ch = source[i]
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
                    if depth == 0:
                        i += 1
                        break
                i += 1
            source = source[:start] + source[i:]

    def strip_lines(source: str, keyword: str) -> str:
        lines = [line for line in source.splitlines() if keyword not in line]
        return "\n".join(lines) + "\n"

    text = strip_block(text, "attribute_metadata {")
    text = strip_lines(text, "... on ProductAttributeMetadata")
    text = strip_lines(text, "used_in_components")
    text = strip_block(text, "custom_attributes {")
    text = strip_lines(text, "selected_attribute_options")
    text = strip_lines(text, "entered_attribute_value")

    if text != original:
        path.write_text(text, encoding="utf-8")
        print("patched")
    else:
        print("unchanged")
    return 0


def cmd_check_react(args: argparse.Namespace) -> int:
    root = Path(args.dir).resolve() / "node_modules"
    if not root.exists():
        print("skip")
        return 0
    names = ["react", "react-dom"]
    report: List[str] = []
    exit_code = 0
    for name in names:
        versions = set()
        for pkg in root.rglob(f"*/{name}/package.json"):
            if ".cache" in pkg.parts:
                continue
            try:
                data = json.loads(pkg.read_text(encoding="utf-8"))
            except Exception:
                continue
            if data.get("name") == name:
                version = data.get("version")
                if version:
                    versions.add(version)
        if not versions:
            report.append(f"{name}=missing")
            exit_code = 1
        elif len(versions) == 1:
            report.append(f"{name}={next(iter(versions))}")
        else:
            report.append(f"{name}={','.join(sorted(versions))}")
            exit_code = 1
    print("; ".join(report))
    return exit_code


def cmd_react_version_check(args: argparse.Namespace) -> int:
    proxy = argparse.Namespace(dir=args.root)
    return cmd_check_react(proxy)


def cmd_react_debug(args: argparse.Namespace) -> int:
    service = args.service
    workdir = _get_unit_workdir(service)
    if not workdir:
        return 0
    pkg_path = workdir / "package.json"
    if not pkg_path.exists():
        return 0
    try:
        data = json.loads(pkg_path.read_text(encoding="utf-8"))
    except Exception:
        return 0
    deps: Dict[str, str] = {}
    for section in ("dependencies", "devDependencies", "peerDependencies"):
        raw = data.get(section)
        if isinstance(raw, dict):
            deps.update({k: str(v) for k, v in raw.items()})
    react = deps.get("react")
    react_dom = deps.get("react-dom")
    report = []
    if react:
        report.append(f"react={react}")
    if react_dom:
        report.append(f"react-dom={react_dom}")
    if report:
        print("; ".join(report))
    return 0


def cmd_validate_graphql(args: argparse.Namespace) -> int:
    payload_text = args.payload or ""
    try:
        payload = json.loads(payload_text)
    except Exception:
        print("GraphQL 接口返回非 JSON 内容。")
        return 1
    errors = payload.get("errors")
    if errors:
        print(f"GraphQL 返回 errors: {errors}")
        return 1
    return 0


def cmd_fix_order_history(args: argparse.Namespace) -> int:
    path = Path(args.file).resolve()
    try:
        text = _read_text(path)
    except FileNotFoundError:
        print("absent")
        return 0

    lines = text.splitlines()
    changed = False
    for idx, line in enumerate(lines):
        if line.strip() == "state":
            indent = line[: len(line) - len(line.lstrip())]
            replacement = f"{indent}status"
            if line != replacement:
                lines[idx] = replacement
                changed = True

    if not changed:
        print("unchanged")
        return 0

    new_text = "\n".join(lines)
    if text.endswith("\n"):
        new_text += "\n"
    path.write_text(new_text, encoding="utf-8")
    print("patched")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="PWA helper CLI")
    sub = parser.add_subparsers(dest="command", required=True)

    decode = sub.add_parser("decode-b64", help="Decode base64 JSON, fallback to {}")
    decode.add_argument("--data", default="")
    decode.set_defaults(func=cmd_decode)

    apply_env = sub.add_parser("apply-env", help="Apply overrides to env file")
    apply_env.add_argument("--file", required=True)
    apply_env.add_argument("--overrides", required=True)
    apply_env.set_defaults(func=cmd_apply_env)

    ensure_workspace = sub.add_parser("ensure-workspace", help="Ensure workspace entry/dependency exists")
    ensure_workspace.add_argument("--root", required=True, help="PWA Studio 根目录")
    ensure_workspace.add_argument("--workspace", required=True, help="Workspaces 项条目")
    ensure_workspace.add_argument("--dependency", help="依赖名称，可选")
    ensure_workspace.add_argument("--value", help="依赖值，默认 link:<workspace>")
    ensure_workspace.set_defaults(func=cmd_ensure_workspace)

    ensure_workspace_dep = sub.add_parser("ensure-workspace-dependency", help="Ensure dependency entry exists in package.json")
    ensure_workspace_dep.add_argument("--file", required=True)
    ensure_workspace_dep.add_argument("--package", required=True)
    ensure_workspace_dep.add_argument("--value", required=True)
    ensure_workspace_dep.set_defaults(func=cmd_ensure_workspace_dependency)

    set_field = sub.add_parser("set-field", help="Set package.json section entry")
    set_field.add_argument("--file", required=True)
    set_field.add_argument("--section", required=True)
    set_field.add_argument("--name", required=True)
    set_field.add_argument("--value", required=True)
    set_field.set_defaults(func=cmd_set_field)

    ensure_pkg_field = sub.add_parser("ensure-package-field", help="Ensure top-level package.json field equals value")
    ensure_pkg_field.add_argument("--file", required=True)
    ensure_pkg_field.add_argument("--field", required=True)
    ensure_pkg_field.add_argument("--value", required=True)
    ensure_pkg_field.set_defaults(func=cmd_ensure_package_field)

    remove_field = sub.add_parser("remove-field", help="Remove package.json section entry")
    remove_field.add_argument("--file", required=True)
    remove_field.add_argument("--section", required=True)
    remove_field.add_argument("--name", required=True)
    remove_field.set_defaults(func=cmd_remove_field)

    remove_pkg_field = sub.add_parser("remove-package-field", help="Remove top-level package.json field")
    remove_pkg_field.add_argument("--file", required=True)
    remove_pkg_field.add_argument("--field", required=True)
    remove_pkg_field.set_defaults(func=cmd_remove_package_field)

    ensure_pkg_dep = sub.add_parser("ensure-package-dependency", help="Ensure dependency entry exists")
    ensure_pkg_dep.add_argument("--file", required=True)
    ensure_pkg_dep.add_argument("--package", required=True)
    ensure_pkg_dep.add_argument("--version", required=True)
    ensure_pkg_dep.set_defaults(func=cmd_ensure_package_dependency)

    ensure_pkg_dev_dep = sub.add_parser("ensure-package-dev-dependency", help="Ensure devDependency entry exists")
    ensure_pkg_dev_dep.add_argument("--file", required=True)
    ensure_pkg_dev_dep.add_argument("--package", required=True)
    ensure_pkg_dev_dep.add_argument("--version", required=True)
    ensure_pkg_dev_dep.set_defaults(func=cmd_ensure_package_dev_dependency)

    remove_pkg_dep = sub.add_parser("remove-package-dependency", help="Remove dependency/devDependency entry")
    remove_pkg_dep.add_argument("--file", required=True)
    remove_pkg_dep.add_argument("--package", required=True)
    remove_pkg_dep.set_defaults(func=cmd_remove_package_dependency)

    ensure_env = sub.add_parser("ensure-env-default", help="Ensure env key exists with default value")
    ensure_env.add_argument("--file", required=True)
    ensure_env.add_argument("--key", required=True)
    ensure_env.add_argument("--value", required=True)
    ensure_env.set_defaults(func=cmd_ensure_env_default)

    get_env = sub.add_parser("get-env", help="Read env value for key (prints blank if missing)")
    get_env.add_argument("--file", required=True)
    get_env.add_argument("--key", required=True)
    get_env.set_defaults(func=cmd_get_env)

    patch_talon = sub.add_parser("patch-talon", help="Patch ProductFullDetail talon for safe attributes")
    patch_talon.add_argument("--file", required=True)
    patch_talon.set_defaults(func=cmd_patch_talon)

    sanitize_checkout = sub.add_parser("sanitize-checkout", help="Sanitize checkout GraphQL fragments")
    sanitize_checkout.add_argument("--file", required=True)
    sanitize_checkout.set_defaults(func=cmd_sanitize_checkout)

    remove_line = sub.add_parser("remove-line", help="Remove lines containing substring")
    remove_line.add_argument("--file", required=True)
    remove_line.add_argument("--contains", required=True)
    remove_line.set_defaults(func=cmd_remove_line)

    replace_line = sub.add_parser("replace-line", help="Replace a line when exact match is found")
    replace_line.add_argument("--file", required=True)
    replace_line.add_argument("--old", required=True)
    replace_line.add_argument("--new", required=True)
    replace_line.set_defaults(func=cmd_replace_line)

    add_guard = sub.add_parser("add-guard", help="Wrap module.exports with environment guard")
    add_guard.add_argument("--file", required=True)
    add_guard.add_argument("--env-var", required=True)
    add_guard.set_defaults(func=cmd_add_guard)

    prune_ext = sub.add_parser("prune-extensions", help="Remove sample extensions under packages/extensions")
    prune_ext.add_argument("--root", required=True)
    prune_ext.set_defaults(func=cmd_prune_extensions)

    tune_webpack = sub.add_parser("tune-webpack", help="Tune webpack performance hints")
    tune_webpack.add_argument("--file", required=True)
    tune_webpack.set_defaults(func=cmd_tune_webpack)

    patch_fragment = sub.add_parser("patch-product-fragment", help="Sanitize product detail fragment for MOS")
    patch_fragment.add_argument("--file", required=True)
    patch_fragment.set_defaults(func=cmd_patch_product_fragment)

    load_cfg = sub.add_parser("load-config", help="Load magento-pwa config and emit environment variables")
    load_cfg.add_argument("--config", required=True)
    load_cfg.add_argument("--site", required=True)
    load_cfg.set_defaults(func=cmd_load_config)

    ensure_peer = sub.add_parser("ensure-peer-deps", help="Ensure peerDependencies align with dependencies")
    ensure_peer.add_argument("--file", required=True)
    ensure_peer.set_defaults(func=cmd_ensure_peer_deps)

    list_graphql = sub.add_parser("list-graphql-files", help="List GraphQL fragment sources under root")
    list_graphql.add_argument("--root", required=True)
    list_graphql.set_defaults(func=cmd_list_graphql_files)

    sanitize_graphql = sub.add_parser("sanitize-graphql", help="Remove Commerce-only GraphQL fields")
    sanitize_graphql.add_argument("--file", required=True)
    sanitize_graphql.set_defaults(func=cmd_sanitize_graphql)

    sanitize_orders = sub.add_parser("sanitize-orders", help="Align orders component with MOS schema")
    sanitize_orders.add_argument("--file", required=True)
    sanitize_orders.set_defaults(func=cmd_sanitize_orders)

    sanitize_payment = sub.add_parser("sanitize-payment", help="Harden payment info component for missing fields")
    sanitize_payment.add_argument("--file", required=True)
    sanitize_payment.set_defaults(func=cmd_sanitize_payment)

    sanitize_cart = sub.add_parser("sanitize-cart-trigger", help="Remove unsupported cart trigger fields")
    sanitize_cart.add_argument("--file", required=True)
    sanitize_cart.set_defaults(func=cmd_sanitize_cart_trigger)

    patch_custom_attrs = sub.add_parser(
        "patch-product-custom-attributes",
        help="Harden ProductFullDetail custom attribute access",
    )
    patch_custom_attrs.add_argument("--file", required=True)
    patch_custom_attrs.set_defaults(func=cmd_patch_product_custom_attributes)

    check_react = sub.add_parser("check-react", help="Verify React dependencies versions")
    check_react.add_argument("--dir", required=True)
    check_react.set_defaults(func=cmd_check_react)

    react_version = sub.add_parser("react-version-check", help="Report React versions under node_modules")
    react_version.add_argument("--root", required=True)
    react_version.set_defaults(func=cmd_react_version_check)

    react_debug = sub.add_parser("react-debug", help="Inspect systemd service to report React versions")
    react_debug.add_argument("--service", required=True)
    react_debug.set_defaults(func=cmd_react_debug)

    graphql_ping = sub.add_parser("graphql-ping", help="Check Magento GraphQL endpoint availability")
    graphql_ping.add_argument("--endpoint", required=True)
    graphql_ping.add_argument("--query", help="Custom GraphQL query")
    graphql_ping.add_argument("--timeout", type=float, default=10.0)
    graphql_ping.set_defaults(func=cmd_graphql_ping)

    port_check = sub.add_parser("port-check", help="Check TCP port connectivity")
    port_check.add_argument("--host", default="127.0.0.1")
    port_check.add_argument("--port", required=True)
    port_check.add_argument("--timeout", type=float, default=3.0)
    port_check.set_defaults(func=cmd_port_check)

    validate_graphql = sub.add_parser("validate-graphql", help="Validate Magento GraphQL probe response")
    validate_graphql.add_argument("--payload", required=True)
    validate_graphql.set_defaults(func=cmd_validate_graphql)

    fix_order_history = sub.add_parser(
        "fix-order-history", help="Replace deprecated CustomerOrder.state field with status"
    )
    fix_order_history.add_argument("--file", required=True)
    fix_order_history.set_defaults(func=cmd_fix_order_history)

    return parser


def main(argv: Iterable[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
