#!/usr/bin/env python3
"""Helpers for parsing salt-call mysql module output."""

from __future__ import annotations

import argparse
import json
from typing import Iterable


def extract_json(text: str) -> dict:
    start = text.find("{")
    if start == -1:
        raise ValueError("Salt 输出缺少 JSON")
    return json.loads(text[start:])


def cmd_bool(args: argparse.Namespace) -> int:
    data = extract_json(args.payload)
    value = data.get("local")
    if isinstance(value, bool):
        result = "1" if value else "0"
    elif isinstance(value, str):
        result = "1" if value.lower() == "true" else "0"
    else:
        result = "1" if value else "0"
    print(result)
    return 0


def cmd_print(args: argparse.Namespace) -> int:
    data = extract_json(args.payload)
    value = data.get("local")
    if value is not None:
        if isinstance(value, bool):
            print("true" if value else "false")
        else:
            print(value)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Salt mysql helper")
    sub = parser.add_subparsers(dest="command", required=True)

    bool_parser = sub.add_parser("bool", help="Render bool from salt-call output")
    bool_parser.add_argument("--payload", required=True)
    bool_parser.set_defaults(func=cmd_bool)

    print_parser = sub.add_parser("print", help="Print salt-call local value")
    print_parser.add_argument("--payload", required=True)
    print_parser.set_defaults(func=cmd_print)

    return parser


def main(argv: Iterable[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
