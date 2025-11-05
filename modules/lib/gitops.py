#!/usr/bin/env python3
"""Utilities for detecting GitOps configuration drift."""

from __future__ import annotations

import argparse
import os
import subprocess
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable, List, Optional

REPO_ROOT = Path(__file__).resolve().parents[2]
UNIT_TEST = os.environ.get("SALTGOAT_UNIT_TEST") == "1"


class GitError(RuntimeError):
    """Raised when underlying git command fails."""


def _run_git(args: List[str], cwd: Optional[Path] = None) -> str:
    cmd = ["git"] + args
    proc = subprocess.run(
        cmd,
        cwd=cwd or REPO_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise GitError(proc.stderr.strip() or proc.stdout.strip() or f"git {' '.join(args)} failed")
    return proc.stdout.strip()


@dataclass
class DriftReport:
    branch: str
    upstream: Optional[str]
    ahead: int
    behind: int
    working_changes: List[str]
    untracked: List[str]

    @property
    def has_drift(self) -> bool:
        return bool(self.ahead or self.behind or self.working_changes or self.untracked)


def detect_drift(remote: str = "origin") -> DriftReport:
    branch = _run_git(["rev-parse", "--abbrev-ref", "HEAD"])
    upstream = None
    try:
        upstream = _run_git(["rev-parse", "--abbrev-ref", f"{branch}@{{upstream}}"])
    except GitError:
        candidate = f"{remote}/{branch}"
        try:
            _run_git(["rev-parse", "--verify", candidate])
            upstream = candidate
        except GitError:
            upstream = None

    ahead = behind = 0
    if upstream:
        # Count commits diverged from upstream
        counts = _run_git(["rev-list", "--left-right", "--count", f"{branch}...{upstream}"])
        parts = counts.split()
        if len(parts) == 2:
            ahead = int(parts[0])
            behind = int(parts[1])

    status = _run_git(["status", "--short"])
    working_changes = []
    untracked = []
    if status:
        for line in status.splitlines():
            if line.startswith("??"):
                untracked.append(line[3:])
            else:
                working_changes.append(line.strip())

    return DriftReport(
        branch=branch,
        upstream=upstream,
        ahead=ahead,
        behind=behind,
        working_changes=working_changes,
        untracked=untracked,
    )


def format_text(report: DriftReport) -> str:
    lines = [
        f"Branch: {report.branch}",
        f"Upstream: {report.upstream or 'none'}",
        f"Ahead: {report.ahead}",
        f"Behind: {report.behind}",
    ]
    if report.working_changes:
        lines.append("Working tree changes:")
        lines.extend(f"  {entry}" for entry in report.working_changes)
    if report.untracked:
        lines.append("Untracked files:")
        lines.extend(f"  {entry}" for entry in report.untracked)
    if not report.has_drift:
        lines.append("No configuration drift detected.")
    return "\n".join(lines)


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="SaltGoat GitOps drift detector")
    parser.add_argument("--remote", default="origin", help="Git remote to compare against")
    parser.add_argument("--format", choices=["text", "json"], default="text")
    parser.add_argument("--allow-dirty", action="store_true", help="Return 0 even if drift detected")
    args = parser.parse_args(list(argv) if argv is not None else None)

    try:
        report = detect_drift(remote=args.remote)
    except GitError as exc:
        parser.error(str(exc))
        return 2

    if args.format == "json":
        import json

        print(json.dumps(asdict(report), ensure_ascii=False, indent=2))
    else:
        print(format_text(report))

    if report.has_drift and not args.allow_dirty:
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
