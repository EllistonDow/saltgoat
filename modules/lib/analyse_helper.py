#!/usr/bin/env python3
"""Analyse helper for Pillar/state diffing."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Iterable


class SaltCallError(RuntimeError):
    pass


def run(cmd: list[str]) -> str:
    proc = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise SaltCallError(proc.stderr.strip())
    return proc.stdout.strip()


def cmd_pillar(args: argparse.Namespace) -> int:
    pillar_path = Path(args.pillar)
    if not pillar_path.exists():
        print("{}")
        return 0
    cmd = [
        "salt-call",
        "--local",
        "--out=json",
        "slsutil.renderer",
        str(pillar_path),
    ]
    try:
        output = run(cmd)
    except SaltCallError as exc:
        print(exc, file=sys.stderr)
        print("{}")
        return 0
    data = json.loads(output).get("local", {})
    print(json.dumps(data, ensure_ascii=False))
    return 0


def cmd_state(args: argparse.Namespace) -> int:
    pillar_json = args.pillar
    pillar_data = json.loads(pillar_json) if pillar_json else {}
    state = args.state
    cmd = [
        "salt-call",
        "--local",
        "--out=json",
        "state.show_sls",
        state,
        f"pillar={json.dumps(pillar_data)}",
    ]
    output = run(cmd)
    data = json.loads(output).get("local", {})
    print(json.dumps(data, ensure_ascii=False))
    return 0


def cmd_diff(args: argparse.Namespace) -> int:
    data = json.loads(Path(args.file).read_text(encoding="utf-8"))
    before = data.get("before_reference")
    after = data.get("after_reference")
    from difflib import unified_diff

    before_lines = before.splitlines() if isinstance(before, str) else []
    after_lines = after.splitlines() if isinstance(after, str) else []
    for line in unified_diff(before_lines, after_lines, lineterm=""):
        print(line)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Analyse helper CLI")
    sub = parser.add_subparsers(dest="command", required=True)

    pillar = sub.add_parser("pillar", help="Render pillar file via salt-call")
    pillar.add_argument("--pillar", required=True)
    pillar.set_defaults(func=cmd_pillar)

    state = sub.add_parser("state", help="Render state.show_sls with pillar data")
    state.add_argument("--state", required=True)
    state.add_argument("--pillar", default="")
    state.set_defaults(func=cmd_state)

    diff = sub.add_parser("diff", help="Show unified diff for analyse result")
    diff.add_argument("--file", required=True)
    diff.set_defaults(func=cmd_diff)

    return parser


def main(argv: Iterable[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
