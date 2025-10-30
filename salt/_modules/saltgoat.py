"""
SaltGoat custom execution module.

Provides helpers that wrap common state logic so Bash modules can defer to Salt.
"""

from __future__ import annotations

import json
import os
import shlex
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

__virtualname__ = "saltgoat"


def __virtual__():
    return __virtualname__


def _has_schedule():
    try:
        jobs = __salt__["schedule.list"]()  # type: ignore[union-attr]
        return isinstance(jobs, dict)
    except Exception:  # noqa: BLE001
        return False


def _schedule_entries() -> Optional[Dict[str, Any]]:
    try:
        entries = __salt__["schedule.list"](return_yaml=False)  # type: ignore[call-arg]
    except TypeError:
        try:
            entries = __salt__["schedule.list"]()  # type: ignore[union-attr]
        except Exception:  # noqa: BLE001
            return None
    except Exception:  # noqa: BLE001
        return None

    if isinstance(entries, dict):
        if "schedule" in entries and isinstance(entries["schedule"], dict):
            return entries["schedule"]
        return entries
    if isinstance(entries, str):
        try:
            import yaml  # type: ignore

            data = yaml.safe_load(entries)
        except Exception:  # noqa: BLE001
            return None
        if isinstance(data, dict):
            if "schedule" in data and isinstance(data["schedule"], dict):
                return data["schedule"]
            return data
    return None


