#!/usr/bin/env python3
"""
Magento 2 schedule automation helper.

Provides list/auto operations for installing Salt Schedule jobs per detected site.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple

try:
    import yaml  # type: ignore
except Exception:  # pragma: no cover - PyYAML 可能未安装
    yaml = None

BASE_DIR = Path("/var/www")
CRON_DIR = Path("/etc/cron.d")
ENV = os.environ.copy()
ENV.setdefault("PYTHONWARNINGS", "ignore")


def log(level: str, message: str) -> None:
    print(f"[{level}] {message}")


def info(message: str) -> None:
    log("INFO", message)


def success(message: str) -> None:
    log("SUCCESS", message)


def warning(message: str) -> None:
    log("WARNING", message)


def error(message: str) -> None:
    log("ERROR", message)


def parse_json(payload: str) -> Dict[str, object]:
    start = payload.find("{")
    end = payload.rfind("}")
    if start == -1 or end == -1 or end <= start:
        return {}
    try:
        return json.loads(payload[start : end + 1])
    except json.JSONDecodeError:
        return {}


def run_salt(args: Sequence[str], json_out: bool = False) -> Tuple[int, str, str, Dict[str, object]]:
    cmd = ["sudo", "salt-call", "--local", "--log-level=quiet", *args]
    if json_out and "--out=json" not in cmd:
        cmd.append("--out=json")
    result = subprocess.run(
        cmd,
        text=True,
        capture_output=True,
        env=ENV,
    )
    parsed: Dict[str, object] = {}
    if json_out:
        parsed = parse_json(result.stdout)
    return result.returncode, result.stdout, result.stderr, parsed


@dataclass(frozen=True)
class SiteRecord:
    site: str
    root: Path

    @property
    def token(self) -> str:
        token = self.site.strip().lower().replace(" ", "_").replace("-", "_")
        return token or self.site

    @property
    def cron_paths(self) -> List[Path]:
        token = self.token
        specific = CRON_DIR / f"magento-maintenance-{token}"
        legacy = CRON_DIR / "magento-maintenance"
        return [specific, legacy]


def detect_sites() -> List[SiteRecord]:
    records: List[SiteRecord] = []
    if not BASE_DIR.exists():
        return records
    for entry in sorted(BASE_DIR.iterdir()):
        if not entry.is_dir():
            continue
        direct_root = entry
        direct_env = direct_root / "app/etc/env.php"
        direct_magento = direct_root / "bin/magento"
        if direct_env.is_file() and direct_magento.is_file():
            records.append(SiteRecord(site=entry.name, root=direct_root))
            continue
        rolling_root = entry / "current"
        rolling_env = rolling_root / "app/etc/env.php"
        rolling_magento = rolling_root / "bin/magento"
        if rolling_env.is_file() and rolling_magento.is_file():
            records.append(SiteRecord(site=f"{entry.name}/current", root=rolling_root))
    return records


def load_pillar_config() -> Dict[str, object]:
    _, stdout, _, parsed = run_salt(["pillar.get", "magento_schedule"], json_out=True)
    data = parsed.get("local")
    if isinstance(data, dict):
        return data
    # fallback: salt-call may return the raw value directly
    try:
        return json.loads(stdout)
    except Exception:
        return {}


def site_label(name: str) -> str:
    return name.replace("/", "-")


def _job_applies(job: Dict[str, object], site: str) -> bool:
    job_site = job.get("site")
    job_sites = job.get("sites")
    if job_site and job_site != site:
        return False
    if isinstance(job_sites, (list, tuple, set)) and site not in job_sites:
        return False
    return True


def expected_job_names(site: SiteRecord, config: Dict[str, object]) -> Set[str]:
    jobs: Set[str] = set()
    token = site.token
    label = site_label(site.site)
    jobs.update(
        {
            f"magento_{token}_cron",
            f"magento_{token}_daily",
            f"magento_{token}_weekly",
            f"magento_{token}_monthly",
            f"magento_{token}_health",
        }
    )

    dump_jobs = config.get("mysql_dump_jobs") if isinstance(config, dict) else None
    has_dump = False
    if isinstance(dump_jobs, list):
        for dump in dump_jobs:
            if not isinstance(dump, dict):
                continue
            name = dump.get("name")
            if not name or not _job_applies(dump, site.site):
                continue
            jobs.add(str(name))
            has_dump = True
    if not has_dump:
        jobs.add(f"{token}mage-dump-hourly")

    api_watchers = config.get("api_watchers")
    has_watcher = False
    if isinstance(api_watchers, list):
        for watcher in api_watchers:
            if not isinstance(watcher, dict):
                continue
            name = watcher.get("name")
            if not name or not _job_applies(watcher, site.site):
                continue
            jobs.add(str(name))
            has_watcher = True
    if not has_watcher:
        jobs.add(f"{label}-api-watch")

    stats_jobs = config.get("stats_jobs")
    has_stats = False
    if isinstance(stats_jobs, list):
        for stats_job in stats_jobs:
            if not isinstance(stats_job, dict):
                continue
            name = stats_job.get("name")
            if not name or not _job_applies(stats_job, site.site):
                continue
            jobs.add(str(name))
            has_stats = True
    if not has_stats:
        jobs.update(
            {
                f"{label}-stats-daily",
                f"{label}-stats-weekly",
                f"{label}-stats-monthly",
            }
        )

    return jobs


def parse_schedule_yaml(raw: str) -> Optional[Dict[str, object]]:
    if yaml is None:
        return None
    try:
        return yaml.safe_load(raw)
    except Exception:
        return None


def fetch_schedule_jobs() -> Dict[str, object]:
    _, stdout, _, parsed = run_salt(["schedule.list"], json_out=True)
    local = parsed.get("local") if isinstance(parsed, dict) else None
    if isinstance(local, dict):
        schedule = local.get("schedule")
        if isinstance(schedule, dict):
            return schedule
    if isinstance(local, str):
        parsed_yaml = parse_schedule_yaml(local)
        if isinstance(parsed_yaml, dict):
            schedule = parsed_yaml.get("schedule")
            if isinstance(schedule, dict):
                return schedule
    parsed_yaml = parse_schedule_yaml(stdout)
    if isinstance(parsed_yaml, dict):
        schedule = parsed_yaml.get("local")
        if isinstance(schedule, dict):
            schedule = schedule.get("schedule")
            if isinstance(schedule, dict):
                return schedule
    return {}


def show_list(
    sites: List[SiteRecord],
    config: Dict[str, object],
    schedule_map: Optional[Dict[str, object]] = None,
) -> int:
    if not sites:
        warning("未检测到任何 Magento 站点（检查 /var/www/* 下的 env.php / bin/magento）。")
        return 0
    if schedule_map is None:
        schedule_map = fetch_schedule_jobs()

    overall_missing = 0
    for record in sites:
        info(f"站点: {record.site} (路径: {record.root})")
        jobs = expected_job_names(record, config)
        if not jobs:
            warning("  无计划任务定义（Pillar `magento_schedule` 未配置额外任务）。")
        missing: List[str] = []
        for job in sorted(jobs):
            exists = isinstance(schedule_map.get(job), dict)
            if exists:
                success(f"  ✓ {job}")
            else:
                warning(f"  ✗ 缺失 {job}")
                missing.append(job)

        cron_present = []
        for cron_file in record.cron_paths:
            if cron_file.exists():
                cron_present.append(str(cron_file))
        if cron_present:
            info("  检测到 Cron 兜底配置: " + ", ".join(cron_present))
        if missing:
            overall_missing += 1
            warning(f"  共缺失 {len(missing)} 个 Salt Schedule 任务。")
        else:
            success("  Salt Schedule 任务已就绪。")
        print()

    if overall_missing == 0:
        success("所有已发现站点的 Salt Schedule 任务均已配置。")
    else:
        warning(f"{overall_missing} 个站点缺少 Salt Schedule 任务，可运行 'saltgoat magetools schedule auto' 修复。")
    return 0


def run_auto(
    sites: List[SiteRecord],
    config: Dict[str, object],
    schedule_map: Optional[Dict[str, object]] = None,
) -> int:
    if shutil.which("salt-call"):
        subprocess.run(
            ["sudo", "salt-call", "--local", "saltutil.sync_modules"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    if not sites:
        warning("未检测到任何 Magento 站点，自动安装已跳过。")
        return 0

    failures = 0
    cron_candidates: List[SiteRecord] = []
    results: List[str] = []

    for record in sites:
        info(f"处理站点: {record.site}")
        args = [f"saltgoat.magento_schedule_install", f"site={record.site}"]
        _, stdout, stderr, parsed = run_salt(args, json_out=True)
        local = parsed.get("local") if isinstance(parsed, dict) else None
        if not isinstance(local, dict):
            failures += 1
            error(f"  调用失败，输出: {stdout or stderr}")
            continue
        if not local.get("result", False):
            failures += 1
            comment = str(local.get("comment", "未知错误"))
            error(f"  安装失败: {comment}")
            continue
        mode = str(local.get("mode", "schedule"))
        comment = str(local.get("comment", "")).strip()
        if mode == "cron":
            cron_candidates.append(record)
            warning(f"  Salt Schedule 不可用，已回退至 Cron: {comment or '查看 /etc/cron.d/。'}")
        else:
            success("  Salt Schedule 安装/验证完成。")

        if comment:
            info(f"  备注: {comment}")
        results.append(record.site)

    print()
    success(f"已处理站点: {', '.join(results)}")
    refreshed_map = fetch_schedule_jobs()

    cron_confirmed = []
    for record in cron_candidates:
        jobs = expected_job_names(record, config)
        missing = [job for job in jobs if job not in refreshed_map]
        if missing:
            cron_confirmed.append(record.site)
        else:
            success(f"站点 {record.site} 的 Salt Schedule 实际存在，已忽略 Cron 回退提示。")

    if cron_confirmed:
        warning(f"{len(cron_confirmed)} 个站点因 Salt Schedule 不可用而使用 Cron 兜底: {', '.join(cron_confirmed)}。")
    if failures:
        error(f"{failures} 个站点安装失败，请检查日志后重试。")
        return 1

    info("重新检测 Salt Schedule 配置:")
    print()
    return show_list(sites, config, refreshed_map)


def ensure_sites_order(sites: Iterable[SiteRecord]) -> List[SiteRecord]:
    return sorted(sites, key=lambda rec: rec.site)


def main(argv: Sequence[str]) -> int:
    action = argv[1] if len(argv) > 1 else "list"
    if action not in {"list", "auto"}:
        error("Usage: saltgoat magetools schedule [list|auto]")
        return 1

    sites = ensure_sites_order(detect_sites())
    config = load_pillar_config()

    if action == "list":
        schedule_map = fetch_schedule_jobs()
        return show_list(sites, config, schedule_map)
    schedule_map = fetch_schedule_jobs()
    return run_auto(sites, config, schedule_map)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
