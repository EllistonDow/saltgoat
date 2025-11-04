#!/usr/bin/env python3
"""ASCII ops dashboard showing SaltGoat host pulse."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple, Optional

DEFAULT_TELEGRAM_CONFIG = Path("/etc/saltgoat/telegram.json")
SERVICES = [
    ("nginx", "nginx"),
    ("php8.3-fpm", "php8.3-fpm"),
    ("varnish", "varnish"),
    ("mysql", "mysql"),
    ("rabbitmq", "rabbitmq"),
    ("valkey", "valkey"),
    ("opensearch", "opensearch"),
    ("salt-minion", "salt-minion"),
]
SITES = ["bank", "tank", "pwas"]
PILLAR_NGINX = Path("salt/pillar/nginx.sls")
FAIL2BAN_STATE = Path("/var/log/saltgoat/fail2ban-state.json")


def run(cmd: List[str], timeout: int = 10) -> Tuple[int, str, str]:
    proc = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def service_status(unit: str) -> Tuple[str, str]:
    code, _, _ = run(["systemctl", "is-active", unit])
    state = "active" if code == 0 else "inactive"
    code_enabled, _, _ = run(["systemctl", "is-enabled", unit])
    enabled = "enabled" if code_enabled == 0 else "disabled"
    return state, enabled


def site_target(site: str) -> str:
    if PILLAR_NGINX.exists():
        try:
            import yaml  # type: ignore

            data = yaml.safe_load(PILLAR_NGINX.read_text(encoding="utf-8")) or {}
            entry = ((data.get("nginx") or {}).get("sites") or {}).get(site, {})
            names = entry.get("server_name")
            if isinstance(names, list) and names:
                return f"https://{names[0]}"
            if isinstance(names, str) and names.strip():
                return f"https://{names.strip()}"
        except Exception:
            pass
    return f"https://{site}.magento.tattoogoat.com"


def http_probe(url: str) -> Tuple[str, float, bool]:
    cmd = [
        "curl",
        "-sS",
        "-o",
        "/tmp/goat-pulse.tmp",
        "-D",
        "-",
        "-w",
        "%{http_code} %{time_total}",
        "-H",
        "Cache-Control: no-cache",
        "--max-time",
        "10",
        "--retry",
        "1",
        url,
    ]
    code, stdout, _ = run(cmd)
    if code != 0 or not stdout:
        return "ERR", 0.0, False
    lines = stdout.splitlines()
    metrics = lines[-1].split() if lines else []
    headers = "\n".join(lines[:-1])
    status = metrics[0] if metrics else "000"
    duration = float(metrics[1]) if len(metrics) > 1 else 0.0
    varnish = "X-Varnish" in headers
    try:
        Path("/tmp/goat-pulse.tmp").unlink(missing_ok=True)  # type: ignore[arg-type]
    except Exception:
        pass
    return status, duration, varnish


def varnish_stats() -> Tuple[int, int, float]:
    code, stdout, _ = run(["varnishstat", "-1", "-f", "MAIN.cache_hit,MAIN.cache_miss"])
    hits = miss = 0
    if code == 0:
        for line in stdout.splitlines():
            parts = line.split()
            if len(parts) >= 2:
                if "cache_hit" in parts[0]:
                    hits = int(float(parts[1]))
                elif "cache_miss" in parts[0]:
                    miss = int(float(parts[1]))
    ratio = hits / (hits + miss) * 100 if hits + miss else 0.0
    return hits, miss, ratio


def fail2ban_summary() -> Tuple[int, Dict[str, List[str]]]:
    try:
        if not FAIL2BAN_STATE.exists():
            return 0, {}
        data = json.loads(FAIL2BAN_STATE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, PermissionError):
        return 0, {}
    currently = sum(len(ips) for ips in data.values() if isinstance(ips, list))
    return currently, data


def clear_screen() -> None:
    print("\033[2J\033[H", end="")


def print_services() -> None:
    print("Service Status")
    print("-" * 50)
    print(f"{'Service':<20} {'State':<10} {'Enabled'}")
    for label, unit in SERVICES:
        state, enabled = service_status(unit)
        print(f"{label:<20} {state:<10} {enabled}")
    print()


def print_sites() -> None:
    print("Storefront Probes")
    print("-" * 50)
    print(f"{'Site':<8} {'HTTP':<6} {'Time':<8} {'Via'}")
    for site in SITES:
        url = site_target(site)
        status, duration, varnish = http_probe(url)
        via = "Varnish" if varnish else "Origin"
        duration_ms = f"{duration:.2f}s" if duration else "-"
        print(f"{site:<8} {status:<6} {duration_ms:<8} {via}")
    print()


def print_varnish() -> None:
    hits, miss, ratio = varnish_stats()
    print("Varnish Cache")
    print("-" * 50)
    print(f"HIT: {hits}  MISS: {miss}  HIT RATIO: {ratio:.1f}%")
    print()


def print_fail2ban() -> None:
    current, data = fail2ban_summary()
    print("Fail2ban Summary")
    print("-" * 50)
    print(f"Currently banned IPs: {current}")
    for jail, ips in data.items():
        if not isinstance(ips, list):
            continue
        sample = ", ".join(ips[:5]) if ips else "-"
        print(f"{jail:<18}: {len(ips):<4} {sample}")
    print()


def loop(interval: int, once: bool, capture: Optional[List[str]] = None) -> None:
    while True:
        block = []
        header = f"Goat Pulse @ {datetime.utcnow():%Y-%m-%d %H:%M:%S UTC}"
        block.append(header)
        block.append("=" * 50)
        clear_screen()
        print(header)
        print("=" * 50)
        try:
            for printer in (print_services, print_sites, print_varnish, print_fail2ban):
                printer()
        except KeyboardInterrupt:
            break
        if capture is not None:
            capture.append(header)
        if once:
            break
        time.sleep(interval)


def main() -> None:
    parser = argparse.ArgumentParser(description="SaltGoat ASCII ops dashboard")
    parser.add_argument("-i", "--interval", type=int, default=5, help="refresh interval seconds")
    parser.add_argument("--once", action="store_true", help="render once and exit")
    parser.add_argument("--telegram", action="store_true", help="send single snapshot to Telegram General")
    parser.add_argument("--telegram-config", default=str(DEFAULT_TELEGRAM_CONFIG), help="telegram config path")
    args = parser.parse_args()
    if args.telegram:
        capture: List[str] = []
        loop(1, True, capture)
        body = "\n".join(capture)
        send_telegram(body, Path(args.telegram_config))
        print(body)
        return
    loop(max(1, args.interval), args.once)


def send_telegram(text: str, config_path: Path) -> None:
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
    except Exception:
        return
    entries = config.get("entries") if isinstance(config, dict) else None
    if not entries:
        return
    entry = entries[0]
    if not isinstance(entry, dict):
        return
    token = entry.get("token")
    targets = entry.get("targets") or []
    chat_id = None
    for target in targets:
        if isinstance(target, dict) and str(target.get("chat_id", "")).startswith("-100"):
            chat_id = str(target["chat_id"])
            break
    if chat_id is None:
        for target in targets:
            if isinstance(target, dict) and target.get("chat_id"):
                chat_id = str(target["chat_id"])
                break
    if not token or not chat_id:
        return
    payload = {"chat_id": chat_id, "text": f"[INFO] Goat Pulse Digest\n{text}", "disable_web_page_preview": True}
    import urllib.parse
    import urllib.request

    try:
        encoded = urllib.parse.urlencode(payload).encode()
        url = f"https://api.telegram.org/bot{token}/sendMessage"
        urllib.request.urlopen(url, data=encoded, timeout=10)
    except Exception:
        pass


if __name__ == "__main__":
    main()
