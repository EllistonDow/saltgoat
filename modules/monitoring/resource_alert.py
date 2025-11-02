#!/usr/bin/env python3
"""
SaltGoat resource alert helper.

Evaluates load/memory/disk/service health and pushes Telegram + Salt events when thresholds are exceeded.
"""

from __future__ import annotations

import json
import html
import math
import os
import re
import shutil
import socket
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from argparse import ArgumentParser
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple
from datetime import datetime, timezone

try:
    from salt.client import Caller  # type: ignore
except Exception:  # pragma: no cover - salt 不存在时回退纯本地模式
    Caller = None  # type: ignore

HOSTNAME = socket.getfqdn()
ALERT_LOG = Path("/var/log/saltgoat/alerts.log")
LOGGER_SCRIPT = Path("/opt/saltgoat-reactor/logger.py")
TELEGRAM_COMMON = Path("/opt/saltgoat-reactor/reactor_common.py")
TELEGRAM_CONFIG = Path("/etc/saltgoat/telegram.json")
PHP_FPM_CONFIG = Path("/etc/php/8.3/fpm/pool.d/www.conf")
PHP_FPM_POOL_DIR = PHP_FPM_CONFIG.parent
DEFAULT_THRESHOLDS = {
    "memory": {"notice": 78.0, "warning": 85.0, "critical": 92.0},
    "disk": {"notice": 80.0, "warning": 90.0, "critical": 95.0},
}
FPM_NOTICE_RATIO = 0.8
FPM_WARNING_RATIO = 0.9
MYSQL_NOTICE_RATIO = 0.8
MYSQL_WARNING_RATIO = 0.9
MYSQL_CRITICAL_RATIO = 0.95
VALKEY_WARNING_RATIO = 0.85
VALKEY_CRITICAL_RATIO = 0.93

RUNTIME_DIR = Path("/etc/saltgoat/runtime")
PHP_AUTOSCALE_FILE = RUNTIME_DIR / "php-fpm-pools.json"
MYSQL_AUTOSCALE_FILE = RUNTIME_DIR / "mysql-autotune.json"
VALKEY_AUTOSCALE_FILE = RUNTIME_DIR / "valkey-autotune.json"
VALKEY_CONFIG = Path("/etc/valkey/valkey.conf")

AUTOSCALE_MIN_INTERVAL = 300  # seconds
PHP_AUTOSCALE_MAX = 240
PHP_AUTOSCALE_STEP_RATIO = 0.25
PHP_AUTOSCALE_MIN_STEP = 2
MYSQL_AUTOSCALE_MAX = 800
MYSQL_AUTOSCALE_STEP_RATIO = 0.2
MYSQL_AUTOSCALE_MIN_STEP = 20
VALKEY_AUTOSCALE_STEP_RATIO = 0.2
VALKEY_AUTOSCALE_MIN_STEP_MB = 256
VALKEY_AUTOSCALE_MAX_RATIO = 0.75
SERVICE_HEAL_COOLDOWN = 300
RECENT_IDS_LIMIT = 200

_SERVICE_CACHE: Dict[str, bool] = {}


def shell_exists(path: Path) -> bool:
    try:
        path.stat()
        return True
    except PermissionError:
        return False
    except FileNotFoundError:
        return False


TELEGRAM_AVAILABLE = (
    shell_exists(LOGGER_SCRIPT)
    and shell_exists(TELEGRAM_COMMON)
    and shell_exists(TELEGRAM_CONFIG)
)

if TELEGRAM_AVAILABLE:
    sys.path.insert(0, str(TELEGRAM_COMMON.parent))
    try:
        import reactor_common  # type: ignore
    except Exception:  # pragma: no cover
        TELEGRAM_AVAILABLE = False


def run_cmd(args: List[str]) -> str:
    try:
        out = subprocess.check_output(args, stderr=subprocess.DEVNULL)
        return out.decode().strip()
    except subprocess.CalledProcessError:
        return ""


def get_load() -> Tuple[float, float, float]:
    try:
        return os.getloadavg()
    except OSError:
        return (0.0, 0.0, 0.0)


def read_meminfo() -> Dict[str, int]:
    result: Dict[str, int] = {}
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as fh:
            for line in fh:
                if ":" not in line:
                    continue
                key, value = line.split(":", 1)
                value = value.strip().split()[0]
                try:
                    result[key] = int(value)
                except ValueError:
                    continue
    except FileNotFoundError:
        pass
    return result


def memory_usage_percent() -> float:
    info = read_meminfo()
    mem_total = info.get("MemTotal")
    if not mem_total:
        return 0.0
    mem_available = info.get("MemAvailable")
    if mem_available is None:
        mem_free = info.get("MemFree", 0)
        buffers = info.get("Buffers", 0)
        cached = info.get("Cached", 0)
        mem_available = mem_free + buffers + cached
    used = mem_total - mem_available
    return (used / mem_total) * 100.0


def disk_usage(paths: Iterable[Path]) -> Dict[str, float]:
    stats: Dict[str, float] = {}
    for path in paths:
        try:
            usage = shutil.disk_usage(path)
            percent = usage.used / usage.total * 100.0
            stats[str(path)] = percent
        except FileNotFoundError:
            continue
    return stats


