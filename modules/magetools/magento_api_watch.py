#!/usr/bin/env python3
"""
Magento API watcher: polls recent orders/customers and emits Salt events + Telegram notifications.
"""

import argparse
import base64
import binascii
import hashlib
import hmac
import json
import os
import random
import string
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple
import html
try:
    import yaml  # type: ignore
except Exception:  # pragma: no cover
    yaml = None  # type: ignore

try:
    from salt.client import Caller  # type: ignore
except Exception as exc:  # pragma: no cover - salt not available in tests
    print(f"[ERROR] Magento API watcher requires salt client libraries: {exc}", file=sys.stderr)
    sys.exit(2)


LOG = lambda msg: print(msg, file=sys.stderr)

STATE_ROOT = Path("/var/lib/saltgoat/magento-watcher")
REPO_ROOT = Path(__file__).resolve().parents[2]
SECRET_DIR = REPO_ROOT / "salt" / "pillar" / "secret"
LOGGER_SCRIPT = Path("/opt/saltgoat-reactor/logger.py")
TELEGRAM_COMMON = Path("/opt/saltgoat-reactor/reactor_common.py")
TELEGRAM_CONFIG = Path("/etc/saltgoat/telegram.json")
ALERT_LOG = Path("/var/log/saltgoat/alerts.log")
TEST_MODE = os.environ.get("MAGENTO_WATCHER_TEST_MODE") == "1"
RECENT_IDS_LIMIT = 256
ADMIN_TOKEN_CACHE_FILE = "admin_token.json"
ADMIN_TOKEN_EXPIRY_BUFFER = 300

sys.path.insert(0, str(REPO_ROOT))
from modules.lib import notification as notif  # type: ignore

def safe_exists(path: Path) -> bool:
    try:
        path.stat()
        return True
    except FileNotFoundError:
        return False
    except PermissionError:
        LOG(f"[WARNING] 无法访问 {path} (权限不足)，跳过 Telegram 推送。")
        return False
    except Exception as exc:
        LOG(f"[WARNING] 检查 {path} 失败: {exc}")
        return False


if TEST_MODE:
    TELEGRAM_AVAILABLE = False
else:
    TELEGRAM_AVAILABLE = all(
        [
            safe_exists(TELEGRAM_COMMON),
            safe_exists(LOGGER_SCRIPT),
            safe_exists(TELEGRAM_CONFIG),
        ]
    )
    if TELEGRAM_AVAILABLE:
        sys.path.insert(0, str(TELEGRAM_COMMON.parent))
        try:
            import reactor_common  # type: ignore
        except Exception as exc:  # pragma: no cover
            LOG(f"[WARNING] 无法导入 reactor_common: {exc}")
            TELEGRAM_AVAILABLE = False


def _admin_token_cache_path(site: str) -> Path:
    site_dir = STATE_ROOT / site
    site_dir.mkdir(parents=True, exist_ok=True)
    return site_dir / ADMIN_TOKEN_CACHE_FILE


def _decode_jwt_expiry(token: str) -> Optional[int]:
    parts = token.split(".")
    if len(parts) != 3:
        return None
    payload_b64 = parts[1]
    padding = "=" * (-len(payload_b64) % 4)
    try:
        payload_raw = base64.urlsafe_b64decode((payload_b64 + padding).encode("ascii"))
        payload = json.loads(payload_raw.decode("utf-8"))
    except (binascii.Error, ValueError, json.JSONDecodeError):
        return None
    exp = payload.get("exp")
    if isinstance(exp, (int, float)):
        return int(exp)
    return None


def _load_cached_admin_token(site: str) -> Optional[str]:
    path = _admin_token_cache_path(site)
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    token = data.get("token")
    if not token or not isinstance(token, str):
        return None
    expires_at = data.get("exp")
    if isinstance(expires_at, (int, float)):
        if time.time() >= float(expires_at) - ADMIN_TOKEN_EXPIRY_BUFFER:
            return None
    return token


def _save_cached_admin_token(site: str, token: str) -> None:
    path = _admin_token_cache_path(site)
    payload: Dict[str, Any] = {"token": token}
    exp = _decode_jwt_expiry(token)
    if exp:
        payload["exp"] = exp
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


