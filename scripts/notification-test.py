#!/usr/bin/env python3
"""
Send a synthetic SaltGoat notification to configured webhooks/Telegram for testing.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from modules.lib import notification as notif  # type: ignore


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="SaltGoat notification tester")
    parser.add_argument("--tag", required=True, help="通知 tag，例如 saltgoat/backup/mysql_dump/bank")
    parser.add_argument("--severity", default="INFO", help="级别，例如 INFO/WARNING/CRITICAL")
    parser.add_argument("--site", default=None, help="站点标识，用于匹配通知过滤规则")
    parser.add_argument(
        "--message",
        default=None,
        help="HTML 格式内容，默认自动根据 --text 生成 <pre>",
    )
    parser.add_argument(
        "--text",
        default="SaltGoat notification test",
        help="纯文本内容，用于 plain fallback 和默认 HTML 片段",
    )
    parser.add_argument(
        "--payload",
        default=None,
        help="附加 JSON payload（字符串或 @file），默认为基础字段",
    )
    parser.add_argument(
        "--webhook-only",
        action="store_true",
        help="仅发送 Webhook，不发 Telegram（用于测试 Mattermost/Slack）",
    )
    return parser


def load_payload(raw: str | None, defaults: dict) -> dict:
    if not raw:
        return defaults
    if raw.startswith("@"):
        data = Path(raw[1:]).read_text(encoding="utf-8")
    else:
        data = raw
    payload = json.loads(data)
    if not isinstance(payload, dict):
        raise SystemExit("payload 必须是 JSON 对象")
    return payload


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    plain = args.text or "SaltGoat notification test"
    html = args.message or f"<pre>{plain}</pre>"
    payload = load_payload(
        args.payload,
        {
            "generated": now,
            "severity": args.severity.upper(),
            "site": args.site,
            "note": "notification-test",
        },
    )
    delivered = notif.dispatch_webhooks(args.tag, args.severity.upper(), args.site, plain, html, payload)
    print(f"Webhook delivered: {delivered}")
    if args.webhook_only:
        return 0

    # Telegram 测试：沿用 resource_alert 的发送逻辑，若未配置 Telegram 会自动跳过
    try:
        from modules.monitoring import resource_alert as ra  # type: ignore
    except Exception:
        print("Telegram 模块不可用，已跳过。")
        return 0

    if not notif.should_send(args.tag, args.severity.upper(), args.site):
        print("Telegram 过滤规则阻止发送（min_severity 或 disabled_tags）。")
        return 0

    ra.telegram_notify(
        args.tag,
        html,
        {
            "tag": args.tag,
            "severity": args.severity.upper(),
            "site": args.site,
            "generated": now,
            **payload,
        },
        plain,
    )
    print("Telegram 通知已尝试发送。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

