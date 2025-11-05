#!/usr/bin/env python3
"""Create per-site Telegram forum topics and map them in telegram.json."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Dict, Iterable, List, Tuple
import socket

try:
    import yaml  # type: ignore
except Exception:  # pragma: no cover - PyYAML may be missing
    yaml = None

REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = Path("/etc/saltgoat/telegram.json")
PILLAR_PATH = REPO_ROOT / "salt" / "pillar" / "magento-schedule.sls"
PILLAR_TOPICS_PATH = REPO_ROOT / "salt" / "pillar" / "telegram-topics.sls"
SITE_CATEGORIES: Dict[str, Tuple[str, str]] = {
    "orders": ("saltgoat/business/order/{site}", "{site}-orders"),
    "customers": ("saltgoat/business/customer/{site}", "{site}-customers"),
    "summary": ("saltgoat/business/summary/{site}", "{site}-summary"),
    "mysql-backup": ("saltgoat/backup/mysql_dump/{site}", "{site}-mysql-backup"),
    "restic-backup": ("saltgoat/backup/restic/{site}", "{site}-restic-backup"),
}

HOST_CATEGORIES: Dict[str, Tuple[str, str]] = {
    "resources": ("saltgoat/monitor/resources/{site}", "{site}-resources"),
    "autoscale": ("saltgoat/autoscale/{site}", "{site}-autoscale"),
    "doctor": ("saltgoat/doctor/{site}", "{site}-doctor"),
    "minio": ("saltgoat/storage/minio/{site}", "{site}-minio"),
}


def load_config() -> Dict[str, object]:
    if not CONFIG_PATH.exists():
        raise SystemExit(f"Config not found: {CONFIG_PATH}")
    try:
        return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:  # pragma: no cover - config corruption
        raise SystemExit(f"Failed to parse {CONFIG_PATH}: {exc}") from exc


def write_config(data: Dict[str, object]) -> None:
    CONFIG_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _normalize_site(site: str) -> str:
    return site.strip().lower().replace("/", "-")


def _is_valid_site_name(site: str) -> bool:
    slug = _normalize_site(site)
    return bool(slug) and not slug.startswith(".")


def _has_magento_root(path: Path) -> bool:
    direct = path / "app" / "etc" / "env.php"
    rolling = path / "current" / "app" / "etc" / "env.php"
    return direct.is_file() or rolling.is_file()


def detect_sites_from_pillar() -> List[str]:
    if not PILLAR_PATH.exists():
        return []
    raw_text = PILLAR_PATH.read_text(encoding="utf-8")
    if yaml is None:
        sites: List[str] = []
        for line in raw_text.splitlines():
            line = line.strip()
            if line.startswith("site:"):
                _, value = line.split(":", 1)
                value = value.strip().strip("'\"")
                if value and value not in sites:
                    sites.append(value)
        return sites
    try:
        data = yaml.safe_load(raw_text) or {}
    except Exception:
        return []
    schedule = data.get("magento_schedule") if isinstance(data, dict) else {}
    sites: List[str] = []
    if isinstance(schedule, dict):
        for key in ("stats_jobs", "mysql_dump_jobs", "api_watchers"):
            jobs = schedule.get(key)
            if not isinstance(jobs, list):
                continue
            for job in jobs:
                if not isinstance(job, dict):
                    continue
                site = job.get("site") or job.get("sites")
                if isinstance(site, str) and site not in sites:
                    sites.append(site)
                elif isinstance(site, (list, tuple, set)):
                    for entry in site:
                        if isinstance(entry, str) and entry not in sites:
                            sites.append(entry)
    return sites


def detect_sites() -> List[str]:
    sites = {site for site in detect_sites_from_pillar() if _is_valid_site_name(site)}
    base_dir = Path("/var/www")
    if base_dir.exists():
        for entry in base_dir.iterdir():
            if not entry.is_dir():
                continue
            if not _is_valid_site_name(entry.name):
                continue
            if _has_magento_root(entry):
                sites.add(entry.name)
    return sorted(_normalize_site(site) for site in sites if _is_valid_site_name(site))


def resolve_primary_profile(config: Dict[str, object], profile_name: str) -> Dict[str, object]:
    entries = config.get("entries")
    if isinstance(entries, list):
        for entry in entries:
            if isinstance(entry, dict) and entry.get("name") == profile_name:
                return entry
    raise SystemExit(f"Profile '{profile_name}' not found in {CONFIG_PATH}")


def resolve_chat_id(entry: Dict[str, object]) -> str:
    targets = entry.get("targets") or entry.get("chat_ids") or entry.get("chat_id") or []
    candidate: str | None = None
    if isinstance(targets, (list, tuple)):
        for item in targets:
            if isinstance(item, dict):
                chat = str(item.get("chat_id", ""))
            else:
                chat = str(item)
            if chat.startswith("-100"):
                return chat
            if chat and candidate is None:
                candidate = chat
    elif isinstance(targets, dict):
        chat = str(targets.get("chat_id", ""))
        if chat:
            return chat
    elif isinstance(targets, (str, int)):
        candidate = str(targets)
    if candidate:
        return candidate
    raise SystemExit("Unable to determine chat_id for Telegram profile")


def create_topic(token: str, chat_id: str, name: str, retries: int = 3) -> int:
    base = f"https://api.telegram.org/bot{token}/createForumTopic"
    params = urllib.parse.urlencode({"chat_id": chat_id, "name": name})
    url = f"{base}?{params}"
    attempt = 0
    while True:
        try:
            with urllib.request.urlopen(url, timeout=15) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            payload = exc.read().decode("utf-8")
            try:
                data = json.loads(payload)
            except json.JSONDecodeError:
                raise SystemExit(f"Failed to create topic '{name}': {payload}") from exc
            retry_after = (data.get("parameters") or {}).get("retry_after")
            if exc.code == 429 and retry_after and attempt < retries:
                wait_time = int(retry_after) + 1
                print(f"[INFO] Telegram rate limit hit; waiting {wait_time}s before retrying '{name}'")
                time.sleep(wait_time)
                attempt += 1
                continue
            if data.get("ok") and isinstance(data.get("result"), dict):
                thread_id = data["result"].get("message_thread_id")
                if thread_id is not None:
                    return int(thread_id)
            raise SystemExit(f"Telegram error creating topic '{name}': {data.get('description')}") from exc
        if not data.get("ok"):
            raise SystemExit(f"Telegram error creating topic '{name}': {data.get('description')}")
        result = data.get("result")
        if not isinstance(result, dict) or "message_thread_id" not in result:
            raise SystemExit(f"Unexpected response creating topic '{name}': {data}")
        return int(result["message_thread_id"])


def ensure_topics(config: Dict[str, object], profile: Dict[str, object], sites: Iterable[str], categories: Dict[str, Tuple[str, str]], dry_run: bool = False) -> bool:
    topics = profile.setdefault("topics", {})
    if not isinstance(topics, dict):
        topics = {}
        profile["topics"] = topics
    token = profile.get("token")
    if not token:
        raise SystemExit("Telegram profile missing bot token")
    chat_id = resolve_chat_id(profile)
    updated = False
    for site in sites:
        for _, (tag_template, topic_template) in categories.items():
            tag = tag_template.format(site=site)
            if tag in topics:
                continue
            topic_name = topic_template.format(site=site)
            print(f"[INFO] creating topic '{topic_name}' for tag '{tag}'")
            if dry_run:
                continue
            thread_id = create_topic(token, chat_id, topic_name)
            topics[tag] = thread_id
            updated = True
    return updated


def write_pillar_topics(profile: Dict[str, object], dry_run: bool = False) -> None:
    topics = profile.get("topics")
    if not isinstance(topics, dict) or not topics:
        return
    sorted_topics = dict(sorted(topics.items()))
    if yaml is not None:
        content = yaml.safe_dump({"telegram_topics": sorted_topics}, allow_unicode=True, sort_keys=True)
    else:
        lines = ["telegram_topics:"]
        for tag, thread in sorted_topics.items():
            lines.append(f"  '{tag}': {thread}")
        content = "\n".join(lines) + "\n"
    if dry_run:
        print(f"[INFO] dry-run: would write {PILLAR_TOPICS_PATH}\n{content}")
        return
    PILLAR_TOPICS_PATH.write_text(content, encoding="utf-8")
    print(f"[SUCCESS] {PILLAR_TOPICS_PATH} 已更新")


def main() -> None:
    parser = argparse.ArgumentParser(description="Setup Telegram topics per Magento site")
    parser.add_argument("--sites", help="逗号分隔的站点列表，未提供时自动探测")
    parser.add_argument("--profile", default="primary", help="telegram.json 内的 profile 名称 (默认 primary)")
    parser.add_argument("--dry-run", action="store_true", help="仅打印计划，不修改配置")
    args = parser.parse_args()

    if args.sites:
        sites = [_normalize_site(site) for site in args.sites.split(",") if site]
    else:
        sites = detect_sites()
    if not sites:
        print("[WARNING] 未检测到站点，跳过话题创建。")
        return

    config = load_config()
    profile = resolve_primary_profile(config, args.profile)
    categories = SITE_CATEGORIES
    updated = ensure_topics(config, profile, sites, categories, dry_run=args.dry_run)

    host_name = socket.getfqdn() or socket.gethostname()
    host_slug = _normalize_site(host_name)
    if host_slug:
        if ensure_topics(config, profile, [host_slug], HOST_CATEGORIES, dry_run=args.dry_run):
            updated = True

    if args.dry_run:
        if updated:
            print("[INFO] dry-run 模式，未写入配置。")
        else:
            print("[INFO] 已存在对应话题，无需更新。")
        write_pillar_topics(profile, dry_run=True)
    else:
        if updated:
            write_config(config)
            print("[SUCCESS] telegram.json 已更新")
        else:
            print("[INFO] 已存在对应话题，无需更新。")
        write_pillar_topics(profile, dry_run=False)


if __name__ == "__main__":
    main()