def obtain_admin_token(site: str, base_url: str, username: str, password: str, force_refresh: bool = False) -> str:
    if not force_refresh:
        cached = _load_cached_admin_token(site)
        if cached:
            return cached
    token_url = base_url.rstrip("/") + "/rest/V1/integration/admin/token"
    body = json.dumps({"username": username, "password": password}).encode("utf-8")
    req = urllib.request.Request(token_url, data=body, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:  # nosec
            charset = resp.headers.get_content_charset() or "utf-8"
            raw = resp.read().decode(charset, errors="replace")
    except urllib.error.HTTPError as exc:
        raise MagentoAPIError(f"获取 admin token 失败: HTTP {exc.code} {exc.reason}") from exc
    except urllib.error.URLError as exc:
        raise MagentoAPIError(f"获取 admin token 失败: {exc.reason}") from exc
    except Exception as exc:
        raise MagentoAPIError(f"获取 admin token 失败: {exc}") from exc
    token: Optional[str] = None
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, str) and parsed:
            token = parsed
    except json.JSONDecodeError:
        pass
    if not token:
        stripped = raw.strip().strip('"')
        token = stripped if stripped else None
    if not token:
        raise MagentoAPIError("获取 admin token 失败: 响应为空")
    _save_cached_admin_token(site, token)
    return token


class MagentoAPIError(Exception):
    """Raised when Magento API requests fail."""

    def __init__(self, message: str, body: Optional[str] = None):
        super().__init__(message)
        self.body = body


class OAuth1Signer:
    """Minimal OAuth1 (HMAC-SHA1) signer for Magento REST API."""

    def __init__(self, consumer_key: str, consumer_secret: str, token: str, token_secret: str):
        self.consumer_key = consumer_key
        self.consumer_secret = consumer_secret
        self.token = token
        self.token_secret = token_secret
        self._random = random.SystemRandom()

    @staticmethod
    def _percent_encode(value: Any) -> str:
        return urllib.parse.quote(str(value), safe="~-._")

    @staticmethod
    def _normalize_url(url: str) -> str:
        parsed = urllib.parse.urlsplit(url)
        scheme = parsed.scheme.lower()
        hostname = (parsed.hostname or "").lower()
        port = parsed.port

        if port is None:
            netloc = hostname
        elif (scheme == "http" and port == 80) or (scheme == "https" and port == 443):
            netloc = hostname
        else:
            netloc = f"{hostname}:{port}"

        path = parsed.path or "/"
        return f"{scheme}://{netloc}{path}"

    def _base_params(
        self,
        params: List[Tuple[str, str]],
        oauth_params: Dict[str, str],
    ) -> List[Tuple[str, str]]:
        combined: List[Tuple[str, str]] = []
        combined.extend(params)
        combined.extend(oauth_params.items())
        encoded = [
            (self._percent_encode(k), self._percent_encode(v))
            for k, v in combined
        ]
        encoded.sort()
        return encoded

    def _signature(
        self,
        method: str,
        url: str,
        params: List[Tuple[str, str]],
        oauth_params: Dict[str, str],
    ) -> str:
        normalized_params = self._base_params(params, oauth_params)
        parameter_string = "&".join(f"{k}={v}" for k, v in normalized_params)
        base_elems = [
            self._percent_encode(method.upper()),
            self._percent_encode(self._normalize_url(url)),
            self._percent_encode(parameter_string),
        ]
        base_string = "&".join(base_elems)
        signing_key = "&".join(
            [
                self._percent_encode(self.consumer_secret),
                self._percent_encode(self.token_secret),
            ]
        )
        digest = hmac.new(signing_key.encode("utf-8"), base_string.encode("utf-8"), hashlib.sha1).digest()
        return base64.b64encode(digest).decode("utf-8")

    def build_authorization_header(self, method: str, url: str, params: List[Tuple[str, str]]) -> str:
        oauth_params: Dict[str, str] = {
            "oauth_consumer_key": self.consumer_key,
            "oauth_token": self.token,
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_timestamp": str(int(time.time())),
            "oauth_nonce": "".join(self._random.choice(string.ascii_letters + string.digits) for _ in range(16)),
            "oauth_version": "1.0",
        }
        oauth_params["oauth_signature"] = self._signature(method, url, params, oauth_params)

        ordered_keys = [
            "oauth_consumer_key",
            "oauth_token",
            "oauth_signature_method",
            "oauth_timestamp",
            "oauth_nonce",
            "oauth_version",
            "oauth_signature",
        ]
        header_items = [
            f'{self._percent_encode(k)}="{self._percent_encode(oauth_params[k])}"' for k in ordered_keys
        ]
        return "OAuth " + ", ".join(header_items)

def ensure_root() -> None:
    if os.geteuid() != 0:  # type: ignore[attr-defined]
        print(
            "[ERROR] Magento API 工具需要 root 权限，请使用 'sudo saltgoat magetools <command> ...'",
            file=sys.stderr,
        )
        sys.exit(1)


