from __future__ import annotations

import html
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    import yaml  # type: ignore
except Exception:  # pragma: no cover - optional dependency
    yaml = None  # type: ignore

try:
    from salt.client import Caller  # type: ignore
except Exception:  # pragma: no cover - salt 环境不可用
    Caller = None  # type: ignore


_LEVELS = {
    "DEBUG": 0,
    "INFO": 1,
    "NOTICE": 2,
    "WARNING": 3,
    "ERROR": 4,
    "CRITICAL": 5,
}

_CALLER: Optional[Caller] = None
_CACHE: Optional[Dict[str, object]] = None
_TOPIC_CACHE: Optional[Dict[str, object]] = None
_TAG_RE = re.compile(r"<[^>]+>")
_MD_SPECIAL_RE = re.compile(r"([_\*\[\]\(\)~`>#+\-=|{}.!])")
# Telegram 话题完全来自 Pillar `telegram_topics`
QUEUE_DIR = Path("/var/log/saltgoat/notify-queue")
WEBHOOK_TIMEOUT = int(os.environ.get("SALTGOAT_WEBHOOK_TIMEOUT", "5"))
WEBHOOK_WORKERS = max(1, int(os.environ.get("SALTGOAT_WEBHOOK_WORKERS", "4")))
FALLBACK_NOTIFICATIONS_PATH = Path(
    os.environ.get(
        "SALTGOAT_NOTIFICATIONS_FILE",
        Path(__file__).resolve().parents[2] / "salt" / "pillar" / "notifications.sls",
    )
)
SKIP_PILLAR = os.environ.get("SALTGOAT_SKIP_PILLAR", "0") in {"1", "true", "True"}


def _topic_cache_paths() -> List[Path]:
    paths: List[Path] = []
    env_path = os.environ.get("SALTGOAT_TOPIC_CACHE")
    if env_path:
        paths.append(Path(env_path))
    paths.append(Path("/var/lib/saltgoat/telegram-topics.json"))
    try:
        home = Path.home()
    except Exception:
        home = None
    if home is not None:
        paths.append(home / ".saltgoat" / "telegram-topics.json")
    return paths


def _load_topic_cache() -> Dict[str, object]:
    global _TOPIC_CACHE
    if _TOPIC_CACHE is not None:
        return _TOPIC_CACHE
    merged: Dict[str, object] = {"entries": {}}
    for path in _topic_cache_paths():
        try:
            text = path.read_text(encoding="utf-8")
        except Exception:
            continue
        try:
            data = json.loads(text)
        except Exception:
            continue
        if isinstance(data, dict):
            entries = data.get("entries") if isinstance(data.get("entries"), dict) else None
            if entries is None and all(isinstance(v, dict) for v in data.values()):
                entries = data  # backwards compatibility
            if isinstance(entries, dict):
                merged["entries"].update(entries)
    _TOPIC_CACHE = merged
    return _TOPIC_CACHE


def _save_topic_cache() -> None:
    cache = _load_topic_cache()
    for path in _topic_cache_paths():
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")
        except Exception:
            continue
        else:
            break


def _topic_cache_key(chat_id: str, title: str) -> str:
    return f"{chat_id.strip()}::{title.strip()}".lower()


def _topic_cache_lookup(chat_id: str, title: str) -> Optional[int]:
    cache = _load_topic_cache()
    key = _topic_cache_key(chat_id, title)
    entry = cache.get("entries", {}).get(key)
    if isinstance(entry, dict):
        thread = entry.get("thread_id")
        if isinstance(thread, int):
            return thread
        try:
            return int(str(thread))
        except Exception:
            return None
    return None


