#!/usr/bin/env python3
"""ASCII ops dashboard showing SaltGoat host pulse."""

from __future__ import annotations

import argparse
import contextlib
import html
import io
import json
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Any

DEFAULT_TELEGRAM_CONFIG = Path("/etc/saltgoat/telegram.json")
REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from modules.lib import minio_helper  # type: ignore  # noqa: E402

SERVICES = [
    ("nginx", "nginx"),
    ("php8.3-fpm", "php8.3-fpm"),
    ("varnish", "varnish"),
    ("mysql", "mysql"),
    ("rabbitmq", "rabbitmq"),
    ("valkey", "valkey"),
    ("opensearch", "opensearch"),
    ("salt-minion", "salt-minion"),
    ("minio", "minio"),
]
SITES = ["bank", "tank", "pwas"]
PILLAR_NGINX = Path("salt/pillar/nginx.sls")
FAIL2BAN_STATE = Path("/var/log/saltgoat/fail2ban-state.json")
PILLAR_MINIO = REPO_ROOT / "salt" / "pillar" / "minio.sls"


def run(cmd: List[str], timeout: int = 10) -> Tuple[int, str, str]:
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"


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


def gather_minio_health() -> Dict[str, Any]:
    try:
        cfg = minio_helper.load_enabled_config(PILLAR_MINIO)
    except Exception:
        cfg = None
    if cfg is None:
        return {"enabled": False}
    url = cfg.health_url
    timeout = max(1.0, float(cfg.health_timeout))
    headers = {"User-Agent": "GoatPulse/1.0"}
    req = urllib.request.Request(url, headers=headers)
    context = None
    if cfg.health_scheme.lower().startswith("https"):
        context = ssl.create_default_context() if cfg.health_verify else ssl._create_unverified_context()
    start = time.time()
    info: Dict[str, Any] = {
        "enabled": True,
        "url": url,
        "service": cfg.service_name,
    }
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=context) as resp:
            latency = time.time() - start
            status = resp.getcode()
            info.update({"status": status, "latency": round(latency, 3), "ok": status == 200, "message": f"HTTP {status}"})
            return info
    except urllib.error.HTTPError as exc:
        latency = time.time() - start
        info.update({"status": exc.code, "latency": round(latency, 3), "ok": False, "message": f"HTTP {exc.code}"})
        return info
    except Exception as exc:
        latency = time.time() - start
        info.update({"status": None, "latency": round(latency, 3), "ok": False, "message": str(exc)})
        return info


def print_minio(info: Dict[str, Any]) -> None:
    print("MinIO Health")
    print("-" * 50)
    if not info.get("enabled", True):
        print("Status: disabled or pillar missing")
    else:
        status = "OK" if info.get("ok") else "FAIL"
        msg = info.get("message", "")
        latency = info.get("latency")
        latency_text = f"{latency:.3f}s" if isinstance(latency, (int, float)) else "-"
        print(f"Status : {status} ({msg})")
        print(f"Latency: {latency_text}")
        print(f"URL    : {info.get('url', '-')}")
    print()


def clear_screen() -> None:
    print("\033[2J\033[H", end="")


def gather_services() -> List[Dict[str, str]]:
    records = []
    for label, unit in SERVICES:
        state, enabled = service_status(unit)
        records.append({"label": label, "unit": unit, "state": state, "enabled": enabled})
    return records


def print_services(data: List[Dict[str, str]]) -> None:
    print("Service Status")
    print("-" * 50)
    print(f"{'Service':<20} {'State':<10} {'Enabled'}")
    for item in data:
        print(f"{item['label']:<20} {item['state']:<10} {item['enabled']}")
    print()


def gather_sites() -> List[Dict[str, Any]]:
    info = []
    for site in SITES:
        url = site_target(site)
        status, duration, varnish = http_probe(url)
        info.append({"site": site, "status": status, "duration": duration, "varnish": varnish})
    return info


def print_sites(data: List[Dict[str, Any]]) -> None:
    print("Storefront Probes")
    print("-" * 50)
    print(f"{'Site':<8} {'HTTP':<6} {'Time':<8} {'Via'}")
    for entry in data:
        status = entry["status"]
        duration = entry["duration"]
        varnish = entry["varnish"]
        via = "Varnish" if varnish else "Origin"
        duration_ms = f"{duration:.2f}s" if duration else "-"
        print(f"{entry['site']:<8} {status:<6} {duration_ms:<8} {via}")
    print()


def print_varnish(stats: Tuple[int, int, float]) -> None:
    hits, miss, ratio = stats
    print("Varnish Cache")
    print("-" * 50)
    print(f"HIT: {hits}  MISS: {miss}  HIT RATIO: {ratio:.1f}%")
    print()


def print_fail2ban(summary: Tuple[int, Dict[str, List[str]]]) -> None:
    current, data = summary
    print("Fail2ban Summary")
    print("-" * 50)
    print(f"Currently banned IPs: {current}")
    for jail, ips in data.items():
        if not isinstance(ips, list):
            continue
        sample = ", ".join(ips[:5]) if ips else "-"
        print(f"{jail:<18}: {len(ips):<4} {sample}")
    print()


