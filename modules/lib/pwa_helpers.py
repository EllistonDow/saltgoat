#!/usr/bin/env python3
"""Helpers for Magento PWA install workflow."""

from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path
from typing import Iterable, List

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


def _read_text(path: Path) -> str:
    if not path.exists():
        raise FileNotFoundError(f"{path} 不存在")
    return path.read_text(encoding="utf-8")


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

    set_field = sub.add_parser("set-field", help="Set package.json section entry")
    set_field.add_argument("--file", required=True)
    set_field.add_argument("--section", required=True)
    set_field.add_argument("--name", required=True)
    set_field.add_argument("--value", required=True)
    set_field.set_defaults(func=cmd_set_field)

    remove_field = sub.add_parser("remove-field", help="Remove package.json section entry")
    remove_field.add_argument("--file", required=True)
    remove_field.add_argument("--section", required=True)
    remove_field.add_argument("--name", required=True)
    remove_field.set_defaults(func=cmd_remove_field)

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

    check_react = sub.add_parser("check-react", help="Verify React dependencies versions")
    check_react.add_argument("--dir", required=True)
    check_react.set_defaults(func=cmd_check_react)

    validate_graphql = sub.add_parser("validate-graphql", help="Validate Magento GraphQL probe response")
    validate_graphql.add_argument("--payload", required=True)
    validate_graphql.set_defaults(func=cmd_validate_graphql)

    return parser


def main(argv: Iterable[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