def service_exists(name: str) -> bool:
    if name in _SERVICE_CACHE:
        return _SERVICE_CACHE[name]
    try:
        proc = subprocess.run(
            ["systemctl", "show", f"{name}.service", "--property", "LoadState"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        exists = proc.returncode == 0 and "not-found" not in proc.stdout
    except FileNotFoundError:
        exists = False
    _SERVICE_CACHE[name] = exists
    return exists


def service_status(services: Iterable[str]) -> Dict[str, bool]:
    result: Dict[str, bool] = {}
    for svc in services:
        if not service_exists(svc):
            continue
        try:
            proc = subprocess.run(
                ["systemctl", "is-active", "--quiet", svc],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            )
            if proc.returncode == 4 and proc.stderr and "could not be found" in proc.stderr.lower():
                continue
            result[svc] = proc.returncode == 0
        except FileNotFoundError:
            continue
    return result


def ensure_runtime_dir() -> None:
    try:
        RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    except PermissionError:
        pass


def load_runtime_json(path: Path) -> Dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError:
        return {}


def save_runtime_json(path: Path, data: Dict[str, Any]) -> None:
    ensure_runtime_dir()
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    tmp_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp_path.replace(path)


def runtime_meta_scope(data: Dict[str, Any], scope: str) -> Dict[str, Any]:
    meta: Dict[str, Any]
    meta_obj = data.get("__meta__")
    if isinstance(meta_obj, dict):
        meta = meta_obj
    else:
        meta = {}
        data["__meta__"] = meta
    scope_meta = meta.get(scope)
    if not isinstance(scope_meta, dict):
        scope_meta = {}
        meta[scope] = scope_meta
    return scope_meta


def recently_scaled(meta: Dict[str, Any], min_interval: int = AUTOSCALE_MIN_INTERVAL) -> bool:
    last = meta.get("last_scaled_at")
    if isinstance(last, (int, float)):
        if time.time() - last < min_interval:
            return True
    return False


def php_fpm_pool_configs(pool_dir: Path = PHP_FPM_POOL_DIR) -> Dict[str, Dict[str, Any]]:
    configs: Dict[str, Dict[str, Any]] = {}
    if not shell_exists(pool_dir):
        return configs
    for conf_path in sorted(pool_dir.glob("*.conf")):
        try:
            with conf_path.open("r", encoding="utf-8") as fh:
                current_pool: Optional[str] = None
                pool_data: Dict[str, Any] = {}
                for raw_line in fh:
                    line = raw_line.strip()
                    if not line or line.startswith(("#", ";")):
                        continue
                    if line.startswith("[") and line.endswith("]"):
                        if current_pool and pool_data:
                            pool_data["path"] = str(conf_path)
                            configs[current_pool] = pool_data
                        current_pool = line[1:-1].strip() or conf_path.stem
                        pool_data = {}
                        continue
                    if "=" not in line:
                        continue
                    key, value = [segment.strip() for segment in line.split("=", 1)]
                    if key == "pm.max_children":
                        try:
                            pool_data["max_children"] = int(value)
                        except ValueError:
                            continue
                    elif key == "pm":
                        pool_data["pm"] = value
                    elif key == "listen":
                        pool_data["listen"] = value
                    elif key.startswith("php_admin_value[") and key.endswith("]"):
                        inner = key[len("php_admin_value[") : -1]
                        admin = pool_data.setdefault("php_admin_value", {})
                        admin[inner] = value
                    elif key.startswith("php_value[") and key.endswith("]"):
                        inner = key[len("php_value[") : -1]
                        php_values = pool_data.setdefault("php_value", {})
                        php_values[inner] = value
                if current_pool:
                    pool_data["path"] = str(conf_path)
                    configs[current_pool] = pool_data
        except (OSError, ValueError):
            continue
    if not configs and shell_exists(PHP_FPM_CONFIG):
        # fallback 单池场景
        max_children = php_fpm_pool_configs_from_file(PHP_FPM_CONFIG)
        if max_children:
            configs = max_children
    return configs


def php_fpm_pool_configs_from_file(path: Path) -> Dict[str, Dict[str, Any]]:
    try:
        with path.open("r", encoding="utf-8") as fh:
            data: Dict[str, Any] = {}
            pool_name = path.stem
            for raw_line in fh:
                line = raw_line.strip()
                if not line or line.startswith(("#", ";")):
                    continue
                if line.startswith("[") and line.endswith("]"):
                    pool_name = line[1:-1].strip() or pool_name
                    continue
                if "=" not in line:
                    continue
                key, value = [segment.strip() for segment in line.split("=", 1)]
                if key == "pm.max_children":
                    try:
                        data["max_children"] = int(value)
                    except ValueError:
                        continue
                elif key == "pm":
                    data["pm"] = value
                elif key == "listen":
                    data["listen"] = value
                elif key.startswith("php_admin_value[") and key.endswith("]"):
                    inner = key[len("php_admin_value[") : -1]
                    admin = data.setdefault("php_admin_value", {})
                    admin[inner] = value
            data["path"] = str(path)
            return {pool_name: data}
    except (OSError, ValueError):
        pass
    return {}


def php_fpm_children_by_pool() -> Dict[str, int]:
    try:
        output = subprocess.check_output(
            ["ps", "-o", "cmd=", "-C", "php-fpm8.3"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return {}
    counts: Dict[str, int] = defaultdict(int)
    for line in output.splitlines():
        if "php-fpm: pool" not in line or "master process" in line:
            continue
        pool = line.split("php-fpm: pool", 1)[-1].strip()
        if pool:
            counts[pool] += 1
    return dict(counts)


def collect_mysql_metrics() -> Optional[Dict[str, Any]]:
    def _run(query: str) -> Optional[int]:
        try:
            output = subprocess.check_output(
                ["mysql", "-Nse", query],
                text=True,
                stderr=subprocess.DEVNULL,
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            return None
        for line in output.splitlines():
            parts = line.strip().split()
            if len(parts) == 2:
                try:
                    return int(float(parts[1]))
                except ValueError:
                    continue
        return None

    max_connections = _run("SHOW VARIABLES LIKE 'max_connections';")
    threads_connected = _run("SHOW GLOBAL STATUS LIKE 'Threads_connected';")
    threads_running = _run("SHOW GLOBAL STATUS LIKE 'Threads_running';")
    max_used = _run("SHOW GLOBAL STATUS LIKE 'Max_used_connections';")
    uptime = _run("SHOW GLOBAL STATUS LIKE 'Uptime';")
    if max_connections is None or threads_connected is None:
        return None
    return {
        "max_connections": max_connections,
        "threads_connected": threads_connected,
        "threads_running": threads_running,
        "max_used_connections": max_used,
        "uptime": uptime,
    }


def collect_valkey_metrics() -> Optional[Dict[str, Any]]:
    cli = shutil.which("valkey-cli") or shutil.which("redis-cli")
    if not cli:
        return None
    password: Optional[str] = None
    if shell_exists(VALKEY_CONFIG):
        try:
            for line in VALKEY_CONFIG.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.lower().startswith("requirepass"):
                    parts = line.split()
                    if len(parts) >= 2:
                        password = parts[1]
                    break
        except (OSError, UnicodeDecodeError):
            password = None
    base_cmd = [cli, "INFO", "memory"]
    auth_cmd = [cli, "-a", password, "INFO", "memory"] if password else None
    try:
        output = subprocess.check_output(
            base_cmd,
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError:
        return None
    except subprocess.CalledProcessError:
        output = ""
    if "NOAUTH" in output and password and auth_cmd:
        try:
            output = subprocess.check_output(
                auth_cmd,
                text=True,
                stderr=subprocess.DEVNULL,
            )
        except subprocess.CalledProcessError:
            return None
    if not output:
        return None
    metrics: Dict[str, Any] = {}
    for raw in output.splitlines():
        if ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            continue
        if key in {"used_memory", "used_memory_peak", "maxmemory"}:
            try:
                metrics[key] = int(value)
            except ValueError:
                continue
        elif key in {"maxmemory_human"}:
            metrics[key] = value
        elif key == "mem_fragmentation_ratio":
            try:
                metrics[key] = float(value)
            except ValueError:
                continue
    if "used_memory" not in metrics:
        return None
    metrics["cli"] = cli
    if password:
        metrics["password"] = password
    return metrics


def autoscale_php_pool(pool_name: str, config: Dict[str, Any], auto_ctx: Dict[str, Any]) -> None:
    max_children = config.get("max_children")
    if not isinstance(max_children, int) or max_children <= 0:
        return
    data = load_runtime_json(PHP_AUTOSCALE_FILE)
    meta = runtime_meta_scope(data, pool_name)
    if recently_scaled(meta):
        return
    new_max = max_children + max(int(math.ceil(max_children * PHP_AUTOSCALE_STEP_RATIO)), PHP_AUTOSCALE_MIN_STEP)
    if new_max > PHP_AUTOSCALE_MAX:
        new_max = PHP_AUTOSCALE_MAX
    if new_max <= max_children:
        return
    new_start = max(4, min(new_max, max(config.get("start_servers", new_max // 2), new_max // 2)))
    new_min_spare = max(3, min(new_max, max(config.get("min_spare_servers", new_max // 3), new_max // 3)))
    new_max_spare = min(
        new_max,
        max(
            new_min_spare + 2,
            config.get("max_spare_servers", new_max // 2),
            new_max // 2 + 2,
        ),
    )
    data[pool_name] = {
        "max_children": new_max,
        "start_servers": new_start,
        "min_spare_servers": new_min_spare,
        "max_spare_servers": new_max_spare,
    }
    meta["last_scaled_at"] = time.time()
    save_runtime_json(PHP_AUTOSCALE_FILE, data)
    auto_ctx["actions"].append(
        f"Autoscaled PHP-FPM pool {pool_name}: max_children {max_children} -> {new_max}."
    )
    auto_ctx["states"].add("core.php")


def autoscale_mysql(metrics: Dict[str, Any], auto_ctx: Dict[str, Any]) -> None:
    max_connections = metrics.get("max_connections")
    threads_connected = metrics.get("threads_connected")
    if not isinstance(max_connections, int) or not isinstance(threads_connected, int) or max_connections <= 0:
        return
    ratio = threads_connected / max_connections
    if ratio < MYSQL_CRITICAL_RATIO:
        return
    data = load_runtime_json(MYSQL_AUTOSCALE_FILE)
    meta = runtime_meta_scope(data, "mysql")
    if recently_scaled(meta):
        return
    increment = max(int(math.ceil(max_connections * MYSQL_AUTOSCALE_STEP_RATIO)), MYSQL_AUTOSCALE_MIN_STEP)
    new_max = max_connections + increment
    if new_max > MYSQL_AUTOSCALE_MAX:
        new_max = MYSQL_AUTOSCALE_MAX
    if new_max <= max_connections:
        return
    data["mysql"] = {"max_connections": new_max}
    meta["last_scaled_at"] = time.time()
    save_runtime_json(MYSQL_AUTOSCALE_FILE, data)
    auto_ctx["actions"].append(
        f"Autoscaled MySQL max_connections {max_connections} -> {new_max}."
    )
    states = auto_ctx.get("states")
    if isinstance(states, set):
        states.add("optional.magento-optimization")
    try:
        subprocess.run(
            ["mysql", "-e", f"SET GLOBAL max_connections = {new_max};"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


def autoscale_valkey(metrics: Dict[str, Any], auto_ctx: Dict[str, Any]) -> None:
    maxmemory = metrics.get("maxmemory")
    used_memory = metrics.get("used_memory")
    cli = metrics.get("cli")
    if not isinstance(maxmemory, int) or maxmemory <= 0:
        return
    if not isinstance(used_memory, int) or used_memory <= 0:
        return
    ratio = used_memory / maxmemory if maxmemory else 0
    if ratio < VALKEY_CRITICAL_RATIO:
        return
    total_mem = read_meminfo().get("MemTotal", 0) * 1024
    hard_cap = int(total_mem * VALKEY_AUTOSCALE_MAX_RATIO)
    if hard_cap <= 0:
        hard_cap = maxmemory
    increment = max(
        int(maxmemory * VALKEY_AUTOSCALE_STEP_RATIO),
        VALKEY_AUTOSCALE_MIN_STEP_MB * 1024 * 1024,
    )
    new_max = maxmemory + increment
    if new_max > hard_cap:
        new_max = hard_cap
    if new_max <= maxmemory:
        return
    data = load_runtime_json(VALKEY_AUTOSCALE_FILE)
    meta = runtime_meta_scope(data, "valkey")
    if recently_scaled(meta):
        return
    new_value_mb = max(new_max // (1024 * 1024), VALKEY_AUTOSCALE_MIN_STEP_MB)
    data["valkey"] = {"maxmemory": f"{new_value_mb}mb"}
    meta["last_scaled_at"] = time.time()
    save_runtime_json(VALKEY_AUTOSCALE_FILE, data)
    auto_ctx["actions"].append(
        f"Autoscaled Valkey maxmemory {maxmemory // (1024 * 1024)}mb -> {new_value_mb}mb."
    )
    states = auto_ctx.get("states")
    if isinstance(states, set):
        states.add("optional.magento-optimization")
    if isinstance(cli, str):
        password = metrics.get("password")
        try:
            cmd = [cli]
            if password:
                cmd += ["-a", password]
            cmd += ["CONFIG", "SET", "maxmemory", f"{new_value_mb}mb"]
            subprocess.run(
                cmd,
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            pass


def apply_states(states: Iterable[str]) -> Dict[str, bool]:
    results: Dict[str, bool] = {}
    for state in states:
        cmd = ["salt-call", "--local", "state.apply", state]
        try:
            proc = subprocess.run(
                cmd,
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            success = proc.returncode == 0
        except FileNotFoundError:
            success = False
        results[state] = success
    return results


def restart_services(services: Iterable[str]) -> Dict[str, Dict[str, Any]]:
    results: Dict[str, Dict[str, Any]] = {}
    for service in services:
        if not service_exists(service):
            continue
        cmd = ["systemctl", "restart", service]
        try:
            proc = subprocess.run(
                cmd,
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            ok = proc.returncode == 0
            status_snippet = ""
            log_snippet = ""
            if ok:
                try:
                    status_proc = subprocess.run(
                        ["systemctl", "status", service, "--no-pager", "--lines", "5"],
                        check=False,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                    )
                    status_snippet = status_proc.stdout.strip()
                except FileNotFoundError:
                    status_snippet = ""
                try:
                    journal_proc = subprocess.run(
                        [
                            "journalctl",
                            "-u",
                            service,
                            "--since",
                            "-5 min",
                            "--no-pager",
                            "--lines",
                            "20",
                        ],
                        check=False,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                    )
                    log_snippet = journal_proc.stdout.strip()
                except FileNotFoundError:
                    log_snippet = ""
            results[service] = {"ok": ok, "status": status_snippet, "journal": log_snippet}
        except FileNotFoundError:
            results[service] = {"ok": False, "status": "systemctl not found", "journal": ""}
    return results


def default_timeout_services() -> List[str]:
    services = ["php8.3-fpm"]
    if service_exists("varnish"):
        services.append("varnish")
    return services


def default_server_error_services() -> List[str]:
    services = ["php8.3-fpm", "nginx"]
    if service_exists("varnish"):
        services.append("varnish")
    return services


def default_failure_services() -> List[str]:
    services = ["php8.3-fpm", "nginx"]
    if service_exists("varnish"):
        services.append("varnish")
    return services


def normalize_services(value: Any) -> List[str]:
    if isinstance(value, (list, tuple, set)):
        return [str(item) for item in value if str(item).strip()]
    if value:
        return [str(value)]
    return []


def tls_days_until_expiry(url: str, timeout: float) -> Tuple[Optional[float], Optional[str]]:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme.lower() != "https":
        return None, None
    host = parsed.hostname
    if not host:
        return None, "invalid host"
    port = parsed.port or 443
    context = ssl.create_default_context()
    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            with context.wrap_socket(sock, server_hostname=host) as ssock:
                cert = ssock.getpeercert()
    except Exception as exc:  # noqa: BLE001
        return None, f"TLS handshake failed: {exc}"
    if not cert or "notAfter" not in cert:
        return None, "certificate missing expiry"
    try:
        expiry = datetime.strptime(cert["notAfter"], "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
    except ValueError:
        return None, "unable to parse certificate expiry"
    days_left = (expiry - datetime.now(timezone.utc)).total_seconds() / 86400
    return days_left, None


def load_service_heal_map() -> Dict[str, float]:
    try:
        data = json.loads((RUNTIME_DIR / "service-heal.json").read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return {str(k): float(v) for k, v in data.items()}
    except FileNotFoundError:
        return {}
    except Exception:
        return {}
    return {}


def save_service_heal_map(data: Dict[str, float]) -> None:
    try:
        ensure_runtime_dir()
        path = RUNTIME_DIR / "service-heal.json"
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception:
        pass


def _command_from_details(details: Dict[str, Any]) -> str:
    args = details.get("args") or details.get("job_args")
    if isinstance(args, list) and args:
        return " ".join(str(item) for item in args)
    if isinstance(args, str):
        return args
    return ""


def _sites_in_command(command: str) -> Set[str]:
    sites: Set[str] = set()
    match = re.search(r"--site\s+([\w\-/]+)", command)
    if match:
        sites.add(match.group(1))
    for path_match in re.findall(r"/var/www/([\w\-]+)", command):
        sites.add(path_match)
    return sites


def load_site_checks() -> List[Dict[str, Any]]:
    if Caller is None:
        return []
    try:
        caller = Caller()  # type: ignore[call-arg]
        sites = caller.cmd("pillar.get", "saltgoat:monitor:sites", [])
        if isinstance(sites, list):
            return [site for site in sites if isinstance(site, dict) and site.get("url")]
    except Exception:
        return []
    return []


def check_sites(
    sites: List[Dict[str, Any]],
    details: List[str],
    auto_ctx: Dict[str, Any],
    bump: Any,
) -> List[Dict[str, Any]]:
    results: List[Dict[str, Any]] = []
    for site in sites:
        url = str(site.get("url", ""))
        if not url:
            continue
        name = str(site.get("name") or url)
        timeout = float(site.get("timeout", 5.0) or 5.0)
        expected = int(site.get("expect", 200) or 200)
        headers = site.get("headers") if isinstance(site.get("headers"), dict) else {}
        retries = max(1, int(site.get("retries", 1) or 1))
        success_attempt: Optional[int] = None
        status: Optional[int] = None
        body_snippet = ""
        error_msg: Optional[str] = None
        duration = 0.0

        for attempt in range(1, retries + 1):
            req = urllib.request.Request(url, headers={"User-Agent": "SaltGoatHealth/1.0", **headers})
            start = time.time()
            status = None
            body_snippet = ""
            error_msg = None
            try:
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    status = resp.getcode()
                    try:
                        body_snippet = resp.read(256).decode("utf-8", errors="ignore")
                    except Exception:
                        body_snippet = ""
            except urllib.error.HTTPError as exc:
                status = exc.code
                try:
                    body_snippet = exc.read(256).decode("utf-8", errors="ignore")
                except Exception:
                    body_snippet = ""
            except Exception as exc:
                error_msg = str(exc)
            duration = time.time() - start
            if error_msg is None and status == expected:
                success_attempt = attempt
                break
            if attempt < retries:
                time.sleep(min(2.0, timeout / 2))

        site_result = {
            "name": name,
            "url": url,
            "status": status,
            "expected": expected,
            "duration": round(duration, 3),
            "attempts": retries,
        }
        if success_attempt is not None:
            site_result["success_attempt"] = success_attempt
        if error_msg:
            site_result["error"] = error_msg
        if body_snippet:
            site_result["body"] = body_snippet
        results.append(site_result)

        failure_defaults = default_failure_services()
        timeout_defaults = default_timeout_services()
        server_error_defaults = default_server_error_services()

        tls_warn = int(site.get("tls_warn_days", 14) or 14)
        tls_crit = int(site.get("tls_critical_days", 7) or 7)
        tls_days, tls_error = tls_days_until_expiry(url, timeout)
        if tls_days is not None:
            site_result["tls_days_remaining"] = round(tls_days, 2)
            if tls_days < 0:
                bump("CRITICAL", f"TLS {name}")
                details.append(f"Site {name} TLS certificate expired {-round(tls_days, 2)} days ago")
                auto_ctx.setdefault("services", set()).update(
                    normalize_services(site.get("failure_services", failure_defaults))
                )
            elif tls_days <= tls_crit:
                bump("CRITICAL", f"TLS {name}")
                details.append(f"Site {name} TLS certificate expires in {round(tls_days, 2)} days")
            elif tls_days <= tls_warn:
                bump("WARNING", f"TLS {name}")
                details.append(f"Site {name} TLS certificate expires in {round(tls_days, 2)} days")
        elif tls_error:
            bump("WARNING", f"TLS {name}")
            details.append(f"Site {name} TLS check failed: {tls_error}")

        if error_msg:
            bump("CRITICAL", f"Site {name}")
            details.append(f"Site check failed: {name} ({error_msg})")
            auto_ctx.setdefault("services", set()).update(
                normalize_services(site.get("failure_services", failure_defaults))
            )
            continue

        if status is None:
            bump("CRITICAL", f"Site {name}")
            details.append(f"Site check failed: {name} returned no status")
            auto_ctx.setdefault("services", set()).update(
                normalize_services(site.get("failure_services", failure_defaults))
            )
            continue

        details.append(f"Site {name}: HTTP {status} ({duration:.2f}s)")
        if status != expected:
            if status >= 500:
                bump("CRITICAL", f"Site {name}")
            else:
                bump("WARNING", f"Site {name}")

            if status in {502, 503, 504}:
                services = normalize_services(site.get("timeout_services", timeout_defaults))
            elif status >= 500:
                services = normalize_services(site.get("server_error_services", server_error_defaults))
            else:
                services = normalize_services(site.get("failure_services", failure_defaults))
            auto_ctx.setdefault("services", set()).update(services)
        elif status >= 400:
            bump("WARNING", f"Site {name}")

    return results
def hostname() -> str:
    return HOSTNAME or run_cmd(["hostname"]) or "localhost"


def load_thresholds(cpu_count: int) -> Dict[str, float]:
    # baseline: warning at 1.25x cores, critical at 1.5x
    base = {
        "warn_1m": cpu_count * 1.25,
        "crit_1m": cpu_count * 1.5,
        "warn_5m": cpu_count * 1.1,
        "crit_5m": cpu_count * 1.4,
        "warn_15m": cpu_count * 1.0,
        "crit_15m": cpu_count * 1.3,
    }
    overrides = get_threshold_overrides().get("load", {})
    for key in list(base.keys()):
        if key in overrides:
            try:
                base[key] = float(overrides[key])
            except (TypeError, ValueError):
                continue
    return base


def _append_alert_log(label: str, tag: str, payload: Dict[str, Any]) -> None:
    try:
        ALERT_LOG.parent.mkdir(parents=True, exist_ok=True)
        record = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "label": label,
            "tag": tag,
            "host": hostname(),
            "payload": payload,
        }
        with ALERT_LOG.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    except Exception:
        pass


def log_to_file(label: str, tag: str, payload: Dict[str, Any]) -> None:
    if shell_exists(LOGGER_SCRIPT):
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
            return
        except Exception:
            pass
    _append_alert_log(label, tag, payload)


def telegram_notify(tag: str, message: str, payload: Dict[str, Any]) -> None:
    if not TELEGRAM_AVAILABLE:
        return

    def _log(kind: str, extra: Dict[str, Any]) -> None:
        log_to_file("TELEGRAM", f"{tag} {kind}", extra)

    profiles = reactor_common.load_telegram_profiles(str(TELEGRAM_CONFIG), _log)
    if not profiles:
        _log("skip", {"reason": "no_profiles"})
        return
    _log("profile_summary", {"count": len(profiles)})
    reactor_common.broadcast_telegram(
        message,
        profiles,
        _log,
        tag=tag,
        parse_mode="HTML",
    )


def emit_salt_event(tag: str, payload: Dict[str, Any]) -> None:
    if Caller is None:
        return
    try:
        caller = Caller()  # type: ignore[call-arg]
        caller.cmd("event.send", tag, payload)
    except Exception:
        pass


def color_severity(level: str) -> str:
    return level


def format_html_block(title: str, pairs: List[Tuple[str, str]]) -> Tuple[str, str]:
    underline = "=" * 30
    entries = [(label, value) for label, value in pairs if value not in (None, "")]
    width = max((len(label) for label, _ in entries), default=8)
    lines = [underline, title, underline]
    for label, value in entries:
        parts = str(value).splitlines() or [""]
        lines.append(f"{label.ljust(width)} : {parts[0]}")
        for extra in parts[1:]:
            lines.append(f"{' ' * width}   {extra}")
    plain = "\n".join(lines)
    return plain, f"<pre>{html.escape(plain)}</pre>"


def get_threshold_overrides() -> Dict[str, Any]:
    if Caller is None:
        return {}
    try:
        caller = Caller()  # type: ignore[call-arg]
        # preferred path saltgoat:monitor:thresholds, fallback monitor_thresholds
        overrides = caller.cmd("pillar.get", "saltgoat:monitor:thresholds", {})
        if not overrides:
            overrides = caller.cmd("pillar.get", "monitor_thresholds", {})
        if isinstance(overrides, dict):
            return overrides
    except Exception:
        pass
    return {}


def evaluate() -> Tuple[str, List[str], Dict[str, Any], List[str]]:
    cpu_count = os.cpu_count() or 1
    load1, load5, load15 = get_load()
    thresholds = load_thresholds(cpu_count)

    severity = "INFO"
    details: List[str] = []
    triggers: List[str] = []
    auto_ctx: Dict[str, Any] = {"actions": [], "states": set(), "services": set()}

    def bump(level: str, reason: str) -> None:
        nonlocal severity
        order = {"INFO": 0, "NOTICE": 1, "WARNING": 2, "CRITICAL": 3}
        if order[level] > order[severity]:
            severity = level
        if reason not in triggers:
            triggers.append(reason)

    # Load check
    load_line = f"Load average: 1m={load1:.2f} 5m={load5:.2f} 15m={load15:.2f} (cores={cpu_count})"
    details.append(load_line)
    if load1 >= thresholds["crit_1m"] or load5 >= thresholds["crit_5m"] or load15 >= thresholds["crit_15m"]:
        bump("CRITICAL", "Load")
        details.append(
            "Load critical: "
            f"1m threshold {thresholds['crit_1m']:.2f}, "
            f"5m threshold {thresholds['crit_5m']:.2f}, "
            f"15m threshold {thresholds['crit_15m']:.2f}"
        )
    elif load1 >= thresholds["warn_1m"] or load5 >= thresholds["warn_5m"] or load15 >= thresholds["warn_15m"]:
        bump("WARNING", "Load")
        details.append(
            "Load warning: "
            f"1m threshold {thresholds['warn_1m']:.2f}, "
            f"5m threshold {thresholds['warn_5m']:.2f}, "
            f"15m threshold {thresholds['warn_15m']:.2f}"
        )

    # Memory
    memory_thresholds = DEFAULT_THRESHOLDS["memory"] | get_threshold_overrides().get("memory", {})
    mem_percent = memory_usage_percent()
    details.append(f"Memory used: {mem_percent:.1f}%")
    mem_crit = float(memory_thresholds.get("critical", DEFAULT_THRESHOLDS["memory"]["critical"]))
    mem_warn = float(memory_thresholds.get("warning", DEFAULT_THRESHOLDS["memory"]["warning"]))
    mem_notice = float(memory_thresholds.get("notice", DEFAULT_THRESHOLDS["memory"]["notice"]))
    if mem_percent >= mem_crit:
        bump("CRITICAL", "Memory")
        details.append(f"Memory critical: usage >= {mem_crit:.1f}%")
    elif mem_percent >= mem_warn:
        bump("WARNING", "Memory")
        details.append(f"Memory warning: usage >= {mem_warn:.1f}%")
    elif mem_percent >= mem_notice:
        bump("NOTICE", "Memory")
        details.append(f"Memory notice: usage >= {mem_notice:.1f}%")

    # Disk
    disk_thresholds = DEFAULT_THRESHOLDS["disk"] | get_threshold_overrides().get("disk", {})
    disks = disk_usage([Path("/"), Path("/var/lib/mysql"), Path("/home")])
    for mount, percent in disks.items():
        details.append(f"Disk {mount}: {percent:.1f}% used")
        disk_crit = float(disk_thresholds.get("critical", DEFAULT_THRESHOLDS["disk"]["critical"]))
        disk_warn = float(disk_thresholds.get("warning", DEFAULT_THRESHOLDS["disk"]["warning"]))
        disk_notice = float(disk_thresholds.get("notice", DEFAULT_THRESHOLDS["disk"]["notice"]))
        if percent >= disk_crit:
            bump("CRITICAL", f"Disk {mount}")
            details.append(f"Disk critical: {mount} usage >= {disk_crit:.1f}%")
        elif percent >= disk_warn:
            bump("WARNING", f"Disk {mount}")
            details.append(f"Disk warning: {mount} usage >= {disk_warn:.1f}%")
        elif percent >= disk_notice:
            bump("NOTICE", f"Disk {mount}")
            details.append(f"Disk notice: {mount} usage >= {disk_notice:.1f}%")

    # Services
    core_services = ["nginx", "php8.3-fpm", "mysql", "valkey", "rabbitmq", "salt-minion"]
    if service_exists("varnish"):
        core_services.append("varnish")
    services = service_status(core_services)
    failing = [svc for svc, ok in services.items() if not ok]
    if failing:
        bump("CRITICAL", "Services")
        details.append("Services down: " + ", ".join(failing))
    else:
        details.append("All critical services running.")

    fpm_info: Dict[str, Any] = {"pools": {}}
    pool_configs = php_fpm_pool_configs()
    pool_children = php_fpm_children_by_pool()
    if pool_configs:
        total_children = 0
        for pool_name, config in sorted(pool_configs.items()):
            entry: Dict[str, Any] = {}
            max_children = config.get("max_children")
            current_children = pool_children.get(pool_name, 0)
            total_children += current_children
            entry["children"] = current_children
            if max_children is not None:
                entry["max_children"] = max_children
            listen = config.get("listen")
            if listen:
                entry["listen"] = listen
            pm_mode = config.get("pm")
            if pm_mode:
                entry["pm"] = pm_mode
            admin_values = config.get("php_admin_value")
            if isinstance(admin_values, dict):
                memory_limit = admin_values.get("memory_limit")
                if memory_limit:
                    entry["memory_limit"] = memory_limit
            if max_children:
                usage = current_children / max_children if max_children else 0
                entry["utilization"] = round(usage, 4)
                if usage >= 1.0:
                    bump("CRITICAL", "PHP-FPM capacity")
                    details.append(
                        f"PHP-FPM pool '{pool_name}' saturated: "
                        f"{current_children}/{max_children} workers in use."
                    )
                    autoscale_php_pool(pool_name, config, auto_ctx)
                elif usage >= FPM_WARNING_RATIO:
                    bump("WARNING", "PHP-FPM capacity")
                    details.append(
                        "PHP-FPM pool '{pool}' near capacity: "
                        "{current}/{max} workers ({ratio:.1f}%).".format(
                            pool=pool_name,
                            current=current_children,
                            max=max_children,
                            ratio=usage * 100,
                        )
                    )
                elif usage >= FPM_NOTICE_RATIO:
                    bump("NOTICE", "PHP-FPM capacity")
                    details.append(
                        "PHP-FPM pool '{pool}' warming up: "
                        "{current}/{max} workers ({ratio:.1f}%).".format(
                            pool=pool_name,
                            current=current_children,
                            max=max_children,
                            ratio=usage * 100,
                        )
                    )
            fpm_info["pools"][pool_name] = entry
        extra_pools = {pool: cnt for pool, cnt in pool_children.items() if pool not in fpm_info["pools"]}
        for pool_name, count in extra_pools.items():
            fpm_info["pools"][pool_name] = {"children": count}
        fpm_info["children_total"] = total_children
        if total_children == 0:
            bump("WARNING", "PHP-FPM capacity")
            details.append("PHP-FPM pools discovered but no worker processes are running.")
    elif pool_children:
        # 没有解析到配置但存在进程
        fpm_info["children_total"] = sum(pool_children.values())
        fpm_info["pools"] = {pool: {"children": count} for pool, count in pool_children.items()}

    mysql_info: Dict[str, Any] = {}
    mysql_metrics = collect_mysql_metrics()
    if mysql_metrics:
        max_connections = mysql_metrics["max_connections"]
        threads_connected = mysql_metrics["threads_connected"]
        ratio = threads_connected / max_connections if max_connections else 0
        mysql_info.update(mysql_metrics)
        mysql_info["utilization"] = round(ratio, 4)
        details.append(
            f"MySQL connections: {threads_connected}/{max_connections} ({ratio*100:.1f}%)."
        )
        if ratio >= MYSQL_CRITICAL_RATIO:
            bump("CRITICAL", "MySQL connections")
            details.append("MySQL connections saturated; attempting autoscale.")
            autoscale_mysql(mysql_metrics, auto_ctx)
        elif ratio >= MYSQL_WARNING_RATIO:
            bump("WARNING", "MySQL connections")
        elif ratio >= MYSQL_NOTICE_RATIO:
            bump("NOTICE", "MySQL connections")

    valkey_info: Dict[str, Any] = {}
    valkey_metrics = collect_valkey_metrics()
    if valkey_metrics:
        used_memory = valkey_metrics.get("used_memory", 0)
        maxmemory = valkey_metrics.get("maxmemory", 0)
        ratio = used_memory / maxmemory if maxmemory else 0
        valkey_info.update({k: v for k, v in valkey_metrics.items() if k != "cli"})
        valkey_info["utilization"] = round(ratio, 4) if maxmemory else 0
        if maxmemory:
            details.append(
                "Valkey memory: {used}/{limit} ({ratio:.1f}%).".format(
                    used=used_memory // (1024 * 1024),
                    limit=maxmemory // (1024 * 1024),
                    ratio=ratio * 100,
                )
            )
            if ratio >= VALKEY_CRITICAL_RATIO:
                bump("CRITICAL", "Valkey memory")
                details.append("Valkey memory near limit; attempting autoscale.")
                autoscale_valkey(valkey_metrics, auto_ctx)
            elif ratio >= VALKEY_WARNING_RATIO:
                bump("WARNING", "Valkey memory")

    site_payload: List[Dict[str, Any]] = []
    sites_config = load_site_checks()
    if sites_config:
        site_results = check_sites(sites_config, details, auto_ctx, bump)
        site_payload.extend(site_results)

    payload = {
        "host": hostname(),
        "severity": severity,
        "load": {"1m": load1, "5m": load5, "15m": load15},
        "memory": mem_percent,
        "disks": disks,
        "services": services,
        "php_fpm": fpm_info,
        "mysql": mysql_info,
        "valkey": valkey_info,
        "sites": site_payload,
        "thresholds": {
            "load": thresholds,
            "memory": {"notice": mem_notice, "warning": mem_warn, "critical": mem_crit},
            "disk": {"notice": disk_notice, "warning": disk_warn, "critical": disk_crit},
            "php_fpm": {"notice_ratio": FPM_NOTICE_RATIO, "warning_ratio": FPM_WARNING_RATIO},
            "mysql": {"notice_ratio": MYSQL_NOTICE_RATIO, "warning_ratio": MYSQL_WARNING_RATIO, "critical_ratio": MYSQL_CRITICAL_RATIO},
            "valkey": {"warning_ratio": VALKEY_WARNING_RATIO, "critical_ratio": VALKEY_CRITICAL_RATIO},
        },
        "autoscale": {"actions": list(auto_ctx["actions"])},
    }
    auto_ctx["states"] = sorted(auto_ctx["states"])
    auto_ctx["services"] = sorted(auto_ctx.get("services", []))
    return severity, details, payload, triggers, auto_ctx


def parse_args():
    parser = ArgumentParser(description="SaltGoat resource alert")
    parser.add_argument(
        "--force-severity",
        choices=["INFO", "NOTICE", "WARNING", "CRITICAL"],
        help="测试用途：强制使用指定告警级别",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    severity, details, payload, triggers, auto_ctx = evaluate()
    if args.force_severity:
        severity = args.force_severity

    auto_actions: List[str] = auto_ctx.get("actions", []) if isinstance(auto_ctx, dict) else []
    auto_states = auto_ctx.get("states", []) if isinstance(auto_ctx, dict) else []
    auto_services = auto_ctx.get("services", []) if isinstance(auto_ctx, dict) else []
    if auto_actions:
        for action in auto_actions:
            print(f"[AUTOSCALE] {action}")
            details.append(f"AUTOSCALE: {action}")
        state_results = apply_states(auto_states)
        autoscale_section = payload.setdefault("autoscale", {})
        autoscale_section["states"] = auto_states
        autoscale_section["results"] = state_results
        for state, ok in state_results.items():
            if not ok:
                details.append(f"AUTOSCALE: state.apply {state} failed")
        autoscale_payload = {
            "host": payload.get("host", hostname()),
            "actions": auto_actions,
            "states": auto_states,
            "results": state_results,
        }
        log_to_file("AUTOSCALE", "saltgoat/autoscale", autoscale_payload)
        host_id = autoscale_payload["host"]
        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        fields: List[Tuple[str, str]] = [("Host", host_id), ("Time", timestamp)]
        for action in auto_actions:
            fields.append(("Action", action))
        if auto_states:
            fields.append(("States", ", ".join(auto_states)))
        _, html_block = format_html_block("AUTOSCALE ACTIONS", fields)
        telegram_notify("saltgoat/autoscale", html_block, autoscale_payload)
        emit_salt_event("saltgoat/autoscale", autoscale_payload)

    if auto_services:
        heal_map = load_service_heal_map()
        now = time.time()
        to_restart: List[str] = []
        skipped: List[str] = []
        for service in auto_services:
            last = heal_map.get(service)
            if last and now - last < SERVICE_HEAL_COOLDOWN:
                skipped.append(service)
            else:
                to_restart.append(service)

        if skipped:
            details.append(
                "AUTOSCALE: skip restart for {} (cooldown)".format(
                    ", ".join(sorted(skipped))
                )
            )

        if to_restart:
            service_results = restart_services(to_restart)
            autoscale_section = payload.setdefault("autoscale", {})
            autoscale_section["services"] = {svc: info.get("ok", False) for svc, info in service_results.items()}
            autoscale_section["service_status"] = {svc: info.get("status", "") for svc, info in service_results.items()}
            autoscale_section["service_logs"] = {svc: info.get("journal", "") for svc, info in service_results.items()}
            for service, info in service_results.items():
                if info.get("ok"):
                    details.append(f"AUTOSCALE: restarted service {service}")
                    status_text = info.get("status")
                    if status_text:
                        details.append(f"AUTOSCALE: systemctl status {service}\n{status_text}")
                    journal_text = info.get("journal")
                    if journal_text:
                        details.append(f"AUTOSCALE: journalctl -u {service}\n{journal_text}")
                    heal_map[service] = now
                else:
                    details.append(f"AUTOSCALE: restart service {service} failed")
            save_service_heal_map(heal_map)

    if severity in {"WARNING", "CRITICAL"}:
        trigger_text = ", ".join(triggers) if triggers else "load"
        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        fields: List[Tuple[str, str]] = [
            ("Host", payload["host"]),
            ("Trigger", trigger_text),
            ("Time", timestamp),
        ]
        for detail in details:
            if not detail:
                continue
            fields.append(("Detail", str(detail)))
        plain_block, html_block = format_html_block(f"{severity} RESOURCE ALERT", fields)
        tag = f"saltgoat/monitor/resources/{severity.lower()}"
        augmented = payload | {"details": details, "tag": tag}
        log_to_file("RESOURCE", tag, augmented)
        telegram_notify("saltgoat/monitor/resources", html_block, augmented)
        emit_salt_event(tag, payload)
        print(plain_block)
    else:
        print("Resources within normal range; no alert issued.")


if __name__ == "__main__":
    main()
