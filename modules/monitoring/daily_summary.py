#!/usr/bin/env python3
"""
SaltGoat daily summary reporter.

Generates a concise system summary, writes it to /var/log/saltgoat/monitor/, and pushes Telegram + Salt events.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import shutil
import socket
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

try:
    from salt.client import Caller  # type: ignore
except Exception:  # pragma: no cover
    Caller = None  # type: ignore

HOSTNAME = socket.getfqdn()
MONITOR_DIR = Path("/var/log/saltgoat/monitor")
ALERT_LOG = Path("/var/log/saltgoat/alerts.log")
LOGGER_SCRIPT = Path("/opt/saltgoat-reactor/logger.py")
TELEGRAM_COMMON = Path("/opt/saltgoat-reactor/reactor_common.py")
REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
from modules.lib import notification as notif  # type: ignore


def path_exists(path: Path) -> bool:
    try:
        path.stat()
        return True
    except (PermissionError, FileNotFoundError):
        return False


TELEGRAM_AVAILABLE = path_exists(LOGGER_SCRIPT) and path_exists(TELEGRAM_COMMON)

if TELEGRAM_AVAILABLE:
    sys.path.insert(0, str(TELEGRAM_COMMON.parent))
    try:
        import reactor_common  # type: ignore
    except Exception:  # pragma: no cover
        TELEGRAM_AVAILABLE = False


def run_cmd(cmd: List[str]) -> str:
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return out.decode().strip()
    except subprocess.CalledProcessError:
        return ""


def safe_float(value: str) -> Optional[float]:
    try:
        return float(value)
    except ValueError:
        return None


def loadavg() -> Tuple[float, float, float]:
    try:
        return os.getloadavg()
    except OSError:
        return (0.0, 0.0, 0.0)


def memory_usage() -> Tuple[float, str]:
    info: Dict[str, int] = {}
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as fh:
            for line in fh:
                if ":" not in line:
                    continue
                k, v = line.split(":", 1)
                value = v.strip().split()[0]
                info[k] = int(value)
    except FileNotFoundError:
        return (0.0, "")

    total = info.get("MemTotal", 0)
    available = info.get("MemAvailable")
    if available is None:
        available = info.get("MemFree", 0) + info.get("Buffers", 0) + info.get("Cached", 0)
    used = total - available
    percent = (used / total * 100.0) if total else 0.0
    summary = f"{used/1024/1024:.1f}G / {total/1024/1024:.1f}G"
    return percent, summary


def disk_summary(paths: Iterable[Path]) -> Dict[str, Tuple[float, str]]:
    result: Dict[str, Tuple[float, str]] = {}
    for path in paths:
        try:
            usage = shutil.disk_usage(path)
        except FileNotFoundError:
            continue
        percent = usage.used / usage.total * 100.0
        summary = f"{usage.used/1024/1024/1024:.1f}G/{usage.total/1024/1024/1024:.1f}G"
        result[str(path)] = (percent, summary)
    return result


def service_status(services: Iterable[str]) -> Dict[str, bool]:
    status: Dict[str, bool] = {}
    for svc in services:
        ok = subprocess.call(
            ["systemctl", "is-active", "--quiet", svc],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ) == 0
        status[svc] = ok
    return status


def _parse_backup_line(meta: str, payload_raw: Optional[str]) -> Optional[Dict[str, Any]]:
    try:
        parts = meta.split()
        if len(parts) < 3:
            return None
        timestamp = " ".join(parts[:2])
        info: Dict[str, Any] = {
            "timestamp": timestamp,
            "raw": meta if payload_raw is None else f"{meta} payload={payload_raw}",
        }
        for token in parts[2:]:
            if token == "[BACKUP]":
                continue
            if "=" in token:
                key, value = token.split("=", 1)
                info[key] = value
        if payload_raw:
            try:
                info["payload"] = json.loads(payload_raw)
            except json.JSONDecodeError:
                info["payload"] = payload_raw
        return info
    except Exception:
        return None


def collect_backup_events(kind: str, key_field: Optional[str] = None, limit: int = 5) -> List[Dict[str, Any]]:
    if not path_exists(ALERT_LOG):
        return []
    tag = f"saltgoat/backup/{kind}/success"
    events: List[Dict[str, Any]] = []
    seen_keys: List[str] = []
    try:
        with open(ALERT_LOG, "r", encoding="utf-8", errors="ignore") as fh:
            lines = fh.readlines()
        needle = f"[BACKUP] tag={tag}"
        for line in reversed(lines):
            stripped = line.strip()
            if " payload=" in stripped:
                meta, payload_raw = stripped.split(" payload=", 1)
            else:
                meta, payload_raw = stripped, None
            if needle not in meta:
                continue
            parsed = _parse_backup_line(meta, payload_raw)
            if not parsed:
                continue
            key_value = None
            if key_field:
                data = parsed.get("payload", {}).get("data", {}) if parsed.get("payload") else {}
                if isinstance(data, dict):
                    key_value = data.get(key_field)
                if key_value is None:
                    key_value = parsed.get(key_field)
            if key_value is not None:
                if key_value in seen_keys:
                    continue
                seen_keys.append(key_value)
            events.append(parsed)
            if key_field:
                if len(seen_keys) >= limit:
                    break
            else:
                if len(events) >= limit:
                    break
    except Exception:
        return events
    return events


def log_to_file(label: str, tag: str, payload: Dict[str, Any]) -> None:
    if not path_exists(LOGGER_SCRIPT):
        return
    try:
        subprocess.run(
            [
                sys.executable,
                str(LOGGER_SCRIPT),
                label,
                str(ALERT_LOG),
                tag,
                json.dumps(payload, ensure_ascii=False),
            ],
            check=False,
            timeout=5,
        )
    except Exception:
        pass


def telegram_notify(tag: str, message: str, payload: Dict[str, Any], plain_message: Optional[str] = None) -> None:
    severity = str(payload.get("severity", "INFO")).upper()
    payload["severity"] = severity
    site_hint = payload.get("site")
    if not notif.should_send(tag, severity, site_hint):
        log_to_file(
            "TELEGRAM",
            f"{tag} skip",
            {"reason": "filtered", "severity": severity, "site": site_hint},
        )
        return

    plain_block = plain_message or message
    notif.dispatch_webhooks(tag, severity, site_hint, plain_block, message, payload)
    if not TELEGRAM_AVAILABLE:
        return

    parse_mode = "MarkdownV2"

    def _log(kind: str, extra: Dict[str, Any]) -> None:
        log_to_file("TELEGRAM", f"{tag} {kind}", extra)

    profiles = reactor_common.load_telegram_profiles(None, _log)
    if not profiles:
        _log("skip", {"reason": "no_profiles"})
        return
    _log("profile_summary", {"count": len(profiles)})
    reactor_common.broadcast_telegram(message, profiles, _log, tag=tag, parse_mode=parse_mode)


def emit_event(tag: str, payload: Dict[str, Any]) -> None:
    if Caller is None:
        return
    try:
        caller = Caller()  # type: ignore[call-arg]
        caller.cmd("event.send", tag, payload)
    except Exception:
        pass


def compile_summary() -> Tuple[str, str, Dict[str, Any]]:
    cpu_cores = os.cpu_count() or 1
    load1, load5, load15 = loadavg()
    mem_percent, mem_summary = memory_usage()
    disks = disk_summary([Path("/"), Path("/var/lib/mysql"), Path("/home")])
    services = service_status(["nginx", "php8.3-fpm", "mysql", "valkey", "rabbitmq", "salt-minion"])

    restic_events = collect_backup_events("restic", key_field="repo", limit=5)
    dump_events = collect_backup_events("mysql_dump", key_field="site", limit=10)

    generated_at = dt.datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

    plain_lines = [
        f"[SaltGoat] Daily Summary - {HOSTNAME}",
        f"Date: {generated_at}",
        f"Load avg: {load1:.2f} {load5:.2f} {load15:.2f} (cores={cpu_cores})",
        f"Memory: {mem_percent:.1f}% used ({mem_summary})",
    ]

    if disks:
        plain_lines.append("Disks:")
        for mount, (percent, summary) in disks.items():
            pretty_summary = summary.replace("/", " / ")
            plain_lines.append(f"  - {mount}: {percent:.1f}% ({pretty_summary})")

    failing = [svc for svc, ok in services.items() if not ok]
    if failing:
        plain_lines.append("Services: ⚠️ " + ", ".join(failing) + " down")
    else:
        plain_lines.append("Services: all running")

    if restic_events:
        plain_lines.append("Restic backups:")
        for event in restic_events:
            data = event.get("payload", {}).get("data", {}) if event.get("payload") else {}
            repo = data.get("repo")
            details = []
            if repo:
                details.append(f"repo={repo}")
            detail_str = f" {' '.join(details)}" if details else ""
            plain_lines.append(f"  - {event.get('timestamp', '')}{detail_str}")
    if dump_events:
        plain_lines.append("MySQL dumps:")
        for event in dump_events:
            data = event.get("payload", {}).get("data", {}) if event.get("payload") else {}
            site = data.get("site")
            size = data.get("size")
            path = data.get("path")
            details = []
            if site:
                details.append(f"site={site}")
            if size:
                details.append(f"size={size}")
            if path:
                details.append(f"path={path}")
            detail_str = f" {' '.join(details)}" if details else ""
            plain_lines.append(f"  - {event.get('timestamp', '')}{detail_str}")

    md_lines: List[str] = [
        "*SaltGoat ▸ Daily Summary*",
        f"*Host:* {notif.format_markdown_code(HOSTNAME)}",
        f"*Date:* {notif.format_markdown_code(generated_at)}",
        "",
        f"*Load:* {notif.format_markdown_code(f'{load1:.2f} {load5:.2f} {load15:.2f}')} {notif.escape_markdown_v2(f'(cores={cpu_cores})')}",
        f"*Memory:* {notif.format_markdown_code(f'{mem_percent:.1f}%')} used → {notif.format_markdown_code(mem_summary)}",
    ]

    if disks:
        disk_rows: List[str] = []
        for mount, (percent, summary) in disks.items():
            pretty_summary = summary.replace("/", " / ")
            disk_rows.append(f"{mount:<15} {percent:.1f}%  ({pretty_summary})")
        md_lines.append("")
        md_lines.append("*Disks:*")
        md_lines.append(notif.format_markdown_code_block(disk_rows))

    if failing:
        md_lines.append("")
        md_lines.append(f"*Services:* {notif.escape_markdown_v2(', '.join(failing) + ' down')}")
    else:
        md_lines.append("")
        md_lines.append(f"*Services:* {notif.escape_markdown_v2('all running')}")

    backup_md_lines: List[str] = []
    if restic_events:
        for event in restic_events:
            data = event.get("payload", {}).get("data", {}) if event.get("payload") else {}
            timestamp_md = notif.format_markdown_code(event.get("timestamp", ""))
            repo_md = notif.format_markdown_code(data.get("repo", "")) if data.get("repo") else None
            detail = f" → repo={repo_md}" if repo_md else ""
            backup_md_lines.append(f"• Restic {timestamp_md}{detail}")
    if dump_events:
        for event in dump_events:
            data = event.get("payload", {}).get("data", {}) if event.get("payload") else {}
            timestamp_md = notif.format_markdown_code(event.get("timestamp", ""))
            parts = []
            site = data.get("site")
            size = data.get("size")
            path = data.get("path")
            if site:
                parts.append(f"site={notif.format_markdown_code(site)}")
            if size:
                parts.append(f"size={notif.format_markdown_code(size)}")
            if path:
                parts.append(f"path={notif.format_markdown_code(path)}")
            detail = f" → {' | '.join(parts)}" if parts else ""
            backup_md_lines.append(f"• MySQL Dump {timestamp_md}{detail}")
    if backup_md_lines:
        md_lines.append("")
        md_lines.append("*Backups*")
        md_lines.extend(backup_md_lines)

    payload = {
        "host": HOSTNAME,
        "load": {"1m": load1, "5m": load5, "15m": load15},
        "cpu_cores": cpu_cores,
        "memory": {"percent": mem_percent, "summary": mem_summary},
        "disks": disks,
        "services": services,
        "restic_reference": restic_events,
        "mysqldump_reference": dump_events,
    }
    plain_text = "\n".join(plain_lines)
    markdown_text = "\n".join(md_lines)
    return plain_text, markdown_text, payload


def ensure_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def write_report(text: str, filename: Optional[str]) -> Optional[Path]:
    if not filename:
        return None
    ensure_directory(MONITOR_DIR)
    target = MONITOR_DIR / filename
    target.write_text(text, encoding="utf-8")
    return target


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="SaltGoat daily summary")
    parser.add_argument(
        "--outfile",
        help="写入报告文件名（默认 daily-YYYYMMDD.txt）",
        default=f"daily-{dt.datetime.utcnow().strftime('%Y%m%d')}.txt",
    )
    parser.add_argument(
        "--no-telegram",
        action="store_true",
        help="仅生成报告，不发送 Telegram",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="不在控制台打印总结",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    summary_plain, summary_markdown, payload = compile_summary()
    write_report(summary_plain, args.outfile)
    tag = "saltgoat/monitor/daily"
    payload_with_tag = payload | {"tag": tag}
    log_to_file("REPORT", tag, payload_with_tag)
    emit_event(tag, payload)
    if not args.no_telegram:
        payload_with_tag.setdefault("severity", "INFO")
        thread_id = payload_with_tag.get("telegram_thread") or notif.get_thread_id(tag)
        if thread_id is not None:
            payload_with_tag["telegram_thread"] = thread_id
        try:
            telegram_notify(tag, summary_markdown, payload_with_tag, summary_plain)
        except Exception as exc:
            notif.queue_failure(
                "telegram",
                tag,
                payload_with_tag | {"message": summary_markdown},
                str(exc),
                {
                    "thread": payload_with_tag.get("telegram_thread"),
                    "parse_mode": "MarkdownV2",
                    "plain": summary_plain,
                },
            )
    if not args.quiet:
        print(summary_plain)


if __name__ == "__main__":
    main()
