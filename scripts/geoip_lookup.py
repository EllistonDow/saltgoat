#!/usr/bin/env python3
"""Simple GeoIP lookup helper using ip-api.com."""
from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from typing import Dict

API = "http://ip-api.com/json/"


def lookup(ip: str | None = None) -> Dict[str, str]:
    url = API + (ip or "")
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.URLError:
        return {"status": "fail", "message": "network error"}


def main() -> None:
    ip = sys.argv[1] if len(sys.argv) > 1 else None
    result = lookup(ip)
    if result.get("status") != "success":
        print(f"GeoIP lookup failed: {result.get('message', 'unknown error')}")
        sys.exit(1)
    print(
        f"{result.get('query')} -> {result.get('country', '')} {result.get('regionName', '')} {result.get('city', '')}"
    )


if __name__ == "__main__":
    main()
