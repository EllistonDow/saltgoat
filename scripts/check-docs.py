#!/usr/bin/env python3
"""
Lightweight documentation linter used by SaltGoat tooling.

Checks Markdown files under docs/ for:
1. Presence of a level-1 heading on the first non-empty line.
2. Absence of trailing whitespace.
3. No tab characters (prefer spaces to keep rendering consistent).

Exits with code 0 when all checks pass, otherwise prints per-file diagnostics
and exits with code 1.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Iterable, List, Tuple


ROOT = Path(__file__).resolve().parents[1]
DOCS_DIR = ROOT / "docs"


class Issue:
    def __init__(self, path: Path, line_no: int, message: str) -> None:
        self.path = path
        self.line_no = line_no
        self.message = message

    def __str__(self) -> str:  # pragma: no cover - trivial formatting
        rel = self.path.relative_to(ROOT)
        return f"{rel}:{self.line_no}: {self.message}"


def check_heading(path: Path, lines: List[str]) -> Iterable[Issue]:
    for index, raw in enumerate(lines, start=1):
        stripped = raw.strip()
        if not stripped:
            continue
        if not stripped.startswith("# "):
            yield Issue(path, index, "missing level-1 heading at top of document")
        break


def check_trailing_whitespace(path: Path, lines: List[str]) -> Iterable[Issue]:
    for index, raw in enumerate(lines, start=1):
        if raw.rstrip("\n").rstrip("\r").rstrip(" \t") != raw.rstrip("\n").rstrip("\r"):
            yield Issue(path, index, "trailing whitespace detected")


def check_tabs(path: Path, lines: List[str]) -> Iterable[Issue]:
    for index, raw in enumerate(lines, start=1):
        if "\t" in raw:
            yield Issue(path, index, "tab character found; use spaces instead")


def lint_file(path: Path, autofix: bool = False) -> Iterable[Issue]:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        yield Issue(path, 1, "unable to decode using UTF-8")
        return
    trailing_fix_applied = False
    lines = text.splitlines()
    yield from check_heading(path, lines)
    trailing_issues = list(check_trailing_whitespace(path, lines))
    yield from check_tabs(path, lines)

    if autofix and trailing_issues:
        cleaned = [line.rstrip(" \t") for line in text.splitlines()]
        path.write_text("\n".join(cleaned) + ("\n" if text.endswith("\n") else ""), encoding="utf-8")
        trailing_fix_applied = True
        trailing_issues = []

    for issue in trailing_issues:
        yield issue
    if autofix and trailing_fix_applied:
        print(f"[FIXED] Removed trailing whitespace: {path.relative_to(ROOT)}")


def collect_markdown_files() -> List[Path]:
    return sorted(DOCS_DIR.glob("*.md"))


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate SaltGoat documentation formatting.")
    parser.add_argument(
        "--fix",
        action="store_true",
        help="自动移除尾随空格（仅限 docs/*.md），其它问题仍需手动处理。",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="以 JSON 格式输出结果，便于 CI/脚本消费。",
    )
    args = parser.parse_args(argv)

    missing_dir = not DOCS_DIR.exists()
    if missing_dir:
        print(f"[ERROR] docs directory not found: {DOCS_DIR}", file=sys.stderr)
        return 1

    files = collect_markdown_files()
    if not files:
        print("[INFO] No Markdown files found under docs/, nothing to check.")
        return 0

    issues: List[Issue] = []
    for path in files:
        issues.extend(lint_file(path, autofix=args.fix))

    if args.json:
        import json  # late import to avoid dependency when不需要

        payload = {
            "files": [str(f.relative_to(ROOT)) for f in files],
            "issue_count": len(issues),
            "issues": [
                {
                    "path": str(issue.path.relative_to(ROOT)),
                    "line": issue.line_no,
                    "message": issue.message,
                }
                for issue in issues
            ],
            "fixed": bool(args.fix) and not issues,
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        if issues:
            print("[ERROR] Documentation issues detected:")
            for issue in issues:
                print(f"  - {issue}")
            print(f"[INFO] Run 'bash scripts/code-review.sh -a' or fix manually before committing.")
        else:
            print(f"[SUCCESS] Documentation check passed ({len(files)} files).")

    return 0 if not issues else 1


if __name__ == "__main__":
    sys.exit(main())
