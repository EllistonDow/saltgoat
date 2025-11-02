#!/usr/bin/env python3
"""
SaltGoat resource alert helper.

Evaluates load/memory/disk/service health and pushes Telegram + Salt events when thresholds are exceeded.
"""

from __future__ import annotations

import json
import math
import os
import shutil
import socket
import subprocess
import sys
import time
from collections import defaultdict
from argparse import ArgumentParser
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple

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


def service_status(services: Iterable[str]) -> Dict[str, bool]:
    result: Dict[str, bool] = {}
    for svc in services:
        ok = subprocess.call(
            ["systemctl", "is-active", "--quiet", svc],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ) == 0
        result[svc] = ok
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


def log_to_file(label: str, tag: str, payload: Dict[str, Any]) -> None:
    if not shell_exists(LOGGER_SCRIPT):
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
    reactor_common.broadcast_telegram(message, profiles, _log, tag=tag)


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
    auto_ctx: Dict[str, Any] = {"actions": [], "states": set()}

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
    services = service_status(["nginx", "php8.3-fpm", "mysql", "valkey", "rabbitmq", "salt-minion"])
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
    auto_ctx["states"] = list(auto_ctx["states"])
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
    if auto_actions:
        for action in auto_actions:
            print(f"[AUTOSCALE] {action}")
            details.append(f"AUTOSCALE: {action}")
        state_results = apply_states(auto_states)
        payload.setdefault("autoscale", {})["results"] = state_results
        for state, ok in state_results.items():
            if not ok:
                details.append(f"AUTOSCALE: state.apply {state} failed")
        autoscale_payload = payload.get("autoscale", {}).copy()
        autoscale_payload["actions"] = auto_actions
        autoscale_payload["results"] = state_results
        log_to_file("AUTOSCALE", "saltgoat/autoscale", autoscale_payload)
        message = "[SaltGoat] Autoscale executed\n" + "\n".join(f" - {action}" for action in auto_actions)
        telegram_notify("saltgoat/autoscale", message, autoscale_payload)

    if severity in {"WARNING", "CRITICAL"}:
        lines = [
            f"[SaltGoat] {severity} resource alert",
            f"Host: {payload['host']}",
            f"Triggered: {', '.join(triggers) if triggers else 'Load'}",
        ]
        lines.extend(f" - {detail}" for detail in details)
        message = "\n".join(lines)
        tag = f"saltgoat/monitor/resources/{severity.lower()}"
        augmented = payload | {"details": details, "tag": tag}
        log_to_file("RESOURCE", tag, augmented)
        telegram_notify("saltgoat/monitor/resources", message, augmented)
        emit_salt_event(tag, payload)
        print(message)
    else:
        print("Resources within normal range; no alert issued.")


if __name__ == "__main__":
    main()