def write_metrics(path: Path, services: List[Dict[str, str]], sites: List[Dict[str, Any]], varnish_data: Tuple[int, int, float], fail2ban_total: int, minio_info: Dict[str, Any]) -> None:
    try:
        lines = []
        for item in services:
            active = 1 if item["state"] == "active" else 0
            enabled = 1 if item["enabled"] == "enabled" else 0
            svc = item["label"]
            lines.append(f'saltgoat_service_active{{service="{svc}"}} {active}')
            lines.append(f'saltgoat_service_enabled{{service="{svc}"}} {enabled}')
        for entry in sites:
            status_raw = entry["status"]
            try:
                status_val = int(status_raw)
            except ValueError:
                status_val = -1
            duration = entry["duration"] or 0.0
            varnish = 1 if entry["varnish"] else 0
            lines.append(f'saltgoat_site_http_status{{site="{entry["site"]}"}} {status_val}')
            lines.append(f'saltgoat_site_http_duration_seconds{{site="{entry["site"]}"}} {duration:.3f}')
            lines.append(f'saltgoat_site_varnish{{site="{entry["site"]}"}} {varnish}')
        hits, miss, ratio = varnish_data
        lines.append(f"saltgoat_varnish_hits {hits}")
        lines.append(f"saltgoat_varnish_miss {miss}")
        lines.append(f"saltgoat_varnish_hit_ratio_percent {ratio:.2f}")
        lines.append(f"saltgoat_fail2ban_banned_total {fail2ban_total}")
        if minio_info.get("enabled"):
            status = 1 if minio_info.get("ok") else 0
            latency = float(minio_info.get("latency") or 0)
            lines.append(f"saltgoat_minio_health {status}")
            lines.append(f"saltgoat_minio_health_latency_seconds {latency:.3f}")
        else:
            lines.append("saltgoat_minio_health -1")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    except Exception as exc:
        print(f"[WARN] Failed to write metrics file {path}: {exc}", file=sys.stderr)


def loop(
    interval: int,
    once: bool,
    metrics_file: Optional[Path],
    plain: bool,
    capture: Optional[List[str]] = None,
) -> None:
    while True:
        block = []
        header = f"Goat Pulse @ {datetime.utcnow():%Y-%m-%d %H:%M:%S UTC}"
        block.append(header)
        block.append("=" * 50)
        if not plain:
            clear_screen()
        print(header)
        print("=" * 50)
        captured_output = ""
        try:
            services = gather_services()
            sites = gather_sites()
            varnish_data = varnish_stats()
            fail2ban_data = fail2ban_summary()
            minio_info = gather_minio_health()
            if capture is not None:
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    print_services(services)
                    print_sites(sites)
                    print_varnish(varnish_data)
                    print_fail2ban(fail2ban_data)
                    print_minio(minio_info)
                captured_output = buf.getvalue()
                print(captured_output, end="")
            else:
                print_services(services)
                print_sites(sites)
                print_varnish(varnish_data)
                print_fail2ban(fail2ban_data)
                print_minio(minio_info)
            if metrics_file:
                write_metrics(metrics_file, services, sites, varnish_data, fail2ban_data[0], minio_info)
        except KeyboardInterrupt:
            break
        if capture is not None:
            if captured_output:
                block.append(captured_output.rstrip("\n"))
            capture.append("\n".join(block))
        if once:
            break
        time.sleep(interval)


def main() -> None:
    parser = argparse.ArgumentParser(description="SaltGoat ASCII ops dashboard")
    parser.add_argument("-i", "--interval", type=int, default=5, help="refresh interval seconds")
    parser.add_argument("--once", action="store_true", help="render once and exit")
    parser.add_argument("--telegram", action="store_true", help="send single snapshot to Telegram General")
    parser.add_argument("--metrics-file", type=Path, help="Write Prometheus textfile metrics to path")
    parser.add_argument("--plain", action="store_true", help="Disable ANSI clear for embedding / doctor")
    parser.add_argument("--telegram-config", default=str(DEFAULT_TELEGRAM_CONFIG), help="telegram config path")
    args = parser.parse_args()
    metrics_path = Path(args.metrics_file) if args.metrics_file else None
    if args.telegram:
        capture: List[str] = []
        loop(1, True, metrics_path, args.plain, capture)
        body = "\n".join(capture)
        send_telegram(body, Path(args.telegram_config))
        return
    loop(max(1, args.interval), args.once, metrics_path, args.plain)


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
    escaped = html.escape(text)
    payload = {
        "chat_id": chat_id,
        "text": f"<b>[INFO] Goat Pulse Digest</b>\n<pre>{escaped}</pre>",
        "disable_web_page_preview": True,
        "parse_mode": "HTML",
    }
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
