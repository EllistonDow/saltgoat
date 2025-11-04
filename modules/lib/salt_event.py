#!/usr/bin/env python3
"""Salt event helper for SaltGoat shell tooling."""
from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Dict, Iterable

FORCE_FALLBACK = os.environ.get("SALTGOAT_FORCE_EVENT_FALLBACK") == "1"


def parse_pairs(pairs: Iterable[str]) -> Dict[str, str]:
    data: Dict[str, str] = {}
    for pair in pairs:
        if "=" not in pair:
            continue
        key, value = pair.split("=", 1)
        data[key] = value
    return data


def try_send(tag: str, data: Dict[str, str]) -> None:
    if FORCE_FALLBACK:
        raise RuntimeError("forced fallback")
    try:
        from salt.client import Caller  # type: ignore
    except Exception as exc:  # pragma: no cover - fallback path
        raise RuntimeError(str(exc)) from exc

    try:
        caller = Caller()
        caller.cmd("event.send", tag, data)
    except Exception as exc:  # pragma: no cover - fallback path
        raise RuntimeError(str(exc)) from exc


def cmd_send(args: argparse.Namespace) -> int:
    data = parse_pairs(args.pairs)
    if args.extra_json:
        try:
            data.update(json.loads(args.extra_json))
        except json.JSONDecodeError as exc:
            raise SystemExit(f"Invalid JSON payload: {exc}") from exc
    try:
        try_send(args.tag, data)
    except RuntimeError:
        # Signal fallback: emit payload for salt-call usage.
        print(json.dumps(data, ensure_ascii=False))
        return 2
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="SaltGoat salt-event helper")
    sub = parser.add_subparsers(dest="command", required=True)

    send = sub.add_parser("send", help="Send salt event, fallback to JSON output")
    send.add_argument("--tag", required=True, help="Salt event tag")
    send.add_argument(
        "--extra-json",
        default="",
        help="Additional JSON payload merged with key=value pairs",
    )
    send.add_argument("pairs", nargs="*", help="Additional key=value entries")
    send.set_defaults(func=cmd_send)

    fmt = sub.add_parser("format", help="Format payload as JSON")
    fmt.add_argument("--tag", required=True, help="Salt event tag (unused)")
    fmt.add_argument(
        "--extra-json",
        default="",
        help="Additional JSON payload merged with key=value pairs",
    )
    fmt.add_argument("pairs", nargs="*", help="Additional key=value entries")
    fmt.set_defaults(func=cmd_send_format)

    return parser


def cmd_send_format(args: argparse.Namespace) -> int:
    data = parse_pairs(args.pairs)
    if args.extra_json:
        try:
            data.update(json.loads(args.extra_json))
        except json.JSONDecodeError as exc:
            raise SystemExit(f"Invalid JSON payload: {exc}") from exc
    print(json.dumps(data, ensure_ascii=False))
    return 0


def main(argv: Iterable[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