def _topic_cache_store(chat_id: str, title: str, thread_id: int) -> None:
    cache = _load_topic_cache()
    key = _topic_cache_key(chat_id, title)
    cache.setdefault("entries", {})[key] = {
        "chat_id": chat_id,
        "title": title,
        "thread_id": int(thread_id),
        "updated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    _save_topic_cache()


def _load_yaml_dict(path: Path) -> Dict[str, Any]:
    if yaml is None:
        return {}
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        return {}
    try:
        data = yaml.safe_load(text)
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def _load_local_file(*relative_paths: str) -> Dict[str, Any]:
    base = Path(__file__).resolve().parents[2]
    for rel in relative_paths:
        candidate = base / rel
        data = _load_yaml_dict(candidate)
        if data:
            return data
    return {}


def _load_local_telegram_config() -> Dict[str, Any]:
    data = _load_local_file("salt/pillar/secret/telegram.sls", "salt/pillar/telegram.sls")
    if isinstance(data.get("telegram"), dict):
        return data["telegram"]
    return data


def _load_local_topics_config() -> Dict[str, Any]:
    data = _load_local_file("salt/pillar/secret/telegram-topics.sls", "salt/pillar/telegram-topics.sls")
    if isinstance(data.get("telegram_topics"), dict):
        return data["telegram_topics"]
    return data


def _collect_chat_ids(entry: Dict[str, Any]) -> List[str]:
    chat_ids: List[str] = []
    for key in ("targets", "chat_ids", "chat_id", "accept_from"):
        raw = entry.get(key)
        if raw is None:
            continue
        if isinstance(raw, list):
            items = raw
        else:
            items = [raw]
        for item in items:
            if isinstance(item, dict):
                candidate = item.get("chat_id") or item.get("chat") or item.get("id")
            else:
                candidate = item
            if candidate in (None, ""):
                continue
            chat_id = str(candidate)
            if chat_id not in chat_ids:
                chat_ids.append(chat_id)
    return chat_ids


def _load_telegram_profile_index() -> Tuple[Dict[str, Dict[str, Any]], Dict[str, Dict[str, Any]]]:
    telegram = pillar_get("telegram", {}) or {}
    if not isinstance(telegram, dict) or not telegram.get("profiles"):
        telegram = _load_local_telegram_config()
    profiles_cfg = telegram.get("profiles") if isinstance(telegram, dict) else None
    if not isinstance(profiles_cfg, dict):
        return {}, {}
    profiles: Dict[str, Dict[str, Any]] = {}
    chat_index: Dict[str, Dict[str, Any]] = {}
    for name, entry in profiles_cfg.items():
        if not isinstance(entry, dict):
            continue
        if not entry.get("enabled", True):
            continue
        token = entry.get("token")
        if not token:
            continue
        chats = _collect_chat_ids(entry)
        profiles[name] = {"token": token, "chats": chats}
        for chat_id in chats:
            if chat_id not in chat_index:
                chat_index[chat_id] = {"token": token, "profile": name}
    return profiles, chat_index


def _resolve_topic_target(entry: Dict[str, Any], chat_index: Dict[str, Dict[str, Any]], profiles: Dict[str, Dict[str, Any]]) -> Tuple[Optional[str], Optional[str]]:
    chat_id = entry.get("chat_id") or entry.get("chat") or entry.get("target")
    profile_name = entry.get("profile")
    if chat_id not in (None, ""):
        chat = str(chat_id)
        info = chat_index.get(chat)
        if info:
            return chat, info.get("token")
    if profile_name and profile_name in profiles:
        info = profiles[profile_name]
        chats = info.get("chats") or []
        chat = str(chats[0]) if chats else None
        return chat, info.get("token")
    if chat_index:
        chat, info = next(iter(chat_index.items()))
        return chat, info.get("token")
    if profiles:
        name, info = next(iter(profiles.items()))
        chats = info.get("chats") or []
        chat = str(chats[0]) if chats else None
        return chat, info.get("token")
    return None, None


def _create_forum_topic(token: str, chat_id: str, title: str, icon_color: Optional[Any] = None, icon_custom_emoji_id: Optional[Any] = None) -> Optional[int]:
    payload = {"chat_id": chat_id, "name": title}
    if icon_color not in (None, ""):
        try:
            payload["icon_color"] = int(icon_color)
        except Exception:
            pass
    if icon_custom_emoji_id not in (None, ""):
        payload["icon_custom_emoji_id"] = str(icon_custom_emoji_id)
    data = urllib.parse.urlencode(payload).encode()
    url = f"https://api.telegram.org/bot{token}/createForumTopic"
    req = urllib.request.Request(url, data=data)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as exc:  # pragma: no cover - network error path
        try:
            raw = exc.read()
        except Exception:
            return None
    except Exception:  # pragma: no cover - network error path
        return None
    try:
        response = json.loads(raw or b"{}")
    except Exception:
        return None
    if not isinstance(response, dict) or not response.get("ok"):
        return None
    result = response.get("result")
    if not isinstance(result, dict):
        return None
    thread = result.get("message_thread_id")
    if thread in (None, "", 0, "0"):
        return None
    try:
        return int(thread)
    except Exception:
        return None


def _extract_thread_id(value: Any) -> Optional[int]:
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value.strip())
        except Exception:
            return None
    if isinstance(value, dict):
        for key in ("thread_id", "topic_id", "id"):
            candidate = value.get(key)
            if candidate in (None, ""):
                continue
            try:
                return int(candidate)
            except Exception:
                continue
    return None


