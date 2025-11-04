#!/usr/bin/env python3
"""Restic utility helpers for SaltGoat shell scripts."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import secrets
import string
import subprocess
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Tuple


def cmd_run(cmd: List[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True)


def random_secret(_: argparse.Namespace) -> None:
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*()-_=+"
    print("".join(secrets.choice(alphabet) for _ in range(24)))


def normalize_path(args: argparse.Namespace) -> None:
    value = args.path or ""
    print(os.path.abspath(os.path.expanduser(value)))


def _read_env_file(path: Path) -> Dict[str, str]:
    data: Dict[str, str] = {}
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            data[key.strip()] = value.strip()
    except FileNotFoundError:
        pass
    return data


def _restic_command(repo: str, env_file: str, cmd: str) -> subprocess.CompletedProcess[str]:
    script = (
        f"set -a; source '{env_file}' >/dev/null 2>&1; set +a; "
        f"export RESTIC_REPOSITORY='{repo}'; {cmd}"
    )
    return subprocess.run(["bash", "-lc", script], capture_output=True, text=True)


def summarize_sites(args: argparse.Namespace) -> None:
    metadata_dir = Path(args.metadata_dir)
    files = sorted(metadata_dir.glob("*.env"))
    if not files:
        print("暂无 Restic 站点记录")
        return

    rows = []
    for file in files:
        env = _read_env_file(file)
        site = env.get("SITE") or file.stem
        repo = env.get("REPO")
        env_file = env.get("ENV_FILE", "/etc/restic/restic.env")
        service = env.get("SERVICE_NAME", "saltgoat-restic-backup.service")

        snapshot_count = "0"
        latest_time = "n/a"
        size_display = "n/a"

        if repo and not args.skip_restic:
            snap_proc = _restic_command(repo, env_file, f"{args.restic_bin} --json snapshots")
            if snap_proc.returncode == 0 and snap_proc.stdout.strip():
                try:
                    snapshots = json.loads(snap_proc.stdout)
                    if snapshots:
                        snapshots.sort(key=lambda item: item.get("time", ""))
                        snapshot_count = str(len(snapshots))
                        latest = snapshots[-1].get("time")
                        if latest:
                            try:
                                dt_obj = dt.datetime.fromisoformat(latest.replace("Z", "+00:00"))
                                latest_time = dt_obj.strftime("%Y-%m-%d %H:%M")
                            except Exception:
                                latest_time = latest
                except json.JSONDecodeError:
                    latest_time = "解析失败"
            else:
                latest_time = f"错误({snap_proc.returncode})"

            stats_proc = _restic_command(repo, env_file, f"{args.restic_bin} stats --json latest")
            if stats_proc.returncode == 0 and stats_proc.stdout.strip():
                try:
                    stats = json.loads(stats_proc.stdout)
                    size_bytes = stats.get("total_size", 0)
                    if size_bytes >= 1024**3:
                        size_display = f"{size_bytes / (1024**3):.1f}G"
                    else:
                        size_display = f"{size_bytes / (1024**2):.1f}M"
                except json.JSONDecodeError:
                    size_display = "解析失败"
            elif stats_proc.returncode == 3:
                size_display = "无快照"

        svc_state = "unknown"
        svc_status = ""
        last_run = "n/a"

        svc_proc = cmd_run(
            [
                "systemctl",
                "show",
                service,
                "--property=ActiveState,SubState,ExecMainStatus",
            ]
        )
        if svc_proc.returncode == 0:
            props = dict(line.split("=", 1) for line in svc_proc.stdout.splitlines() if "=" in line)
            svc_state = f"{props.get('ActiveState', '?')}/{props.get('SubState', '?')}"
            svc_status = props.get("ExecMainStatus", "")

        journal_proc = cmd_run(
            ["journalctl", "-u", service, "-n", "1", "--no-pager", "--output=json"]
        )
        if journal_proc.returncode == 0 and journal_proc.stdout.strip():
            try:
                entry = json.loads(journal_proc.stdout.splitlines()[-1])
                ts = int(entry.get("__REALTIME_TIMESTAMP", "0"))
                if ts:
                    dt_obj = dt.datetime.fromtimestamp(ts / 1_000_000)
                    last_run = dt_obj.strftime("%Y-%m-%d %H:%M:%S")
            except Exception:
                pass

        rows.append(
            {
                "site": site,
                "snapshots": snapshot_count,
                "latest": latest_time,
                "size": size_display,
                "svc_state": svc_state,
                "svc_status": svc_status,
                "last_run": last_run,
            }
        )

    header = f"{'站点':<12} {'快照数':<6} {'最后备份':<17} {'容量':<8} {'服务状态':<20} {'最后执行':<19}"
    print(header)
    print("-" * len(header))
    for row in sorted(rows, key=lambda r: r["site"]):
        state = row["svc_state"]
        if row["svc_status"]:
            state = f"{state}({row['svc_status']})"
        print(
            f"{row['site']:<12} {row['snapshots']:<6} {row['latest']:<17} "
            f"{row['size']:<8} {state:<20} {row['last_run']:<19}"
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Restic helper utilities")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("random-secret", help="Generate random restic secret").set_defaults(
        func=random_secret
    )

    norm = sub.add_parser("normalize-path", help="Normalize filesystem path")
    norm.add_argument("path", help="Path to normalize")
    norm.set_defaults(func=normalize_path)

    summarize = sub.add_parser("summarize-sites", help="Summarize restic site metadata")
    summarize.add_argument("--metadata-dir", default="/etc/restic/sites.d")
    summarize.add_argument("--restic-bin", default="/usr/bin/restic")
    summarize.add_argument("--skip-restic", action="store_true")
    summarize.set_defaults(func=summarize_sites)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
