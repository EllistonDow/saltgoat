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

    return parser


def main(argv: Iterable[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
