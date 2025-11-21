"""Thin compatibility wrapper for SaltGoat notification helpers."""
from __future__ import annotations

import importlib
import importlib.util
import os
from pathlib import Path
from types import ModuleType
from typing import List, Optional

_REPO_HINTS: List[Path] = []
_env_root = os.environ.get("SALTGOAT_REPO_ROOT")
if _env_root:
    _REPO_HINTS.append(Path(_env_root))
_REPO_HINTS.extend(
    [
        Path("/opt/saltgoat"),
        Path("/srv/saltgoat"),
        Path("/home/doge/saltgoat"),
    ]
)
for parent in Path(__file__).resolve().parents:
    marker = parent / "modules"
    if marker.is_dir() and (marker / "lib" / "notification.py").is_file():
        _REPO_HINTS.append(parent)
        break

_CANDIDATE_FILES: List[Path] = []
for base in _REPO_HINTS:
    if not base:
        continue
    candidate = (base / "modules" / "lib" / "notification.py").resolve()
    if candidate.exists() and candidate not in _CANDIDATE_FILES:
        _CANDIDATE_FILES.append(candidate)


def _load_from_spec(path: Path) -> Optional[ModuleType]:
    try:
        spec = importlib.util.spec_from_file_location("saltgoat_notification_external", path)
        if spec is None or spec.loader is None:
            return None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    except Exception:  # pragma: no cover - runtime helper
        return None


def _load_notification_module() -> ModuleType:
    try:
        from modules.lib import notification as module  # type: ignore
        return module
    except Exception:
        pass
    for path in _CANDIDATE_FILES:
        module = _load_from_spec(path)
        if module is not None:
            return module
    raise ImportError(
        "Unable to locate modules.lib.notification; set SALTGOAT_REPO_ROOT or deploy SaltGoat repo"
    )


_target = _load_notification_module()

for _name in dir(_target):
    if _name.startswith("__"):
        continue
    globals()[_name] = getattr(_target, _name)

__all__ = [name for name in globals() if not name.startswith("__")]