def magento_schedule_install(site: str = "tank") -> Dict[str, Any]:
    """
    Install Magento maintenance schedule for the given site.

    Returns a dict describing whether Salt Schedule or cron fallback was used.
    """
    ret: Dict[str, Any] = {
        "site": site,
        "mode": "schedule",
        "result": True,
        "comment": "",
        "changes": {},
    }

    config: Dict[str, Any] = __salt__["pillar.get"]("magento_schedule", {})  # type: ignore[assignment]
    maintenance_cmd = config.get("maintenance_command", "saltgoat magetools maintenance")
    maintenance_extra_args = config.get("maintenance_extra_args", "")
    daily_args = config.get("daily_args", "")
    weekly_args = config.get("weekly_args", "")
    monthly_args = config.get("monthly_args", "")
    health_args = config.get("health_args", "")

    site_token = site.strip().lower().replace(" ", "_").replace("-", "_") or site

    base_jobs: Dict[str, str] = {
        f"magento_{site_token}_cron": f"cd /var/www/{site} && sudo -u www-data php bin/magento cron:run >> /var/log/magento-cron.log 2>&1",
        f"magento_{site_token}_daily": f"{maintenance_cmd} {site} daily {maintenance_extra_args} {daily_args} >> /var/log/magento-maintenance.log 2>&1",
        f"magento_{site_token}_weekly": f"{maintenance_cmd} {site} weekly {maintenance_extra_args} {weekly_args} >> /var/log/magento-maintenance.log 2>&1",
        f"magento_{site_token}_monthly": f"{maintenance_cmd} {site} monthly {maintenance_extra_args} {monthly_args} >> /var/log/magento-maintenance.log 2>&1",
        f"magento_{site_token}_health": f"{maintenance_cmd} {site} health {maintenance_extra_args} {health_args} >> /var/log/magento-health.log 2>&1",
    }

    dump_jobs_config = config.get("mysql_dump_jobs", []) or []
    dump_jobs: Dict[str, str] = {}
    if isinstance(dump_jobs_config, list):
        for dump_job in dump_jobs_config:
            if not isinstance(dump_job, dict):
                continue
            name = dump_job.get("name")
            if not name:
                continue
            job_site = dump_job.get("site")
            job_sites = dump_job.get("sites")
            if job_site and job_site != site:
                continue
            if job_sites and site not in job_sites:
                continue
            command = ["saltgoat", "magetools", "xtrabackup", "mysql", "dump"]
            if dump_job.get("database"):
                command += ["--database", str(dump_job["database"])]
            if dump_job.get("backup_dir"):
                command += ["--backup-dir", str(dump_job["backup_dir"])]
            if dump_job.get("repo_owner"):
                command += ["--repo-owner", str(dump_job["repo_owner"])]
            if dump_job.get("no_compress"):
                command.append("--no-compress")
            dump_jobs[name] = " ".join(command)

    api_watchers_config = config.get("api_watchers", []) or []
    api_watchers: Dict[str, str] = {}
    if isinstance(api_watchers_config, list):
        for watcher in api_watchers_config:
            if not isinstance(watcher, dict):
                continue
            name = watcher.get("name")
            if not name:
                continue
            job_site = watcher.get("site")
            job_sites = watcher.get("sites")
            if job_site and job_site != site:
                continue
            if job_sites and site not in job_sites:
                continue
            kinds = watcher.get("kinds") or []
            if isinstance(kinds, (list, tuple, set)):
                kinds_list = ",".join(str(kind) for kind in kinds)
            elif kinds:
                kinds_list = str(kinds)
            else:
                kinds_list = "orders,customers"
            api_watchers[name] = f"saltgoat magetools api watch --site {site} --kinds {kinds_list}"

    stats_jobs_config = config.get("stats_jobs", []) or []
    stats_jobs: Dict[str, str] = {}
    if isinstance(stats_jobs_config, list):
        for stats_job in stats_jobs_config:
            if not isinstance(stats_job, dict):
                continue
            name = stats_job.get("name")
            if not name:
                continue
            job_site = stats_job.get("site")
            job_sites = stats_job.get("sites")
            if job_site and job_site != site:
                continue
            if job_sites and site not in job_sites:
                continue
            period = str(stats_job.get("period", "daily")).lower()
            args: List[str] = [
                "saltgoat",
                "magetools",
                "stats",
                "--site",
                site,
                "--period",
                period,
            ]
            page_size = stats_job.get("page_size")
            if page_size:
                args.extend(["--page-size", str(page_size)])
            if stats_job.get("no_telegram"):
                args.append("--no-telegram")
            if stats_job.get("quiet"):
                args.append("--quiet")
            extra_args = stats_job.get("extra_args")
            if extra_args:
                if isinstance(extra_args, str):
                    args.extend(shlex.split(extra_args))
                elif isinstance(extra_args, (list, tuple, set)):
                    args.extend(str(part) for part in extra_args)
            stats_jobs[name] = " ".join(shlex.quote(arg) for arg in args)

    expected_commands: Dict[str, str] = {}
    expected_commands.update(base_jobs)
    expected_commands.update(dump_jobs)
    expected_commands.update(api_watchers)
    expected_commands.update(stats_jobs)

    state_result = __salt__["state.apply"](
        "optional.magento-schedule",
        pillar={"site_name": site},
    )
    ret["changes"] = state_result

    if _has_schedule():
        ret["comment"] = (
            "Salt Schedule entries rendered; ensure salt-minion service is running."
        )
        schedule_entries = _schedule_entries()

        removed: List[str] = []
        if isinstance(schedule_entries, dict):
            for job_name, details in schedule_entries.items():
                if job_name in expected_commands:
                    continue
                if not isinstance(details, dict):
                    continue
                args = details.get("args") or details.get("job_args")
                command = ""
                if isinstance(args, list) and args:
                    command = " ".join(str(item) for item in args)
                elif isinstance(args, str):
                    command = args
                if not command:
                    continue
                if (
                    f"--site {site}" in command
                    or f"/var/www/{site}" in command
                    or (command.strip().startswith("saltgoat magetools xtrabackup mysql dump") and site in command)
                    or any(command.strip() == expected.strip() for expected in expected_commands.values())
                ):
                    try:
                        if __salt__["schedule.delete"](job_name):
                            removed.append(job_name)
                    except Exception:  # noqa: BLE001
                        pass
        if removed:
            ret.setdefault("changes", {}).setdefault("removed_extra", removed)
    else:
        ret["mode"] = "cron"
        ret["comment"] = (
            "/etc/cron.d/magento-maintenance written (Salt Schedule unavailable)."
        )

    return ret


