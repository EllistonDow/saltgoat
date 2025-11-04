#!/usr/bin/env python3
"""Helpers for Magento PWA install workflow."""

from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path
from typing import Iterable


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

    return parser


def main(argv: Iterable[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