def _resolve_dynamic_thread(tag: str, value: Dict[str, Any], chat_index: Dict[str, Dict[str, Any]], profiles: Dict[str, Dict[str, Any]]) -> Optional[int]:
    title = value.get("title") or value.get("topic") or value.get("name") or tag
    if not title:
        return None
    chat_id, token = _resolve_topic_target(value, chat_index, profiles)
    if not chat_id or not token:
        return None
    cached = _topic_cache_lookup(chat_id, title)
    if cached:
        return cached
    thread = _create_forum_topic(token, chat_id, title, value.get("icon_color"), value.get("icon_custom_emoji_id"))
    if thread:
        _topic_cache_store(chat_id, title, thread)
    return thread


def _get_caller() -> Optional[Caller]:
    global _CALLER
    if Caller is None:
        return None
    if _CALLER is None:
        try:
            _CALLER = Caller()
        except Exception:
            return None
    return _CALLER


def pillar_get(path: str, default: object = None) -> object:
    if SKIP_PILLAR:
        return default
    caller = _get_caller()
    if caller is None:
        return default
    try:
        value = caller.cmd("pillar.get", path, default)
    except Exception:
        return default
    if value is None:
        return default
    return value


def level_value(name: str) -> int:
    return _LEVELS.get(str(name).upper(), _LEVELS["INFO"])


def _normalize_site(site: Optional[str]) -> Optional[str]:
    if not site:
        return None
    slug = site.strip().lower().replace(" ", "-").replace("/", "-")
    return slug or None


def load_config(reload: bool = False) -> Dict[str, object]:
    global _CACHE
    if _CACHE is not None and not reload:
        return _CACHE

    sentinel = object()
    data = pillar_get("notifications", sentinel)
    if data is sentinel or not isinstance(data, dict):
        data = {}
    if not data:
        data = _load_notifications_fallback()
    if not isinstance(data, dict):
        data = {}
    telegram = data.get("telegram", {}) if isinstance(data.get("telegram"), dict) else {}

    enabled = bool(telegram.get("enabled", True))
    min_level = str(telegram.get("min_severity", "INFO")).upper()
    parse_mode = telegram.get("parse_mode", "HTML")
    disabled_tags = telegram.get("disabled_tags", [])
    if isinstance(disabled_tags, (list, tuple, set)):
        disabled_tags = [str(tag) for tag in disabled_tags]
    else:
        disabled_tags = []

    site_overrides: Dict[str, Dict[str, object]] = {}
    overrides_raw = telegram.get("site_overrides", {})
    if isinstance(overrides_raw, dict):
        for site, rules in overrides_raw.items():
            if not isinstance(rules, dict):
                continue
            slug = _normalize_site(site)
            if not slug:
                continue
            override: Dict[str, object] = {
                "min_level": str(rules.get("min_severity", min_level)).upper(),
            }
            disabled = rules.get("disabled_tags", [])
            if isinstance(disabled, (list, tuple, set)):
                override["disabled_tags"] = [str(tag) for tag in disabled]
            site_overrides[slug] = override

    webhooks: List[Dict[str, object]] = []
    webhook_cfg = data.get("webhook", {})
    if isinstance(webhook_cfg, dict) and webhook_cfg.get("enabled", False):
        endpoints = webhook_cfg.get("endpoints", [])
        if isinstance(endpoints, list):
            for entry in endpoints:
                if not isinstance(entry, dict):
                    continue
                url = entry.get("url")
                if not url:
                    continue
                headers = entry.get("headers", {})
                if not isinstance(headers, dict):
                    headers = {}
                webhooks.append(
                    {
                        "name": entry.get("name") or url,
                        "url": url,
                        "headers": {str(k): str(v) for k, v in headers.items()},
                    }
                )

    _CACHE = {
        "enabled": enabled,
        "min_level": min_level,
        "min_level_value": level_value(min_level),
        "parse_mode": parse_mode,
        "disabled_tags": disabled_tags,
        "site_overrides": site_overrides,
        "webhooks": webhooks,
    }
    return _CACHE