def magento_schedule_uninstall(site: str = "tank") -> Dict[str, Any]:
    """
    Remove Magento maintenance schedule / cron entries.
    """
    token = site.strip().lower().replace(" ", "_").replace("-", "_") or site
    cron_file = f"/etc/cron.d/magento-maintenance-{token}"
    legacy_cron_file = "/etc/cron.d/magento-maintenance"
    base_jobs = [
        f"magento_{token}_cron",
        f"magento_{token}_daily",
        f"magento_{token}_weekly",
        f"magento_{token}_monthly",
        f"magento_{token}_health",
    ]

    ret: Dict[str, Any] = {
        "site": site,
        "mode": "schedule" if _has_schedule() else "cron",
        "changes": {"schedule": {}, "cron_removed": False},
        "result": True,
        "comment": "",
    }

    expected_removed: List[str] = []
    for job in base_jobs:
        try:
            res = __salt__["schedule.delete"](job)
            ret["changes"]["schedule"][job] = res  # type: ignore[index]
            if res:
                expected_removed.append(job)
        except Exception:  # noqa: BLE001
            ret["changes"]["schedule"][job] = False  # type: ignore[index]

    config: Dict[str, Any] = __salt__["pillar.get"]("magento_schedule", {})  # type: ignore[assignment]

    dump_jobs_cfg = config.get("mysql_dump_jobs", []) or []
    if isinstance(dump_jobs_cfg, list):
        for job in dump_jobs_cfg:
            if not isinstance(job, dict):
                continue
            name = job.get("name")
            if not name:
                continue
            job_site = job.get("site")
            job_sites = job.get("sites")
            if job_site and job_site != site:
                continue
            if job_sites and site not in job_sites:
                continue
            try:
                res = __salt__["schedule.delete"](name)
                ret["changes"]["schedule"][name] = res  # type: ignore[index]
                if res:
                    expected_removed.append(name)
            except Exception:  # noqa: BLE001
                ret["changes"]["schedule"][name] = False  # type: ignore[index]

    api_watchers_cfg = config.get("api_watchers", []) or []
    if isinstance(api_watchers_cfg, list):
        for watcher in api_watchers_cfg:
            if not isinstance(watcher, dict):
                continue
            name = watcher.get("name")
            if not name:
                continue
            job_site = watcher.get("site")
            job_sites = watcher.get("sites")
            if job_site and job_site != site:
                continue
            if job_sites and site not in job_sites:
                continue
            try:
                res = __salt__["schedule.delete"](name)
                ret["changes"]["schedule"][name] = res  # type: ignore[index]
                if res:
                    expected_removed.append(name)
            except Exception:  # noqa: BLE001
                ret["changes"]["schedule"][name] = False  # type: ignore[index]

    stats_jobs_cfg = config.get("stats_jobs", []) or []
    if isinstance(stats_jobs_cfg, list):
        for stats_job in stats_jobs_cfg:
            if not isinstance(stats_job, dict):
                continue
            name = stats_job.get("name")
            if not name:
                continue
            job_site = stats_job.get("site")
            job_sites = stats_job.get("sites")
            if job_site and job_site != site:
                continue
            if job_sites and site not in job_sites:
                continue
            try:
                res = __salt__["schedule.delete"](name)
                ret["changes"]["schedule"][name] = res  # type: ignore[index]
                if res:
                    expected_removed.append(name)
            except Exception:  # noqa: BLE001
                ret["changes"]["schedule"][name] = False  # type: ignore[index]

    schedule_entries = _schedule_entries()

    if isinstance(schedule_entries, dict):
        for job_name, details in schedule_entries.items():
            if job_name in expected_removed:
                continue
            if not isinstance(details, dict):
                continue
            args = details.get("args") or details.get("job_args")
            command = ""
            if isinstance(args, list) and args:
                command = " ".join(str(item) for item in args)
            elif isinstance(args, str):
                command = args
            if not command:
                continue
            if (
                f"--site {site}" in command
                or f"/var/www/{site}" in command
                or (command.strip().startswith("saltgoat magetools xtrabackup mysql dump") and site in command)
            ):
                try:
                    res = __salt__["schedule.delete"](job_name)
                except Exception:  # noqa: BLE001
                    res = False
                ret["changes"]["schedule"][job_name] = res  # type: ignore[index]

    removed = False
    if __salt__["file.file_exists"](cron_file):
        __salt__["file.remove"](cron_file)
        removed = True
    if __salt__["file.file_exists"](legacy_cron_file):
        __salt__["file.remove"](legacy_cron_file)
        removed = True

    ret["changes"]["cron_removed"] = removed  # type: ignore[index]

    return ret


