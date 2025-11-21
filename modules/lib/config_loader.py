"""Unified configuration loading helpers for SaltGoat.

Provides thin wrappers around Salt Pillar while supporting local fallback files
and environment overrides to simplify CI/DEV execution where Salt Caller may
not be available.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Dict

try:
    from salt.client import Caller  # type: ignore
except Exception:  # pragma: no cover
    Caller = None  # type: ignore

_CALLER: Caller | None = None
_REPO_ROOT = Path(__file__).resolve().parents[2]
_SECRET_DIR = _REPO_ROOT / "salt" / "pillar" / "secret"


def _get_caller() -> Caller | None:
    global _CALLER
    if Caller is None:  # type: ignore
        return None
    if _CALLER is None:
        try:
            _CALLER = Caller()
        except Exception:
            return None
    return _CALLER


def pillar_get(path: str, default: Any = None) -> Any:
    caller = _get_caller()
    if caller is None:
        return default
    try:
        value = caller.cmd("pillar.get", path, default)
    except Exception:
        return default
    return default if value is None else value


def fire_event(tag: str, payload: Dict[str, Any]) -> bool:
    caller = _get_caller()
    if caller is None:
        return False
    try:
        caller.cmd("event.send", tag, payload)
        return True
    except Exception:
        return False


def load_secret_file(name: str) -> Dict[str, Any]:
    candidates = []
    env_hint = os.environ.get("SALTGOAT_SECRET_FILE")
    if env_hint:
        candidates.append(Path(env_hint))
    candidates.append(_SECRET_DIR / f"{name}.sls")
    for candidate in candidates:
        if not candidate.exists():
            continue
        try:
            import yaml  # type: ignore
        except Exception:
            return {}
        try:
            data = yaml.safe_load(candidate.read_text(encoding="utf-8")) or {}
        except Exception:
            continue
        if isinstance(data, dict):
            return data
    return {}


def load_json_env(name: str) -> Dict[str, Any]:
    raw = os.environ.get(name)
    if not raw:
        return {}
    try:
        data = json.loads(raw)
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}