def get_parse_mode() -> str:
    return str(load_config().get("parse_mode", "HTML"))


def queue_failure(destination: str, tag: str, payload: Dict[str, object], error: str | None = None, context: Optional[Dict[str, object]] = None) -> None:
    try:
        QUEUE_DIR.mkdir(parents=True, exist_ok=True)
        ctx = dict(context) if isinstance(context, dict) else {}
        record = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "destination": destination,
            "tag": tag,
            "payload": payload,
            "error": error,
            "context": ctx,
            "attempts": 0,
        }
        path = QUEUE_DIR / f"{int(time.time())}_{os.getpid()}.json"
        path.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception:
        pass


def _matches_disabled(tag: str, patterns: List[str]) -> bool:
    return any(tag.startswith(pattern) for pattern in patterns)


def should_send(tag: str, severity: str = "INFO", site: Optional[str] = None) -> bool:
    config = load_config()
    if not config.get("enabled", True):
        return False

    sev_value = level_value(severity)
    if sev_value < config.get("min_level_value", _LEVELS["INFO"]):
        return False

    disabled_global = config.get("disabled_tags", [])
    if isinstance(disabled_global, list) and _matches_disabled(tag, disabled_global):
        return False

    site_slug = _normalize_site(site)
    if site_slug is None:
        # attempt to infer from tag suffix
        parts = tag.split("/")
        if parts:
            site_slug = _normalize_site(parts[-1])

    overrides = config.get("site_overrides", {})
    if site_slug and site_slug in overrides:
        site_cfg = overrides[site_slug]
        min_level = site_cfg.get("min_level")
        if isinstance(min_level, str) and sev_value < level_value(min_level):
            return False
        disabled = site_cfg.get("disabled_tags", [])
        if isinstance(disabled, list) and _matches_disabled(tag, disabled):
            return False

    return True


def format_pre_block(title: str, subtitle: str, fields: List[Tuple[str, Optional[str]]]) -> Tuple[str, str]:
    entries: List[Tuple[str, str]] = []
    for label, value in fields:
        if value in (None, ""):
            continue
        entries.append((str(label), str(value)))
    underline = "=" * 30
    width = max((len(label) for label, _ in entries), default=8)
    lines = [underline, f"{title} ({subtitle})", underline]
    for label, value in entries:
        parts = value.splitlines() or [""]
        lines.append(f"{label.ljust(width)} : {parts[0]}")
        for extra in parts[1:]:
            lines.append(f"{' ' * width}   {extra}")
    plain = "\n".join(lines)
    return plain, f"<pre>{html.escape(plain)}</pre>"


def escape_markdown_v2(text: str) -> str:
    if not text:
        return ""
    escaped = text.replace("\\", "\\\\")
    return _MD_SPECIAL_RE.sub(r"\\\1", escaped)


