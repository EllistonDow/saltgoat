#!/usr/bin/env python3
"""Utilities for automation CLI JSON parsing."""

from __future__ import annotations

import argparse
import json
import sys
from typing import Iterable


def load_payload(json_arg: str | None) -> dict:
    if json_arg:
        return json.loads(json_arg)
    data = sys.stdin.read()
    if not data:
        raise SystemExit("missing JSON payload")
    return json.loads(data)


def first_result(payload: dict) -> dict:
    if not payload:
        return {}
    return next(iter(payload.values()))


def cmd_render_basic(args: argparse.Namespace) -> int:
    payload = load_payload(args.json)
    result = first_result(payload)
    ok = bool(result.get("result", True))
    comment = result.get("comment") or ("操作完成" if ok else "操作失败")
    comment = comment.replace("\n", " ")
    print(comment)
    return 0 if ok else 1


def cmd_extract_field(args: argparse.Namespace) -> int:
    payload = load_payload(args.json)
    result = first_result(payload)
    value = result.get(args.field)
    if value is None:
        return 1
    if isinstance(value, bool):
        print("true" if value else "false")
    else:
        print(value)
    return 0


def cmd_parse_paths(args: argparse.Namespace) -> int:
    payload = load_payload(args.json)
    result = first_result(payload)
    paths = result.get("paths") or {}
    base = paths.get("base_dir", "/srv/saltgoat/automation")
    scripts = paths.get("scripts_dir", f"{base}/scripts")
    jobs = paths.get("jobs_dir", f"{base}/jobs")
    logs = paths.get("logs_dir", f"{base}/logs")
    print(base)
    print(scripts)
    print(jobs)
    print(logs)
    return 0


def cmd_render_scripts(args: argparse.Namespace) -> int:
    payload = load_payload(args.json)
    result = first_result(payload)
    scripts = result.get("scripts") or []
    if not scripts:
        print("暂无脚本，可使用 'saltgoat automation script create <name>' 创建。")
        return 0
    for item in scripts:
        name = item.get("name", "unknown")
        print(f"- {name}")
        print(f"  路径: {item.get('path')}")
        print(f"  修改时间: {item.get('modified')}")
        size = item.get("size")
        if size is not None:
            print(f"  大小: {size} 字节")
    return 0


def cmd_render_jobs(args: argparse.Namespace) -> int:
    payload = load_payload(args.json)
    result = first_result(payload)
    jobs = result.get("jobs") or []
    if not jobs:
        print("暂无任务，可使用 'saltgoat automation job create ...' 创建。")
        return 0
    for item in jobs:
        name = item.get("name", "unknown")
        enabled = "已启用" if item.get("enabled") else "已禁用"
        backend = item.get("backend", "unknown")
        active = "运行中" if item.get("active") else "未调度"
        warning = " ⚠ 脚本缺失" if item.get("script_missing") else ""
        print(f"- {name} [{enabled}/{backend}] {active}{warning}")
        cron = item.get("cron")
        if cron:
            print(f"  Cron: {cron}")
        script_path = item.get("script_path")
        if script_path:
            print(f"  脚本: {script_path}")
        last_run = item.get("last_run")
        if last_run:
            ret = item.get("last_retcode")
            print(f"  最近执行: {last_run} (retcode={ret})")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="SaltGoat automation JSON helpers")
    sub = parser.add_subparsers(dest="command", required=True)

    basic = sub.add_parser("render-basic", help="Render comment and exit code")
    basic.add_argument("--json", help="JSON payload", default=None)
    basic.set_defaults(func=cmd_render_basic)

    extract = sub.add_parser("extract-field", help="Extract field from result")
    extract.add_argument("field", help="Field name to extract")
    extract.add_argument("--json", help="JSON payload", default=None)
    extract.set_defaults(func=cmd_extract_field)

    paths = sub.add_parser("parse-paths", help="Parse automation paths from init result")
    paths.add_argument("--json", help="JSON payload", default=None)
    paths.set_defaults(func=cmd_parse_paths)

    scripts = sub.add_parser("render-scripts", help="Render script list in human format")
    scripts.add_argument("--json", help="JSON payload", default=None)
    scripts.set_defaults(func=cmd_render_scripts)

    jobs = sub.add_parser("render-jobs", help="Render job list in human format")
    jobs.add_argument("--json", help="JSON payload", default=None)
    jobs.set_defaults(func=cmd_render_jobs)

    return parser


def main(argv: Iterable[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