def enable_beacons() -> Dict[str, Any]:
    """
    Apply optional SaltGoat Beacon + Reactor states.
    """
    return {
        "beacons": __salt__["state.apply"]("optional.salt-beacons"),
        "reactor": __salt__["state.apply"]("optional.salt-reactor"),
    }


AUTOMATION_DEFAULT_BASE = "/srv/saltgoat/automation"
AUTOMATION_ALLOWED_BACKENDS = {"schedule", "cron"}


def _state_success(state_result: Dict[str, Any]) -> bool:
    if not isinstance(state_result, dict):
        return False
    for value in state_result.values():
        if isinstance(value, dict) and value.get("result") is False:
            return False
    return True


def _collect_state_comments(state_result: Dict[str, Any]) -> str:
    comments: List[str] = []
    if not isinstance(state_result, dict):
        return ""
    for value in state_result.values():
        if isinstance(value, dict):
            comment = value.get("comment")
            if comment:
                comments.append(str(comment))
    return " ".join(comments)


def _automation_paths(overrides: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    overrides = overrides or {}
    config: Dict[str, Any] = __salt__["config.get"]("saltgoat:automation", {})  # type: ignore[operator]

    base_dir = overrides.get("base_dir") or config.get("base_dir") or AUTOMATION_DEFAULT_BASE
    scripts_dir = overrides.get("scripts_dir") or config.get("scripts_dir") or os.path.join(base_dir, "scripts")
    jobs_dir = overrides.get("jobs_dir") or config.get("jobs_dir") or os.path.join(base_dir, "jobs")
    logs_dir = overrides.get("logs_dir") or config.get("logs_dir") or os.path.join(base_dir, "logs")

    owner = overrides.get("owner") or config.get("owner") or "root"
    group = overrides.get("group") or config.get("group") or owner

    dir_mode = overrides.get("dir_mode") or config.get("dir_mode") or "750"
    logs_mode = overrides.get("logs_mode") or config.get("logs_mode") or "750"
    script_mode = overrides.get("script_mode") or config.get("script_mode") or "755"
    job_file_mode = overrides.get("job_file_mode") or config.get("job_file_mode") or "640"
    cron_user = overrides.get("cron_user") or config.get("cron_user") or owner

    return {
        "base_dir": base_dir,
        "scripts_dir": scripts_dir,
        "jobs_dir": jobs_dir,
        "logs_dir": logs_dir,
        "owner": owner,
        "group": group,
        "dir_mode": dir_mode,
        "logs_mode": logs_mode,
        "script_mode": script_mode,
        "job_file_mode": job_file_mode,
        "cron_user": cron_user,
    }


def _automation_apply_init(paths: Dict[str, Any]) -> Dict[str, Any]:
    return __salt__["state.apply"](
        "optional.automation.init",
        pillar={
            "automation": {
                "base_dir": paths["base_dir"],
                "scripts_dir": paths["scripts_dir"],
                "jobs_dir": paths["jobs_dir"],
                "logs_dir": paths["logs_dir"],
                "owner": paths["owner"],
                "group": paths["group"],
                "mode": paths["dir_mode"],
                "logs_mode": paths["logs_mode"],
            }
        },
    )


def _automation_prepare(overrides: Optional[Dict[str, Any]] = None) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    paths = _automation_paths(overrides)
    init_state = _automation_apply_init(paths)
    return paths, init_state


def _apply_script_state(script_payload: Dict[str, Any], paths: Dict[str, Any]) -> Dict[str, Any]:
    return __salt__["state.apply"](
        "optional.automation.script",
        pillar={
            "automation": {
                "base_dir": paths["base_dir"],
                "scripts_dir": paths["scripts_dir"],
                "jobs_dir": paths["jobs_dir"],
                "logs_dir": paths["logs_dir"],
                "owner": paths["owner"],
                "group": paths["group"],
                "script": script_payload,
            }
        },
    )


def _apply_job_state(job_payload: Dict[str, Any], paths: Dict[str, Any]) -> Dict[str, Any]:
    return __salt__["state.apply"](
        "optional.automation.job",
        pillar={
            "automation": {
                "base_dir": paths["base_dir"],
                "scripts_dir": paths["scripts_dir"],
                "jobs_dir": paths["jobs_dir"],
                "logs_dir": paths["logs_dir"],
                "owner": paths["owner"],
                "group": paths["group"],
                "cron_user": paths["cron_user"],
                "job": job_payload,
            }
        },
    )


def _automation_script_body(name: str, logs_dir: str) -> str:
    timestamp = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    return f"""#!/bin/bash
# SaltGoat 自动化脚本: {name}
# 生成时间: {timestamp}

set -euo pipefail

SCRIPT_NAME="{name}"
LOG_DIR="{logs_dir}"
LOG_FILE="${{LOG_DIR}}/${{SCRIPT_NAME}}_$(date +%Y%m%d).log"

mkdir -p "$LOG_DIR"

log() {{
    local level="$1"
    shift
    printf '[%s] [%s] %s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" | tee -a "$LOG_FILE"
}}

log_info() {{
    log "INFO" "$@"
}}

log_error() {{
    log "ERROR" "$@"
}}

main() {{
    log_info "开始执行自动化脚本: $SCRIPT_NAME"
    # TODO: 在此处添加自动化任务逻辑
    # 示例: log_info "执行系统状态检查"; salt-call --local test.ping
    log_info "脚本执行完成: $SCRIPT_NAME"
}}

main "$@"
"""


def _job_file_path(name: str, paths: Dict[str, Any]) -> Path:
    return Path(paths["jobs_dir"]) / f"{name}.json"


def _load_job(name: str, paths: Dict[str, Any]) -> Dict[str, Any]:
    job_file = _job_file_path(name, paths)
    if not job_file.exists():
        raise FileNotFoundError(str(job_file))
    try:
        with job_file.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except json.JSONDecodeError as exc:  # pragma: no cover - defensive
        raise ValueError(f"无法解析任务配置: {job_file}") from exc


def _save_job_data(name: str, data: Dict[str, Any], paths: Dict[str, Any]) -> None:
    job_file = _job_file_path(name, paths)
    job_file.parent.mkdir(parents=True, exist_ok=True)
    with job_file.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def _resolve_backend(requested: Optional[str]) -> str:
    choice = (requested or "auto").lower()
    if choice == "auto":
        return "schedule" if _has_schedule() else "cron"
    if choice in AUTOMATION_ALLOWED_BACKENDS:
        if choice == "schedule" and not _has_schedule():
            return "cron"
        return choice
    return "cron"


def automation_init() -> Dict[str, Any]:
    """
    Ensure automation directories exist and return their resolved paths.
    """
    paths, init_state = _automation_prepare()
    return {
        "result": _state_success(init_state),
        "paths": paths,
        "changes": init_state,
        "comment": _collect_state_comments(init_state) or "自动化目录已准备就绪",
    }


def automation_script_create(
    name: str,
    overwrite: bool = False,
    body: Optional[str] = None,
) -> Dict[str, Any]:
    if not name:
        return {"result": False, "comment": "脚本名称不能为空"}

    paths, init_state = _automation_prepare()
    script_path = Path(paths["scripts_dir"]) / f"{name}.sh"

    script_payload = {
        "name": name,
        "path": str(script_path),
        "user": paths["owner"],
        "group": paths["group"],
        "mode": paths["script_mode"],
        "ensure": "present",
        "overwrite": overwrite,
        "body": body or _automation_script_body(name, paths["logs_dir"]),
    }

    script_state = _apply_script_state(script_payload, paths)
    success = _state_success(init_state) and _state_success(script_state)

    comments = " ".join(
        part
        for part in (
            _collect_state_comments(init_state),
            _collect_state_comments(script_state),
        )
        if part
    ) or "自动化脚本已创建"

    return {
        "result": success,
        "path": str(script_path),
        "changes": {"init": init_state, "script": script_state},
        "comment": comments,
        "exists": script_path.exists(),
    }


def automation_script_delete(name: str) -> Dict[str, Any]:
    if not name:
        return {"result": False, "comment": "脚本名称不能为空"}

    paths, init_state = _automation_prepare()
    script_payload = {
        "name": name,
        "ensure": "absent",
        "path": str(Path(paths["scripts_dir"]) / f"{name}.sh"),
    }

    script_state = _apply_script_state(script_payload, paths)
    success = _state_success(init_state) and _state_success(script_state)

    comments = " ".join(
        part
        for part in (
            _collect_state_comments(init_state),
            _collect_state_comments(script_state),
        )
        if part
    ) or "自动化脚本已移除"

    return {
        "result": success,
        "changes": {"init": init_state, "script": script_state},
        "comment": comments,
    }


def automation_script_list() -> Dict[str, Any]:
    paths = _automation_paths()
    scripts_dir = Path(paths["scripts_dir"])

    scripts: List[Dict[str, Any]] = []
    if scripts_dir.exists():
        for script in sorted(scripts_dir.glob("*.sh")):
            stat = script.stat()
            scripts.append(
                {
                    "name": script.stem,
                    "path": str(script),
                    "size": stat.st_size,
                    "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    "mode": format(stat.st_mode & 0o777, "04o"),
                }
            )

    return {
        "result": True,
        "scripts_dir": str(scripts_dir),
        "scripts": scripts,
    }


def automation_script_run(name: str, runas: Optional[str] = None) -> Dict[str, Any]:
    if not name:
        return {"result": False, "comment": "脚本名称不能为空"}

    paths, _ = _automation_prepare()
    script_path = Path(paths["scripts_dir"]) / f"{name}.sh"
    if not script_path.exists():
        return {"result": False, "comment": f"脚本不存在: {script_path}"}

    cmd = ["bash", str(script_path)]
    start = time.time()
    result = __salt__["cmd.run_all"](  # type: ignore[operator]
        cmd,
        runas=runas or paths["owner"],
        python_shell=False,
    )
    duration = time.time() - start
    success = result.get("retcode", 1) == 0

    return {
        "result": success,
        "stdout": result.get("stdout", ""),
        "stderr": result.get("stderr", ""),
        "retcode": result.get("retcode", 1),
        "duration": duration,
        "comment": f"脚本执行完成 (耗时 {duration:.2f}s)",
    }


def automation_job_create(
    name: str,
    cron: str,
    script: Optional[str] = None,
    backend: str = "auto",
    enabled: bool = False,
    comment: Optional[str] = None,
    splay: int = 0,
) -> Dict[str, Any]:
    if not name or not cron:
        return {"result": False, "comment": "任务名称与 Cron 表达式不能为空"}

    paths, init_state = _automation_prepare()
    script_name = script or name
    script_path = Path(paths["scripts_dir"]) / f"{script_name}.sh"
    script_exists = script_path.exists()

    resolved_backend = _resolve_backend(backend)
    timestamp = datetime.utcnow().isoformat()

    job_data: Dict[str, Any] = {
        "name": name,
        "cron": cron,
        "script_name": script_name,
        "script_path": str(script_path),
        "backend": resolved_backend,
        "enabled": bool(enabled),
        "created_at": timestamp,
        "updated_at": timestamp,
        "comment": comment or "",
        "splay": splay,
        "user": paths["owner"],
    }

    job_payload = {
        "name": name,
        "ensure": "present",
        "enabled": bool(enabled),
        "backend": resolved_backend,
        "cron": cron,
        "data": job_data,
    }

    job_state = _apply_job_state(job_payload, paths)
    success = _state_success(init_state) and _state_success(job_state)

    comments = [
        part
        for part in (
            _collect_state_comments(init_state),
            _collect_state_comments(job_state),
        )
        if part
    ]
    if not comments:
        comments.append("自动化任务已创建")
    if not script_exists:
        comments.append(f"脚本暂未找到: {script_path}")

    return {
        "result": success,
        "backend": resolved_backend,
        "job": job_data,
        "changes": {"init": init_state, "job": job_state},
        "comment": " ".join(comments),
        "script_missing": not script_exists,
    }


def automation_job_enable(name: str, backend: str = "auto") -> Dict[str, Any]:
    if not name:
        return {"result": False, "comment": "任务名称不能为空"}

    paths, init_state = _automation_prepare()
    try:
        job_data = _load_job(name, paths)
    except FileNotFoundError:
        return {"result": False, "comment": f"任务不存在: {name}"}
    except ValueError as exc:
        return {"result": False, "comment": str(exc)}

    resolved_backend = _resolve_backend(backend or job_data.get("backend"))
    job_data["backend"] = resolved_backend
    job_data["enabled"] = True
    job_data["updated_at"] = datetime.utcnow().isoformat()

    job_payload = {
        "name": name,
        "ensure": "present",
        "enabled": True,
        "backend": resolved_backend,
        "cron": job_data.get("cron", "0 * * * *"),
        "data": job_data,
    }

    job_state = _apply_job_state(job_payload, paths)
    success = _state_success(init_state) and _state_success(job_state)

    comments = " ".join(
        part
        for part in (
            _collect_state_comments(init_state),
            _collect_state_comments(job_state),
        )
        if part
    ) or "任务已启用"

    return {
        "result": success,
        "backend": resolved_backend,
        "job": job_data,
        "changes": {"init": init_state, "job": job_state},
        "comment": comments,
    }


def automation_job_disable(name: str) -> Dict[str, Any]:
    if not name:
        return {"result": False, "comment": "任务名称不能为空"}

    paths, init_state = _automation_prepare()
    try:
        job_data = _load_job(name, paths)
    except FileNotFoundError:
        return {"result": False, "comment": f"任务不存在: {name}"}
    except ValueError as exc:
        return {"result": False, "comment": str(exc)}

    job_data["enabled"] = False
    job_data["updated_at"] = datetime.utcnow().isoformat()

    job_payload = {
        "name": name,
        "ensure": "present",
        "enabled": False,
        "backend": job_data.get("backend", "cron"),
        "cron": job_data.get("cron", "0 * * * *"),
        "data": job_data,
    }

    job_state = _apply_job_state(job_payload, paths)
    success = _state_success(init_state) and _state_success(job_state)

    comments = " ".join(
        part
        for part in (
            _collect_state_comments(init_state),
            _collect_state_comments(job_state),
        )
        if part
    ) or "任务已禁用"

    return {
        "result": success,
        "backend": job_data.get("backend", "cron"),
        "job": job_data,
        "changes": {"init": init_state, "job": job_state},
        "comment": comments,
    }


def automation_job_delete(name: str) -> Dict[str, Any]:
    if not name:
        return {"result": False, "comment": "任务名称不能为空"}

    paths, init_state = _automation_prepare()
    job_payload = {
        "name": name,
        "ensure": "absent",
        "enabled": False,
        "backend": "cron",
        "cron": "* * * * *",
        "data": {"name": name},
    }

    job_state = _apply_job_state(job_payload, paths)
    success = _state_success(init_state) and _state_success(job_state)

    job_file = _job_file_path(name, paths)
    comments = " ".join(
        part
        for part in (
            _collect_state_comments(init_state),
            _collect_state_comments(job_state),
        )
        if part
    ) or "任务已删除"

    return {
        "result": success,
        "backend": job_payload["backend"],
        "removed": not job_file.exists(),
        "job_file": str(job_file),
        "changes": {"init": init_state, "job": job_state},
        "comment": comments,
    }


def automation_job_list() -> Dict[str, Any]:
    paths = _automation_paths()
    jobs_dir = Path(paths["jobs_dir"])

    schedule_jobs: Dict[str, Any] = {}
    if _has_schedule():
        try:
            schedule_jobs = __salt__["schedule.list"]()  # type: ignore[operator]
        except Exception:  # pragma: no cover - defensive
            schedule_jobs = {}

    jobs: List[Dict[str, Any]] = []
    if jobs_dir.exists():
        for job_file in sorted(jobs_dir.glob("*.json")):
            try:
                with job_file.open("r", encoding="utf-8") as handle:
                    data = json.load(handle)
            except Exception:  # pragma: no cover - defensive
                data = {}

            name = data.get("name") or job_file.stem
            backend = data.get("backend", "cron")
            enabled = bool(data.get("enabled", False))
            cron_expr = data.get("cron", "")
            script_path = data.get("script_path")
            script_missing = bool(script_path) and not Path(script_path).exists()

            if backend == "schedule":
                active = bool(schedule_jobs.get(name))
            else:
                cron_file = Path(f"/etc/cron.d/saltgoat-automation-{name}")
                active = cron_file.exists()

            jobs.append(
                {
                    "name": name,
                    "cron": cron_expr,
                    "backend": backend,
                    "enabled": enabled,
                    "active": active,
                    "script_path": script_path,
                    "script_missing": script_missing,
                    "job_file": str(job_file),
                    "last_run": data.get("last_run"),
                    "last_retcode": data.get("last_retcode"),
                }
            )

    return {
        "result": True,
        "jobs_dir": str(jobs_dir),
        "jobs": jobs,
    }


def automation_job_run(name: str) -> Dict[str, Any]:
    if not name:
        return {"result": False, "comment": "任务名称不能为空"}

    paths, _ = _automation_prepare()
    try:
        job_data = _load_job(name, paths)
    except FileNotFoundError:
        return {"result": False, "comment": f"任务不存在: {name}"}
    except ValueError as exc:
        return {"result": False, "comment": str(exc)}

    script_path = job_data.get("script_path") or str(
        Path(paths["scripts_dir"]) / f"{job_data.get('script_name', name)}.sh"
    )
    script_path_obj = Path(script_path)
    if not script_path_obj.exists():
        return {"result": False, "comment": f"任务脚本不存在: {script_path}"}

    log_dir = Path(paths["logs_dir"])
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / f"{name}_{datetime.utcnow():%Y%m%d}.log"

    cmd = ["bash", str(script_path_obj)]
    env = {str(k): str(v) for k, v in (job_data.get("env") or {}).items()}

    start_time = time.time()
    result = __salt__["cmd.run_all"](  # type: ignore[operator]
        cmd,
        runas=job_data.get("user") or paths["owner"],
        python_shell=False,
        env=env,
    )
    duration = time.time() - start_time

    timestamp = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    lines: List[str] = [
        f"[{timestamp}] [INFO] SaltGoat automation job '{name}' 执行",
        f"[INFO] Script: {script_path}",
    ]

    stdout = result.get("stdout", "")
    stderr = result.get("stderr", "")
    if stdout:
        lines.append("[STDOUT]")
        lines.extend(stdout.splitlines())
    if stderr:
        lines.append("[STDERR]")
        lines.extend(stderr.splitlines())

    lines.append(f"[INFO] Return code: {result.get('retcode', 1)}")
    lines.append(f"[INFO] Duration: {duration:.2f}s")
    lines.append("")

    with log_file.open("a", encoding="utf-8") as handle:
        handle.write("\n".join(lines))

    job_data["last_run"] = datetime.utcnow().isoformat()
    job_data["last_retcode"] = result.get("retcode", 1)
    job_data["last_duration"] = duration
    _save_job_data(name, job_data, paths)

    success = result.get("retcode", 1) == 0
    comment = f"任务执行完成，日志: {log_file}"

    return {
        "result": success,
        "stdout": stdout,
        "stderr": stderr,
        "retcode": result.get("retcode", 1),
        "duration": duration,
        "log_file": str(log_file),
        "comment": comment,
    }
