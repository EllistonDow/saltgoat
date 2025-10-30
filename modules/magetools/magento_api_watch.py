#!/usr/bin/env python3
"""
Magento API watcher: polls recent orders/customers and emits Salt events + Telegram notifications.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List
import subprocess
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
    try:
        reactor_common.broadcast_telegram(message, profiles, _log, tag=tag, thread_id=thread_id)
    except Exception as exc:  # pragma: no cover
        _log("error", {"message": str(exc)})


def build_message(kind: str, site: str, payload: Dict[str, Any]) -> str:
    lines = [f"[SaltGoat] NEW {kind} {site}"]
    for key, label in [
        ("order", "Order"),
        ("total", "Total"),
        ("status", "Status"),
        ("customer", "Customer"),
        ("email", "Email"),
        ("created_at", "Created"),
        ("customer_group", "Group"),
        ("id", "ID"),
    ]:
        value = payload.get(key)
        if value:
            lines.append(f"{label}: {value}")
    return "\n".join(lines)


class MagentoWatcher:
    def __init__(self, site: str, base_url: str, token: str, kinds: List[str], page_size: int = 50):
        self.site = site
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.kinds = kinds
        self.page_size = page_size
        self.state_dir = STATE_ROOT / site
        self.state_dir.mkdir(parents=True, exist_ok=True)

    def _request(self, path: str, params: Dict[str, Any]) -> Dict[str, Any]:
        query = urllib.parse.urlencode(params, doseq=True)
        url = f"{self.base_url}{path}?{query}"
        req = urllib.request.Request(url)
        req.add_header("Authorization", f"Bearer {self.token}")
        req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=30) as resp:  # nosec
            charset = resp.headers.get_content_charset() or "utf-8"
            data = resp.read().decode(charset)
            return json.loads(data)

    def _state_file(self, kind: str) -> Path:
        return self.state_dir / f"last_{kind}.json"

    def _load_last_id(self, kind: str) -> int:
        path = self._state_file(kind)
        if not path.exists():
            return 0
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            return int(data.get("last_id", 0))
        except Exception:
            return 0

    def _save_last_id(self, kind: str, last_id: int) -> None:
        path = self._state_file(kind)
        path.write_text(json.dumps({"last_id": last_id}), encoding="utf-8")

    def _bootstrap_last_id(self, kind: str, endpoint: str, id_field: str) -> int:
        params = {
            "searchCriteria[sortOrders][0][field]": id_field,
            "searchCriteria[sortOrders][0][direction]": "DESC",
            "searchCriteria[pageSize]": 1,
        }
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
        kind = "orders"
        last_id = self._load_last_id(kind)
        if last_id <= 0:
            if self._bootstrap_last_id(kind, "/rest/V1/orders", "entity_id") > 0:
                return
            # 若无法获取最新 ID，继续按照默认逻辑尝试（避免长期静默）
        bootstrap = last_id == 0
        params = {
            "searchCriteria[filter_groups][0][filters][0][field]": "entity_id",
            "searchCriteria[filter_groups][0][filters][0][value]": last_id,
            "searchCriteria[filter_groups][0][filters][0][condition_type]": "gt",
            "searchCriteria[sortOrders][0][field]": "entity_id",
            "searchCriteria[sortOrders][0][direction]": "ASC",
            "searchCriteria[pageSize]": self.page_size,
        }
        try:
            payload = self._request("/rest/V1/orders", params)
        except urllib.error.HTTPError as exc:
            body = ""
            try:
                body = exc.read().decode("utf-8", errors="ignore")
            except Exception:
                pass
            LOG(f"[ERROR] 获取订单失败: HTTP {exc.code} - {exc.reason} {body}")
            return
        except Exception as exc:
            LOG(f"[ERROR] 获取订单失败: {exc}")
            return
        items = payload.get("items", [])
        if not items:
            return
        new_items = []
        max_id = last_id
        for item in items:
            entity_id = int(item.get("entity_id", 0))
            if entity_id > last_id:
                new_items.append(item)
            if entity_id > max_id:
                max_id = entity_id
        if bootstrap:
            self._save_last_id(kind, max_id)
            LOG(f"[INFO] {self.site} 首次运行，记录最新订单 ID={max_id}，不发送通知。")
            return
        if not new_items:
            return
        for item in new_items:
            entity_id = item.get("entity_id")
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
                "entity_id": entity_id,
                "increment_id": increment_id,
                "grand_total": total,
                "currency": currency,
                "status": status,
                "created_at": created_at,
                "customer": customer,
                "email": email,
            }
            event_data["tag"] = "saltgoat/business/order"
            event_data["telegram_thread"] = 2
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
            telegram_broadcast("saltgoat/business/order", message, event_data)
        self._save_last_id(kind, max_id)

    def process_customers(self) -> None:
        kind = "customers"
        last_id = self._load_last_id(kind)
        if last_id <= 0:
            if self._bootstrap_last_id(kind, "/rest/V1/customers/search", "id") > 0:
                return
        bootstrap = last_id == 0
        params = {
            "searchCriteria[filter_groups][0][filters][0][field]": "entity_id",
            "searchCriteria[filter_groups][0][filters][0][value]": last_id,
            "searchCriteria[filter_groups][0][filters][0][condition_type]": "gt",
            "searchCriteria[sortOrders][0][field]": "entity_id",
            "searchCriteria[sortOrders][0][direction]": "ASC",
            "searchCriteria[pageSize]": self.page_size,
        }
        try:
            payload = self._request("/rest/V1/customers/search", params)
        except urllib.error.HTTPError as exc:
            body = ""
            try:
                body = exc.read().decode("utf-8", errors="ignore")
            except Exception:
                pass
            LOG(f"[ERROR] 获取用户失败: HTTP {exc.code} - {exc.reason} {body}")
            return
        except Exception as exc:
            LOG(f"[ERROR] 获取用户失败: {exc}")
            return
        items = payload.get("items", [])
        if not items:
            return
        new_items = []
        max_id = last_id
        for item in items:
            entity_id = int(item.get("id", 0))
            if entity_id > last_id:
                new_items.append(item)
            if entity_id > max_id:
                max_id = entity_id
        if bootstrap:
            self._save_last_id(kind, max_id)
            LOG(f"[INFO] {self.site} 首次运行，记录最新用户 ID={max_id}，不发送通知。")
            return
        if not new_items:
            return
        for item in new_items:
            entity_id = item.get("id")
            firstname = item.get("firstname") or ""
            lastname = item.get("lastname") or ""
            name = (firstname + " " + lastname).strip() or "(未命名)"
            email = item.get("email") or ""
            created_at = item.get("created_at") or ""
            group_id = item.get("group_id")
            event_data = {
                "site": self.site,
                "entity_id": entity_id,
                "name": name,
                "email": email,
                "created_at": created_at,
                "group_id": group_id,
            }
            event_data["tag"] = "saltgoat/business/customer"
            event_data["telegram_thread"] = 3
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
            telegram_broadcast("saltgoat/business/customer", message, event_data)
        self._save_last_id(kind, max_id)

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

    if not base_url or not token:
        local_entry = load_local_secret(site)
        base_url = base_url or local_entry.get("base_url", "")
        token = token or local_entry.get("token", "") or local_entry.get("access_token", "")

    if not base_url or not token:
        LOG(f"[ERROR] 未找到站点 {site} 的 base_url/token（pillar 路径 {base_path}）")
        sys.exit(1)

    kinds = [k.strip() for k in args.kinds.split(",") if k.strip() in {"orders", "customers"}]
    if not kinds:
        LOG("[ERROR] --kinds 至少包含 orders 或 customers")
        sys.exit(1)

    watcher = MagentoWatcher(site, base_url, token, kinds, args.page_size)
    watcher.run()


if __name__ == "__main__":
    main()