def format_markdown_code(value: str) -> str:
    if value is None:
        value = ""
    escaped = value.replace("\\", "\\\\").replace("`", "\\`")
    return f"`{escaped}`"


def format_markdown_code_block(lines: List[str]) -> str:
    safe_lines: List[str] = []
    for line in lines:
        if line is None:
            line = ""
        safe_lines.append(line.replace("\\", "\\\\"))
    return "```\n" + "\n".join(safe_lines) + "\n```"


def html_to_plain(content: str) -> str:
    if not content:
        return ""
    return html.unescape(_TAG_RE.sub("", content))


def _load_notifications_fallback() -> Dict[str, object]:
    path = FALLBACK_NOTIFICATIONS_PATH
    if not path or not path.exists():
        return {}
    try:
        import yaml  # type: ignore
    except Exception:  # pragma: no cover - PyYAML 不可用
        yaml = None  # type: ignore
    try:
        raw = path.read_text(encoding="utf-8")
    except Exception:
        return {}
    if yaml is None:
        return {}
    try:
        data = yaml.safe_load(raw) or {}
    except Exception:
        return {}
    if not isinstance(data, dict):
        return {}
    return data.get("notifications", {}) or {}


def send_webhook_entry(entry: Dict[str, object], body: Dict[str, object], *, queue_on_failure: bool = True) -> bool:
    url = entry.get("url") if isinstance(entry, dict) else None
    if not url:
        return False
    data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(str(url), data=data, method="POST")
    headers = entry.get("headers") if isinstance(entry, dict) else None
    if isinstance(headers, dict):
        for key, value in headers.items():
            req.add_header(str(key), str(value))
    if "Content-Type" not in req.headers:
        req.add_header("Content-Type", "application/json; charset=utf-8")
    try:
        urllib.request.urlopen(req, timeout=WEBHOOK_TIMEOUT)  # nosec B310
        return True
    except Exception as exc:
        if queue_on_failure:
            queue_failure(
                "webhook",
                body.get("tag", ""),
                body,
                str(exc),
                {"url": entry.get("url"), "headers": entry.get("headers")},
            )
        return False


def dispatch_webhooks(
    tag: str,
    severity: str,
    site: Optional[str],
    plain_message: str,
    html_message: str,
    payload: Optional[Dict[str, object]] = None,
) -> int:
    config = load_config()
    endpoints = config.get("webhooks") or []
    if not endpoints:
        return 0
    body = {
        "tag": tag,
        "severity": severity,
        "site": site,
        "plain": plain_message,
        "html": html_message,
        "payload": payload or {},
        "text": plain_message,
    }
    max_workers = min(len(endpoints), WEBHOOK_WORKERS)
    results = []
    with ThreadPoolExecutor(max_workers=max_workers or 1) as executor:
        futures = [executor.submit(send_webhook_entry, entry, body) for entry in endpoints]
        for future in futures:
            results.append(bool(future.result()))
    return sum(1 for ok in results if ok)


@lru_cache
def _load_topics() -> Dict[str, int]:
    topics_raw = pillar_get("telegram_topics", {}) or {}
    if not isinstance(topics_raw, dict) or not topics_raw:
        topics_raw = _load_local_topics_config()
    profiles, chat_index = _load_telegram_profile_index()
    normalized: Dict[str, int] = {}
    if isinstance(topics_raw, dict):
        for key, value in topics_raw.items():
            if not key:
                continue
            thread = _extract_thread_id(value)
            if thread is not None:
                normalized[str(key)] = thread
                continue
            if isinstance(value, dict):
                thread = _resolve_dynamic_thread(str(key), value, chat_index, profiles)
                if thread is not None:
                    normalized[str(key)] = thread
    return normalized


def get_thread_id(tag: str) -> Optional[int]:
    topics = _load_topics()
    if not topics:
        return None
    if tag in topics:
        return topics[tag]
    parts = tag.split("/")
    while len(parts) > 1:
        parts = parts[:-1]
        candidate = "/".join(parts)
        if candidate in topics:
            return topics[candidate]
    return None
