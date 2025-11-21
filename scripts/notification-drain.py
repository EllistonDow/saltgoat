#!/usr/bin/env python3
"""Drain and replay SaltGoat notification failure queue entries."""
from __future__ import annotations

import argparse
import json
import socket
import sys
from pathlib import Path
from typing import Dict, List, Optional

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from modules.lib import notification as notif  # type: ignore
from modules.lib import notification_queue  # type: ignore


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Replay queued webhook/Telegram notifications")
    parser.add_argument(
        "--queue-dir",
        default=str(notif.QUEUE_DIR),
        help=f"queue directory (default: {notif.QUEUE_DIR})",
    )
    parser.add_argument(
        "--dest",
        dest="destinations",
        action="append",
        choices=["webhook", "telegram"],
        help="only drain selected destinations (repeatable)",
    )
    parser.add_argument("--max", type=int, default=0, help="maximum records to process (0 = all)")
    parser.add_argument("--dry-run", action="store_true", help="simulate without deleting files")
    parser.add_argument("--verbose", action="store_true", help="print every record result")
    parser.add_argument("--json-status", action="store_true", help="print JSON summary of remaining queue")
    parser.add_argument(
        "--alert-threshold",
        type=int,
        default=0,
        help="emit WARNING/CRITICAL alert when remaining >= threshold (0 = disabled)",
    )
    parser.add_argument(
        "--alert-tag",
        default="saltgoat/monitor/notification_queue",
        help="notification tag used when backlog exceeds threshold",
    )
    parser.add_argument(
        "--alert-site",
        default=None,
        help="site identifier used for filtering (default: host FQDN)",
    )
    return parser.parse_args()


def load_record(path: Path) -> Optional[dict]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"[SKIP] {path.name}: unable to parse JSON ({exc})", file=sys.stderr)
        return None


def main() -> int:
    args = parse_args()
    queue_dir = Path(args.queue_dir)
    if not queue_dir.exists():
        print(f"Queue directory {queue_dir} does not exist; nothing to do.")
        if args.json_status:
            print(json.dumps(build_status([], queue_dir), ensure_ascii=False))
        return 0

    files: List[Path] = sorted(queue_dir.glob("*.json"))
    if not files:
        print("Queue is empty.")
        if args.json_status:
            print(json.dumps(build_status([], queue_dir), ensure_ascii=False))
        return 0

    processed = success = 0
    limit = args.max if args.max and args.max > 0 else None
    destinations = set(args.destinations or [])

    for path in files:
        if limit is not None and processed >= limit:
            break
        record = load_record(path)
        if not record:
            continue
        destination = record.get("destination")
        if destinations and destination not in destinations:
            continue
        processed += 1
        ok, info = notification_queue.retry_record(record, dry_run=args.dry_run)
        prefix = "[OK]" if ok else "[FAIL]"
        if args.verbose or not ok:
            print(f"{prefix} {path.name}: {destination} -> {info}")
        if ok:
            if not args.dry_run:
                try:
                    path.unlink()
                except FileNotFoundError:
                    pass
            success += 1
        elif not args.dry_run:
            notification_queue.update_record_metadata(path, record, info)

    print(f"Processed {processed} record(s); {'dry-run' if args.dry_run else success} succeeded.")
    remaining_files = files
    if not args.dry_run:
        failures = processed - success
        if failures:
            print(f"{failures} record(s) still pending.")
        remaining_files = sorted(queue_dir.glob("*.json"))
        if args.alert_threshold > 0:
            maybe_send_alert(
                queue_dir=queue_dir,
                remaining=len(remaining_files),
                processed=processed,
                delivered=success,
                limit=limit,
                destinations=sorted(destinations),
                tag=args.alert_tag,
                site=args.alert_site,
                threshold=args.alert_threshold,
            )
    if args.json_status:
        print(json.dumps(build_status(remaining_files, queue_dir), ensure_ascii=False, indent=2))
    return 0


def maybe_send_alert(
    *,
    queue_dir: Path,
    remaining: int,
    processed: int,
    delivered: int,
    limit: Optional[int],
    destinations: List[str],
    tag: str,
    site: Optional[str],
    threshold: int,
) -> None:
    if remaining < threshold:
        return
    severity = "CRITICAL" if remaining >= threshold * 2 and threshold > 0 else "WARNING"
    host = site or socket.getfqdn()
    limit_text = str(limit) if limit is not None else "all"
    fields = [
        ("Host", host),
        ("QueueDir", str(queue_dir)),
        ("Remaining", str(remaining)),
        ("Processed", str(processed)),
        ("Delivered", str(delivered)),
        ("BatchLimit", limit_text),
        ("DestFilter", ",".join(destinations) or "any"),
        ("Threshold", str(threshold)),
    ]
    plain, html = notif.format_pre_block("NOTIFICATION QUEUE", host.upper(), fields)
    payload = {
        "severity": severity,
        "site": host,
        "remaining": remaining,
        "queue_dir": str(queue_dir),
        "processed": processed,
        "delivered": delivered,
        "threshold": threshold,
        "destinations": destinations,
    }
    if not notif.should_send(tag, severity, host):
        print(
            f"[ALERT] Suppressed backlog alert (tag={tag}, severity={severity}) due to notification filters."
        )
        return
    delivered_webhooks = notif.dispatch_webhooks(tag, severity, host, plain, html, payload)
    print(
        f"[ALERT] notification queue backlog detected (remaining={remaining}); webhooks delivered: {delivered_webhooks}."
    )
    try:
        from modules.monitoring import resource_alert as ra  # type: ignore

        ra.telegram_notify(tag, html, payload, plain)
        print("[ALERT] Telegram notification dispatched.")
    except Exception:
        print("[ALERT] Telegram module unavailable; skipped.")


def build_status(files: List[Path], queue_dir: Path) -> dict:
    summary: Dict[str, Any] = {
        "queue_dir": str(queue_dir),
        "total": len(files),
        "by_destination": {},
    }
    for path in files:
        record = load_record(path)
        destination = (record or {}).get("destination", "unknown")
        summary["by_destination"].setdefault(destination, 0)
        summary["by_destination"][destination] += 1
    return summary


if __name__ == "__main__":
    raise SystemExit(main())