if TEST_MODE:

    class _DummyCaller:
        def cmd(self, *_args: Any, **_kwargs: Any) -> Any:
            return {}

    CALLER = _DummyCaller()  # type: ignore[assignment]
else:
    ensure_root()
    CALLER = Caller()


def pillar_get(path: str, default: Any = "") -> Any:
    value = CALLER.cmd("pillar.get", path, default)
    return value if value is not None else default


def load_local_secret(site: str) -> Dict[str, Any]:
    if yaml is None:
        return {}
    if not SECRET_DIR.exists():
        return {}
    merged: Dict[str, Any] = {}
    for path in sorted(SECRET_DIR.glob("*.sls")):
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except Exception:
            continue
        secrets = data.get("secrets")
        if not isinstance(secrets, dict):
            continue
        magento_api = secrets.get("magento_api")
        if isinstance(magento_api, dict):
            merged.update(magento_api)
    entry = merged.get(site)
    return entry if isinstance(entry, dict) else {}


def emit_event(tag: str, data: Dict[str, Any]) -> None:
    try:
        CALLER.cmd("event.send", tag, data)
    except Exception as exc:  # pragma: no cover
        LOG(f"[WARNING] event.send 失败 ({tag}): {exc}")


def log_to_file(label: str, tag: str, payload: Dict[str, Any]) -> None:
    if not LOGGER_SCRIPT.exists():
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
    except Exception:  # pragma: no cover
        pass


def telegram_broadcast(tag: str, message: str, payload: Dict[str, Any]) -> None:
    severity = str(payload.get("severity", "INFO")).upper()
    payload["severity"] = severity
    site_hint = payload.get("site") or payload.get("site_slug")
    if not notif.should_send(tag, severity, site_hint):
        log_to_file(
            "TELEGRAM",
            f"{tag} skip",
            {
                "reason": "filtered",
                "severity": severity,
                "site": site_hint,
            },
        )
        return

    if not TELEGRAM_AVAILABLE:
        return

    def _log(label: str, extra: Dict[str, Any]) -> None:
        log_to_file("TELEGRAM", f"{tag} {label}", extra)

    try:
        profiles = reactor_common.load_telegram_profiles(str(TELEGRAM_CONFIG), _log)
    except Exception as exc:  # pragma: no cover
        log_to_file("TELEGRAM", f"{tag} error", {"message": str(exc)})
        return

    if not profiles:
        _log("skip", {"reason": "no_profiles"})
        return

    _log("profile_summary", {"count": len(profiles)})
    thread_id = payload.get("telegram_thread")
    parse_mode = notif.get_parse_mode()
    try:
        reactor_common.broadcast_telegram(
            message,
            profiles,
            _log,
            tag=tag,
            thread_id=thread_id,
            parse_mode=parse_mode,
        )
    except Exception as exc:  # pragma: no cover
        _log("error", {"message": str(exc)})


def build_message(kind: str, site: str, payload: Dict[str, Any]) -> str:
    def format_block(title: str, subtitle: str, fields: List[Tuple[str, Optional[str]]]) -> str:
        _, html_block = notif.format_pre_block(title, subtitle, fields)
        return html_block

    site_label = site.upper()
    if kind == "order":
        fields = [
            ("Order", payload.get("order")),
            ("Total", payload.get("total")),
            ("Status", payload.get("status")),
            ("Customer", payload.get("customer")),
            ("Email", payload.get("email")),
            ("Created", payload.get("created_at")),
        ]
        return format_block("NEW ORDER", site_label, fields)
    elif kind == "customer":
        fields = [
            ("Name", payload.get("customer")),
            ("Email", payload.get("email")),
            ("ID", payload.get("id")),
            ("Group", payload.get("customer_group")),
            ("Created", payload.get("created_at")),
        ]
        return format_block("NEW CUSTOMER", site_label, fields)
    else:
        fields = [(key.title(), str(value)) for key, value in payload.items()]
        return format_block(kind.upper(), site_label, fields)


