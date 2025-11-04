#!/usr/bin/env python3
"""Generate Magento order/customer summaries and notify via Telegram."""

from __future__ import annotations

import argparse
import datetime as dt
from collections import defaultdict
from typing import Any, Dict, Iterable, List, Tuple
import html

from magento_api_watch import (
    CALLER,
    MagentoWatcher,
    load_local_secret,
    pillar_get,
    telegram_broadcast,
    log_to_file,
)
from modules.lib import notification as notif  # type: ignore

PERIOD_CHOICES = {"daily", "weekly", "monthly"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Magento order/customer summary")
    parser.add_argument(
        "--site",
        dest="sites",
        action="append",
        help="站点名称，可多次指定 (必填)",
    )
    parser.add_argument(
        "--period",
        choices=sorted(PERIOD_CHOICES),
        required=True,
        help="统计周期 (daily/weekly/monthly)",
    )
    parser.add_argument(
        "--page-size",
        type=int,
        default=200,
        help="分页尺寸，默认 200",
    )
    parser.add_argument(
        "--no-telegram",
        action="store_true",
        help="仅输出，不发送 Telegram",
    )
    parser.add_argument(
        "--telegram-thread",
        type=int,
        default=None,
        help="Telegram 线程 ID，传递给 reactor 进行话题分流",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="不在控制台打印总结",
    )
    return parser.parse_args()


def local_now() -> dt.datetime:
    return dt.datetime.now(dt.datetime.now().astimezone().tzinfo or dt.timezone.utc)


def period_range(period: str) -> Tuple[dt.datetime, dt.datetime, str]:
    now_local = local_now()
    period_lower = period.lower()
    if period_lower == "daily":
        start_local = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
        label = "Daily"
    elif period_lower == "weekly":
        start_of_week = now_local - dt.timedelta(days=now_local.weekday())
        start_local = start_of_week.replace(hour=0, minute=0, second=0, microsecond=0)
        label = "Weekly"
    elif period_lower == "monthly":
        start_local = now_local.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        label = "Monthly"
    else:
        raise ValueError(f"Unsupported period {period}")
    return start_local, now_local, label


def fmt_ts(value: dt.datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=dt.timezone.utc)
    return value.astimezone(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


def fmt_api_ts(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


def fetch_entities(
    watcher: MagentoWatcher,
    endpoint: str,
    id_field: str,
    start: dt.datetime,
    end: dt.datetime,
) -> Iterable[Dict[str, Any]]:
    page = 1
    page_size = watcher.page_size
    collected: List[Dict[str, Any]] = []
    while True:
        params = {
            "searchCriteria[currentPage]": page,
            "searchCriteria[pageSize]": page_size,
            "searchCriteria[filter_groups][0][filters][0][field]": "created_at",
            "searchCriteria[filter_groups][0][filters][0][value]": fmt_api_ts(start),
            "searchCriteria[filter_groups][0][filters][0][condition_type]": "from",
            "searchCriteria[filter_groups][1][filters][0][field]": "created_at",
            "searchCriteria[filter_groups][1][filters][0][value]": fmt_api_ts(end),
            "searchCriteria[filter_groups][1][filters][0][condition_type]": "to",
            "searchCriteria[sortOrders][0][field]": id_field,
            "searchCriteria[sortOrders][0][direction]": "ASC",
        }
        payload = watcher._request(endpoint, params)  # pylint: disable=protected-access
        items = payload.get("items", []) if isinstance(payload, dict) else []
        if not items:
            break
        collected.extend(items)
        total = payload.get("total_count") if isinstance(payload, dict) else None
        if total is None or len(collected) >= int(total):
            break
        page += 1
    return collected


def summarise_orders(items: Iterable[Dict[str, Any]]) -> Tuple[int, Dict[str, float]]:
    totals: Dict[str, float] = defaultdict(float)
    count = 0
    for item in items:
        count += 1
        currency = item.get("order_currency_code") or item.get("base_currency_code") or ""
        try:
            amount = float(item.get("grand_total") or 0)
        except (TypeError, ValueError):
            amount = 0.0
        totals[currency] += amount
    return count, totals


def summarise_customers(items: Iterable[Dict[str, Any]]) -> int:
    return sum(1 for _ in items)


def format_totals(totals: Dict[str, float]) -> str:
    if not totals:
        return "0"
    parts = []
    for currency, amount in totals.items():
        label = currency or "CUR"
        parts.append(f"{label} {amount:,.2f}")
    return ", ".join(parts)


def ensure_sites(raw_sites: Iterable[str] | None) -> List[str]:
    if not raw_sites:
        raise SystemExit("请使用 --site 指定至少一个站点")
    sites: List[str] = []
    for value in raw_sites:
        for site in value.split(","):
            site = site.strip()
            if site and site not in sites:
                sites.append(site)
    if not sites:
        raise SystemExit("站点列表为空")
    return sites


def load_credentials(site: str) -> Tuple[str, str]:
    pillar_path = f"secrets:magento_api:{site}"
    base_url = pillar_get(f"{pillar_path}:base_url", "")
    token = pillar_get(f"{pillar_path}:token", "") or pillar_get(f"{pillar_path}:access_token", "")
    if base_url and token:
        return base_url, token
    local_entry = load_local_secret(site)
    base_url = base_url or local_entry.get("base_url", "")
    token = token or local_entry.get("token", "") or local_entry.get("access_token", "")
    if not base_url or not token:
        raise SystemExit(f"未找到站点 {site} 的 base_url/token (pillar 路径 secrets:magento_api:{site})")
    return base_url, token


def emit_event(tag: str, payload: Dict[str, Any]) -> None:
    try:
        CALLER.cmd("event.send", tag, payload)
    except Exception:  # pragma: no cover
        pass


def main() -> None:
    args = parse_args()
    sites = ensure_sites(args.sites)
    start_local, end_local, label = period_range(args.period)
    start_str = fmt_ts(start_local)
    end_str = fmt_ts(end_local)
    event_tag = f"saltgoat/business/summary/{args.period.lower()}"

    for site in sites:
        base_url, token = load_credentials(site)
        watcher = MagentoWatcher(site, base_url, token, ["orders"], page_size=args.page_size)
        site_slug = site.replace("/", "-").lower()
        display_site = site.replace("/", " / ").upper()

        orders = list(fetch_entities(watcher, "/rest/V1/orders", "entity_id", start_local, end_local))
        customers = list(
            fetch_entities(
                watcher,
                "/rest/V1/customers/search",
                "id",
                start_local,
                end_local,
            )
        )

        order_count, totals = summarise_orders(orders)
        customer_count = summarise_customers(customers)

        def format_block(title: str, site_label: str, rows: List[Tuple[str, str]]) -> Tuple[str, str]:
            underline = "=" * 30
            if rows:
                width = max(len(label) for label, _ in rows)
            else:
                width = 8
            lines = [underline, f"{title} ({site_label})", underline]
            for label, value in rows:
                parts = value.splitlines() if value else [""]
                lines.append(f"{label.ljust(width)} : {parts[0]}")
                for extra in parts[1:]:
                    lines.append(f"{' ' * width}   {extra}")
            plain = "\n".join(lines)
            html_block = f"<pre>{html.escape(plain)}</pre>"
            return plain, html_block

        generated = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        rows = [
            ("Window", f"{start_str} -> {end_str}"),
            ("Orders", str(order_count)),
            ("Revenue", format_totals(totals)),
            ("Customers", str(customer_count)),
            ("Generated", generated),
        ]
        plain_text, message = format_block(f"{label.upper()} SUMMARY", display_site, rows)
        payload = {
            "site": site,
            "site_slug": site_slug,
            "period": args.period.lower(),
            "label": label,
            "orders": {"count": order_count, "totals": totals},
            "customers": {"count": customer_count},
            "range": {"start": start_str, "end": end_str},
            "severity": "INFO",
        }
        if args.telegram_thread is not None:
            payload["telegram_thread"] = int(args.telegram_thread)
        elif "telegram_thread" not in payload:
            thread = notif.get_thread_id(telegram_tag)
            if thread is not None:
                payload["telegram_thread"] = thread

        log_to_file("SUMMARY", event_tag, payload)
        emit_event(event_tag, payload)

        if not args.no_telegram:
            telegram_tag = f"saltgoat/business/summary/{site_slug}"
            if notif.should_send(telegram_tag, payload["severity"], site_slug):
                payload["tag"] = telegram_tag
                telegram_broadcast(telegram_tag, message, payload, plain_text)
            else:
                log_to_file(
                    "SUMMARY",
                    f"{telegram_tag} skip",
                    {
                        "reason": "filtered",
                        "severity": payload["severity"],
                        "site": site_slug,
                    },
                )

        if not args.quiet:
            print(plain_text)


if __name__ == "__main__":
    main()
