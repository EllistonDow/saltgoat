"""SaltGoat custom runner helpers."""

from typing import Any, Dict, List, Optional

__virtualname__ = "saltgoat"


def __virtual__():
    return __virtualname__


def magento_schedule_install(site: str = "tank") -> Dict[str, Any]:
    """Apply the Magento maintenance schedule state for the given site."""
    return __salt__["state.apply"](
        "optional.magento-schedule",
        pillar={"site_name": site},
    )


def magento_schedule_uninstall(site: str = "tank") -> Dict[str, Any]:
    """Remove Magento maintenance schedules for the given site并清理历史 Cron 文件。"""
    result: Dict[str, Any] = {
        "schedule": {},
        "cron_removed": False,
    }

    schedule_jobs = [
        "magento-cron",
        "magento-daily-maintenance",
        "magento-weekly-maintenance",
        "magento-monthly-maintenance",
        "magento-health-check",
    ]
    for job in schedule_jobs:
        try:
            res = __salt__["schedule.delete"](job)
            result["schedule"][job] = res
        except Exception:  # noqa: BLE001
            result["schedule"][job] = False

    cron_file = "/etc/cron.d/magento-maintenance"
    if __salt__["file.file_exists"](cron_file):
        __salt__["file.remove"](cron_file)
        result["cron_removed"] = True

    return result


def enable_beacons() -> Dict[str, Any]:
    """Apply optional SaltGoat beacons and reactor configuration."""
    return {
        "beacons": __salt__["state.apply"]("optional.salt-beacons"),
        "reactor": __salt__["state.apply"]("optional.salt-reactor"),
    }


def _call_minions(
    function: str,
    tgt: str = "*",
    args: Optional[List[Any]] = None,
    kwargs: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Helper to invoke an execution module on targeted minions."""
    return __salt__["salt.cmd"](  # type: ignore[operator]
        tgt,
        function,
        args or [],
        kwargs or {},
    )


def automation_init(tgt: str = "*") -> Dict[str, Any]:
    """Run saltgoat.automation_init on targeted minions."""
    return _call_minions("saltgoat.automation_init", tgt=tgt)


def automation_script_create(
    name: str,
    tgt: str = "*",
    overwrite: bool = False,
) -> Dict[str, Any]:
    """Create an automation script on targeted minions."""
    return _call_minions(
        "saltgoat.automation_script_create",
        tgt=tgt,
        args=[name],
        kwargs={"overwrite": overwrite},
    )


def automation_script_delete(name: str, tgt: str = "*") -> Dict[str, Any]:
    """Remove an automation script from targeted minions."""
    return _call_minions(
        "saltgoat.automation_script_delete",
        tgt=tgt,
        args=[name],
    )


def automation_job_create(
    name: str,
    cron: str,
    script: Optional[str] = None,
    tgt: str = "*",
    backend: str = "auto",
    enabled: bool = False,
) -> Dict[str, Any]:
    """Create an automation job on targeted minions."""
    return _call_minions(
        "saltgoat.automation_job_create",
        tgt=tgt,
        args=[name, cron],
        kwargs={
            "script": script,
            "backend": backend,
            "enabled": enabled,
        },
    )


def automation_job_enable(
    name: str,
    tgt: str = "*",
    backend: str = "auto",
) -> Dict[str, Any]:
    """Enable an automation job on targeted minions."""
    return _call_minions(
        "saltgoat.automation_job_enable",
        tgt=tgt,
        args=[name],
        kwargs={"backend": backend},
    )


def automation_job_disable(name: str, tgt: str = "*") -> Dict[str, Any]:
    """Disable an automation job on targeted minions."""
    return _call_minions(
        "saltgoat.automation_job_disable",
        tgt=tgt,
        args=[name],
    )


def automation_job_delete(name: str, tgt: str = "*") -> Dict[str, Any]:
    """Delete an automation job on targeted minions."""
    return _call_minions(
        "saltgoat.automation_job_delete",
        tgt=tgt,
        args=[name],
    )


def automation_job_list(tgt: str = "*") -> Dict[str, Any]:
    """List automation jobs on targeted minions."""
    return _call_minions(
        "saltgoat.automation_job_list",
        tgt=tgt,
    )