class MagentoWatcher:
    def __init__(
        self,
        site: str,
        base_url: str,
        token: str,
        kinds: List[str],
        page_size: int = 50,
        auth_mode: str = "bearer",
        oauth_params: Optional[Dict[str, str]] = None,
        max_pages: int = 25,
    ):
        self.site = site
        self.site_topic = site.replace("/", "-").lower()
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.kinds = kinds
        self.page_size = page_size
        self.auth_mode = auth_mode
        self.oauth_params = oauth_params or {}
        self.max_pages = max_pages
        self.oauth_signer: Optional[OAuth1Signer] = None
        if self.auth_mode == "oauth1":
            consumer_key = self.oauth_params.get("consumer_key") or self.oauth_params.get("client_key")
            consumer_secret = self.oauth_params.get("consumer_secret") or self.oauth_params.get("client_secret")
            access_token = (
                self.oauth_params.get("access_token")
                or self.oauth_params.get("oauth_token")
                or self.oauth_params.get("token")
                or token
            )
            token_secret = (
                self.oauth_params.get("access_token_secret")
                or self.oauth_params.get("oauth_token_secret")
                or self.oauth_params.get("token_secret")
            )
            missing = [
                name
                for name, value in [
                    ("consumer_key", consumer_key),
                    ("consumer_secret", consumer_secret),
                    ("access_token", access_token),
                    ("access_token_secret", token_secret),
                ]
                if not value
            ]
            if missing:
                raise ValueError(f"缺少 OAuth1 凭据: {', '.join(missing)}")
            self.token = access_token  # 便于日志与后续扩展复用
            self.oauth_signer = OAuth1Signer(
                consumer_key=str(consumer_key),
                consumer_secret=str(consumer_secret),
                token=str(access_token),
                token_secret=str(token_secret),
            )
        self.state_dir = STATE_ROOT / site
        self.state_dir.mkdir(parents=True, exist_ok=True)

    @staticmethod
    def _normalize_params(params: Dict[str, Any]) -> List[Tuple[str, str]]:
        items: List[Tuple[str, str]] = []
        for key, value in params.items():
            if isinstance(value, (list, tuple)):
                for inner in value:
                    items.append((key, str(inner)))
            else:
                items.append((key, str(value)))
        return items

    def _build_url(self, path: str) -> str:
        if path.startswith("http://") or path.startswith("https://"):
            return path
        return f"{self.base_url}{path}"

    def _apply_auth(self, req: urllib.request.Request, method: str, url: str, params: List[Tuple[str, str]]) -> None:
        req.add_header("Content-Type", "application/json")
        if self.auth_mode == "bearer":
            if not self.token:
                raise MagentoAPIError("缺少 Magento API token")
            req.add_header("Authorization", f"Bearer {self.token}")
        elif self.auth_mode == "oauth1":
            if not self.oauth_signer:
                raise MagentoAPIError("未初始化 OAuth1 签名器")
            header = self.oauth_signer.build_authorization_header(method, url, params)
            req.add_header("Authorization", header)
        else:
            raise MagentoAPIError(f"不支持的认证模式: {self.auth_mode}")

    def _request(self, path: str, params: Dict[str, Any]) -> Dict[str, Any]:
        query_items = self._normalize_params(params)
        base_url = self._build_url(path)
        query_string = urllib.parse.urlencode(query_items)
        url = f"{base_url}?{query_string}" if query_string else base_url
        req = urllib.request.Request(url)
        self._apply_auth(req, "GET", base_url, query_items)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:  # nosec
                charset = resp.headers.get_content_charset() or "utf-8"
                data = resp.read().decode(charset, errors="replace")
        except urllib.error.HTTPError as exc:
            body = ""
            try:
                body = exc.read().decode("utf-8", errors="ignore")
            except Exception:
                pass
            raise MagentoAPIError(f"HTTP {exc.code} {exc.reason}", body) from exc
        except urllib.error.URLError as exc:
            raise MagentoAPIError(f"URL error: {exc.reason}") from exc
        except Exception as exc:
            raise MagentoAPIError(f"HTTP request failed: {exc}") from exc

        try:
            return json.loads(data)
        except json.JSONDecodeError as exc:
            raise MagentoAPIError(f"Invalid JSON payload: {exc}", data) from exc

    def _log_api_error(self, kind: str, exc: MagentoAPIError) -> None:
        body_suffix = ""
        if exc.body:
            snippet = exc.body.strip()
            if len(snippet) > 200:
                snippet = snippet[:200] + "..."
            body_suffix = f" Body: {snippet}"
        LOG(f"[ERROR] {self.site} 获取 {kind} 失败: {exc}{body_suffix}")

    def _collect_entities(
        self,
        kind: str,
        endpoint: str,
        id_field: str,
        filter_field: Optional[str] = None,
        sort_field: Optional[str] = None,
    ) -> Dict[str, Any]:
        filter_field = filter_field or id_field
        last_id = self._load_last_id(kind)
        if last_id <= 0:
            baseline = self._bootstrap_last_id(
                kind,
                endpoint,
                id_field,
                sort_field or id_field,
                filter_field,
            )
            if baseline > 0:
                return {
                    "bootstrap": True,
                    "skip_processing": True,
                    "items": [],
                    "max_id": baseline,
                    "last_id": baseline,
                    "truncated": False,
                }
            last_id = 0
        bootstrap = last_id == 0

        order_field = sort_field or id_field
        base_params: Dict[str, Any] = {
            "searchCriteria[filter_groups][0][filters][0][field]": filter_field,
            "searchCriteria[filter_groups][0][filters][0][value]": last_id,
            "searchCriteria[filter_groups][0][filters][0][condition_type]": "gt",
            "searchCriteria[sortOrders][0][field]": order_field,
            "searchCriteria[sortOrders][0][direction]": "ASC",
            "searchCriteria[pageSize]": self.page_size,
        }

        collected: List[Dict[str, Any]] = []
        seen_ids: set[int] = set()
        max_id = last_id
        page = 1
        truncated = False
        stalled_rounds = 0

        while True:
            if page > self.max_pages:
                truncated = True
                LOG(
                    f"[WARNING] {self.site} {kind} 超过 {self.max_pages} 页阈值，仅处理前 {self.max_pages * self.page_size} 条记录。"
                )
                break

            params = dict(base_params)
            params["searchCriteria[current_page]"] = page
            try:
                payload = self._request(endpoint, params)
            except MagentoAPIError as exc:
                self._log_api_error(kind, exc)
                break
            except Exception as exc:  # pragma: no cover
                LOG(f"[ERROR] {self.site} 获取 {kind} 失败: {exc}")
                break

            items = payload.get("items", [])
            if not isinstance(items, list) or not items:
                break

            page_new: List[Dict[str, Any]] = []
            for item in items:
                raw_id = item.get(id_field, item.get("entity_id"))
                try:
                    entity_id = int(raw_id)
                except (TypeError, ValueError):
                    continue
                if entity_id in seen_ids:
                    continue
                seen_ids.add(entity_id)
                if entity_id > max_id:
                    max_id = entity_id
                if entity_id > last_id:
                    page_new.append(item)

            collected.extend(page_new)

            if bootstrap:
                break

            if len(items) < self.page_size:
                break

            if not page_new:
                stalled_rounds += 1
            else:
                stalled_rounds = 0

            if stalled_rounds >= 2:
                LOG(f"[WARNING] {self.site} {kind} 连续无新记录，提前结束。")
                break

            page += 1

        return {
            "bootstrap": bootstrap,
            "skip_processing": False,
            "items": collected,
            "max_id": max_id,
            "last_id": last_id,
            "truncated": truncated,
        }

    def _state_file(self, kind: str) -> Path:
        return self.state_dir / f"last_{kind}.json"

    def _load_state(self, kind: str) -> Dict[str, Any]:
        default = {"last_id": 0, "recent_ids": []}
        path = self._state_file(kind)
        if not path.exists():
            return default
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return default
        state = {
            "last_id": 0,
            "recent_ids": [],
        }
        try:
            state["last_id"] = int(data.get("last_id", 0))
        except Exception:
            state["last_id"] = 0
        recent_ids: List[int] = []
        raw_recent = data.get("recent_ids", [])
        if isinstance(raw_recent, list):
            for entry in raw_recent:
                try:
                    recent_ids.append(int(entry))
                except (TypeError, ValueError):
                    continue
        state["recent_ids"] = recent_ids[-RECENT_IDS_LIMIT:]
        return state

    def _load_last_id(self, kind: str) -> int:
        state = self._load_state(kind)
        try:
            return int(state.get("last_id", 0))
        except Exception:
            return 0

    def _save_state(self, kind: str, state: Dict[str, Any]) -> None:
        path = self._state_file(kind)
        recent_ids: List[int] = []
        for entry in state.get("recent_ids", []):
            try:
                recent_ids.append(int(entry))
            except (TypeError, ValueError):
                continue
        payload = {
            "last_id": int(state.get("last_id", 0)),
            "recent_ids": recent_ids[-RECENT_IDS_LIMIT:],
        }
        path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

    def _save_last_id(
        self,
        kind: str,
        last_id: int,
        new_ids: Optional[List[int]] = None,
        state: Optional[Dict[str, Any]] = None,
    ) -> None:
        self._update_state(kind, last_id, new_ids or [], state=state)

    def _update_state(
        self,
        kind: str,
        last_id: int,
        new_ids: Optional[List[int]] = None,
        state: Optional[Dict[str, Any]] = None,
    ) -> None:
        if state is None:
            state = self._load_state(kind)
        if new_ids is None:
            new_ids = []
        existing: List[int] = []
        for entry in state.get("recent_ids", []):
            try:
                existing.append(int(entry))
            except (TypeError, ValueError):
                continue
        merged: List[int] = []
        seen: Set[int] = set()
        for value in existing + list(new_ids):
            try:
                num = int(value)
            except (TypeError, ValueError):
                continue
            if num in seen:
                continue
            seen.add(num)
            merged.append(num)
        merged = merged[-RECENT_IDS_LIMIT:]
        state["last_id"] = int(last_id)
        state["recent_ids"] = merged
        self._save_state(kind, state)

    def _bootstrap_last_id(
        self,
        kind: str,
        endpoint: str,
        id_field: str,
        sort_field: Optional[str] = None,
        filter_field: Optional[str] = None,
    ) -> int:
        params = {
            "searchCriteria[sortOrders][0][field]": sort_field or id_field,
            "searchCriteria[sortOrders][0][direction]": "DESC",
            "searchCriteria[pageSize]": 1,
            "searchCriteria[current_page]": 1,
        }
        if filter_field:
            params["searchCriteria[filter_groups][0][filters][0][field]"] = filter_field
            params["searchCriteria[filter_groups][0][filters][0][value]"] = 0
            params["searchCriteria[filter_groups][0][filters][0][condition_type]"] = "gt"
        try:
            payload = self._request(endpoint, params)
        except Exception as exc:  # pragma: no cover - bootstrap 时失败仅记录
            LOG(f"[WARNING] {self.site} 初始化 {kind} 基线失败: {exc}")
            return 0

        items = payload.get("items", []) if isinstance(payload, dict) else []
        if not items:
            return 0

        try:
            latest = int(items[0].get(id_field, 0))
        except Exception:
            latest = 0
        if latest > 0:
            self._save_last_id(kind, latest)
            LOG(f"[INFO] {self.site} 初始化 {kind} 基线 ID={latest}，不推送历史记录。")
        return latest

    def process_orders(self) -> None:
        result = self._collect_entities("orders", "/rest/V1/orders", "entity_id")
        if result["skip_processing"]:
            return
        bootstrap = result["bootstrap"]
        max_id = result["max_id"]
        last_id = result["last_id"]
        items = result["items"]
        state = self._load_state("orders")

        if bootstrap:
            if max_id > last_id:
                self._save_last_id("orders", max_id, state=state)
                LOG(f"[INFO] {self.site} 首次运行，记录最新订单 ID={max_id}，不发送通知。")
            return

        if not items:
            return

        if result["truncated"]:
            self._save_last_id("orders", max_id, state=state)
            LOG(
                f"[WARNING] {self.site} orders 回溯记录超过 {self.max_pages * self.page_size} 条，"
                "已更新基线并跳过本次通知，避免刷屏。"
            )
            return

        recent_ids: Set[int] = set()
        for entry in state.get("recent_ids", []):
            try:
                recent_ids.add(int(entry))
            except (TypeError, ValueError):
                continue
        new_ids: List[int] = []

        for item in items:
            raw_entity_id = item.get("entity_id")
            entity_id_int: Optional[int] = None
            try:
                entity_id_int = int(raw_entity_id)
            except (TypeError, ValueError):
                entity_id_int = None
            if entity_id_int is not None and entity_id_int in recent_ids:
                continue
            if entity_id_int is not None:
                new_ids.append(entity_id_int)
                recent_ids.add(entity_id_int)
            entity_id = entity_id_int if entity_id_int is not None else raw_entity_id
            increment_id = item.get("increment_id") or entity_id
            total = item.get("grand_total")
            currency = item.get("base_currency_code") or ""
            status = item.get("status") or ""
            created_at = item.get("created_at") or ""
            customer = (item.get("customer_firstname") or "") + " " + (item.get("customer_lastname") or "")
            customer = customer.strip() or "Guest"
            email = item.get("customer_email") or ""

            event_data = {
                "site": self.site,
                "site_slug": self.site_topic,
                "entity_id": entity_id,
                "increment_id": increment_id,
                "grand_total": total,
                "currency": currency,
                "status": status,
                "created_at": created_at,
                "customer": customer,
                "email": email,
                "severity": "INFO",
            }
            telegram_tag = f"saltgoat/business/order/{self.site_topic}"
            event_data["tag"] = telegram_tag
            emit_event("saltgoat/business/order", event_data)
            message = build_message(
                "order",
                self.site,
                {
                    "order": f"#{increment_id}",
                    "total": f"{total} {currency}".strip(),
                    "status": status,
                    "customer": customer,
                    "email": email,
                    "created_at": created_at,
                },
            )
            telegram_broadcast(telegram_tag, message, event_data)
        self._save_last_id("orders", max_id, new_ids, state=state)
        if result["truncated"]:
            LOG(f"[WARNING] {self.site} 订单存在超过 {self.max_pages * self.page_size} 条新纪录，已仅推送最近 {len(items)} 条。")

    def process_customers(self) -> None:
        result = self._collect_entities(
            "customers",
            "/rest/V1/customers/search",
            "id",
            filter_field="entity_id",
            sort_field="entity_id",
        )
        if result["skip_processing"]:
            return
        bootstrap = result["bootstrap"]
        max_id = result["max_id"]
        last_id = result["last_id"]
        items = result["items"]
        state = self._load_state("customers")

        if bootstrap:
            if max_id > last_id:
                self._save_last_id("customers", max_id, state=state)
                LOG(f"[INFO] {self.site} 首次运行，记录最新用户 ID={max_id}，不发送通知。")
            return

        if not items:
            return

        if result["truncated"]:
            self._save_last_id("customers", max_id, state=state)
            LOG(
                f"[WARNING] {self.site} customers 回溯记录超过 {self.max_pages * self.page_size} 条，"
                "已更新基线并跳过本次通知，避免刷屏。"
            )
            return

        recent_ids: Set[int] = set()
        for entry in state.get("recent_ids", []):
            try:
                recent_ids.add(int(entry))
            except (TypeError, ValueError):
                continue
        new_ids: List[int] = []

        for item in items:
            raw_entity_id = item.get("id")
            entity_id_int: Optional[int] = None
            try:
                entity_id_int = int(raw_entity_id)
            except (TypeError, ValueError):
                entity_id_int = None
            if entity_id_int is not None and entity_id_int in recent_ids:
                continue
            if entity_id_int is not None:
                new_ids.append(entity_id_int)
                recent_ids.add(entity_id_int)
            entity_id = entity_id_int if entity_id_int is not None else raw_entity_id
            firstname = item.get("firstname") or ""
            lastname = item.get("lastname") or ""
            name = (firstname + " " + lastname).strip() or "(未命名)"
            email = item.get("email") or ""
            created_at = item.get("created_at") or ""
            group_id = item.get("group_id")

            event_data = {
                "site": self.site,
                "site_slug": self.site_topic,
                "entity_id": entity_id,
                "name": name,
                "email": email,
                "created_at": created_at,
                "group_id": group_id,
                "customer_id": item.get("id"),
                "severity": "INFO",
            }
            telegram_tag = f"saltgoat/business/customer/{self.site_topic}"
            event_data["tag"] = telegram_tag
            emit_event("saltgoat/business/customer", event_data)
            message = build_message(
                "customer",
                self.site,
                {
                    "id": entity_id,
                    "customer": name,
                    "email": email,
                    "created_at": created_at,
                    "customer_group": group_id,
                },
            )
            telegram_broadcast(telegram_tag, message, event_data)
        self._save_last_id("customers", max_id, new_ids, state=state)
        if result["truncated"]:
            LOG(f"[WARNING] {self.site} 用户存在超过 {self.max_pages * self.page_size} 条新纪录，已仅推送最近 {len(items)} 条。")

    def run(self) -> None:
        if "orders" in self.kinds:
            self.process_orders()
        if "customers" in self.kinds:
            self.process_customers()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Magento API watcher")
    parser.add_argument("--site", required=True, help="站点名称，对应 secrets.magento_api.<site>")
    parser.add_argument(
        "--kinds",
        default="orders,customers",
        help="监听类型，逗号分隔（orders,customers）",
    )
    parser.add_argument("--page-size", type=int, default=50, help="每次拉取的记录数量（默认 50）")
    parser.add_argument(
        "--auth-mode",
        choices=["auto", "bearer", "oauth1"],
        default="auto",
        help="认证模式：auto 根据配置自动判断，或显式指定 bearer / oauth1",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    site = args.site.strip()
    if not site:
        LOG("[ERROR] 请提供 --site")
        sys.exit(1)

    base_path = f"secrets:magento_api:{site}"
    base_url = pillar_get(f"{base_path}:base_url", "")
    token = pillar_get(f"{base_path}:token", "") or pillar_get(f"{base_path}:access_token", "")
    entry = pillar_get(base_path, {})
    if isinstance(entry, dict):
        base_url = entry.get("base_url", base_url)
        token = token or entry.get("token", "") or entry.get("access_token", "")
    else:
        entry = {}

    raw_oauth_params: Dict[str, Any] = {}
    admin_username = ""
    admin_password = ""

    def _collect_oauth(source: Dict[str, Any]) -> None:
        for group_key in ("oauth", "oauth1"):
            nested = source.get(group_key)
            if isinstance(nested, dict):
                _collect_oauth(nested)
        for key in [
            "consumer_key",
            "client_key",
            "consumer_secret",
            "client_secret",
            "access_token",
            "access_token_secret",
            "oauth_token",
            "oauth_token_secret",
            "token",
            "token_secret",
        ]:
            value = source.get(key)
            if value and key not in raw_oauth_params:
                raw_oauth_params[key] = value

    _collect_oauth(entry)
    for key in ("admin_username", "username", "user"):
        value = entry.get(key)
        if isinstance(value, str) and value:
            admin_username = value
            break
    for key in ("admin_password", "password"):
        value = entry.get(key)
        if isinstance(value, str) and value:
            admin_password = value
            break

    detected_mode = (entry.get("auth_mode") or entry.get("auth") or "").lower()

    local_entry = load_local_secret(site)
    if local_entry:
        if not base_url:
            base_url = local_entry.get("base_url", base_url)
        if not token:
            token = local_entry.get("token", "") or local_entry.get("access_token", "")
        _collect_oauth(local_entry)
        if not detected_mode:
            detected_mode = (local_entry.get("auth_mode") or local_entry.get("auth") or "").lower()
        if not admin_username:
            for key in ("admin_username", "username", "user"):
                value = local_entry.get(key)
                if isinstance(value, str) and value:
                    admin_username = value
                    break
        if not admin_password:
            for key in ("admin_password", "password"):
                value = local_entry.get(key)
                if isinstance(value, str) and value:
                    admin_password = value
                    break

    def has_oauth_credentials(params: Dict[str, Any]) -> bool:
        consumer_key = params.get("consumer_key") or params.get("client_key")
        consumer_secret = params.get("consumer_secret") or params.get("client_secret")
        token_secret = (
            params.get("access_token_secret")
            or params.get("oauth_token_secret")
            or params.get("token_secret")
        )
        access_token = (
            params.get("access_token") or params.get("oauth_token") or params.get("token")
        )
        return all([consumer_key, consumer_secret, token_secret, access_token])

    auth_mode_request = args.auth_mode.lower()
    if auth_mode_request != "auto":
        auth_mode = auth_mode_request
    elif detected_mode in {"bearer", "oauth1", "admin_login"}:
        auth_mode = detected_mode
    elif has_oauth_credentials(raw_oauth_params):
        auth_mode = "oauth1"
    else:
        auth_mode = "bearer"

    oauth_params = {k: str(v) for k, v in raw_oauth_params.items() if v not in (None, "")}

    if not base_url:
        LOG(f"[ERROR] 未找到站点 {site} 的 base_url（pillar 路径 {base_path}）")
        sys.exit(1)

    if auth_mode == "bearer" and not token and admin_username and admin_password:
        auth_mode = "admin_login"

    if auth_mode == "bearer":
        if not token:
            LOG(f"[ERROR] 未找到站点 {site} 的 Bearer token，请在 Pillar 或 secret 中配置 token/access_token。")
            sys.exit(1)
    elif auth_mode == "oauth1":
        if not oauth_params:
            LOG(f"[ERROR] 站点 {site} 未提供 OAuth1 所需的 consumer/access token 参数。")
            sys.exit(1)
    elif auth_mode == "admin_login":
        if not admin_username or not admin_password:
            LOG(f"[ERROR] 站点 {site} 未提供 admin 登录凭据（username/password）。")
            sys.exit(1)
    else:
        LOG(f"[ERROR] 不支持的认证模式: {auth_mode}")
        sys.exit(1)

    kinds = [k.strip() for k in args.kinds.split(",") if k.strip() in {"orders", "customers"}]
    if not kinds:
        LOG("[ERROR] --kinds 至少包含 orders 或 customers")
        sys.exit(1)

    init_token = token
    if auth_mode == "oauth1":
        init_token = (
            oauth_params.get("access_token")
            or oauth_params.get("token")
            or oauth_params.get("oauth_token")
            or token
        )
    elif auth_mode == "admin_login":
        try:
            init_token = obtain_admin_token(site, base_url, admin_username, admin_password)
        except MagentoAPIError as exc:
            LOG(f"[ERROR] {exc}")
            sys.exit(1)
        auth_mode = "bearer"

    try:
        watcher = MagentoWatcher(
            site,
            base_url,
            init_token,
            kinds,
            args.page_size,
            auth_mode=auth_mode,
            oauth_params=oauth_params,
        )
    except ValueError as exc:
        LOG(f"[ERROR] {exc}")
        sys.exit(1)

    watcher.run()


if __name__ == "__main__":
    main()
