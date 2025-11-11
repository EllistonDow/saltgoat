#!/usr/bin/env python3
"""Swap management helper for SaltGoat."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
import subprocess
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Dict, List, Optional, Tuple

DEFAULT_SWAPFILE = Path("/swapfile")
DEFAULT_MIN_SIZE = "8G"
DEFAULT_MAX_SIZE = ""
SYSCTL_FILE = Path("/etc/sysctl.d/99-swap-tuning.conf")
REPO_ROOT = Path(__file__).resolve().parents[2]


class SwapError(RuntimeError):
    """Raised when a swap operation cannot be completed."""


@dataclass
class SwapDevice:
    name: str
    type: str
    size_bytes: int
    used_bytes: int
    priority: int

    def to_dict(self) -> Dict[str, object]:
        data = asdict(self)
        data["size_human"] = human_readable(self.size_bytes)
        data["used_human"] = human_readable(self.used_bytes)
        return data


def human_readable(value: int) -> str:
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    size = float(value)
    for unit in units:
        if size < 1024 or unit == units[-1]:
            return f"{size:.2f} {unit}"
        size /= 1024
    return f"{size:.2f} {units[-1]}"


def parse_size(expr: str) -> int:
    expr = str(expr).strip().lower()
    if not expr:
        raise SwapError("Size cannot be empty")
    match = re.match(r"^([0-9]+)([kmgte]?)(i?b)?$", expr)
    if not match:
        raise SwapError(f"Invalid size expression: {expr}")
    value = int(match.group(1))
    unit = match.group(2)
    multipliers = {
        "": 1,
        "k": 1024,
        "m": 1024**2,
        "g": 1024**3,
        "t": 1024**4,
        "e": 1024**5,
    }
    return value * multipliers.get(unit, 1)


def run(cmd: List[str], check: bool = True, capture: bool = False) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(
            cmd,
            check=check,
            text=True,
            capture_output=capture,
        )
        return result
    except subprocess.CalledProcessError as exc:  # pragma: no cover - requires root failures
        raise SwapError(f"Command failed: {' '.join(cmd)}\n{exc.stderr or exc.stdout}") from exc


def list_swap_devices() -> List[SwapDevice]:
    devices: List[SwapDevice] = []
    try:
        with open("/proc/swaps", "r", encoding="utf-8") as fh:
            lines = fh.read().strip().splitlines()
    except FileNotFoundError:
        return devices
    for line in lines[1:]:
        parts = line.split()
        if len(parts) < 5:
            continue
        name, dev_type, size_kb, used_kb, priority = parts[:5]
        devices.append(
            SwapDevice(
                name=name,
                type=dev_type,
                size_bytes=int(size_kb) * 1024,
                used_bytes=int(used_kb) * 1024,
                priority=int(priority),
            )
        )
    return devices


def get_swappiness() -> int:
    try:
        with open("/proc/sys/vm/swappiness", "r", encoding="utf-8") as fh:
            return int(fh.read().strip())
    except Exception:
        return -1


def get_vfs_cache_pressure() -> int:
    try:
        with open("/proc/sys/vm/vfs_cache_pressure", "r", encoding="utf-8") as fh:
            return int(fh.read().strip())
    except Exception:
        return -1


def read_vmstat() -> Tuple[int, int]:
    try:
        output = subprocess.check_output(["vmstat", "1", "2"], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return (0, 0)
    lines = output.strip().splitlines()
    if len(lines) < 3:
        return (0, 0)
    last = lines[-1].split()
    if len(last) < 8:
        return (0, 0)
    try:
        return (int(last[6]), int(last[7]))
    except ValueError:
        return (0, 0)


def ensure_fstab_entry(swapfile: Path) -> bool:
    entry = f"{swapfile} none swap sw 0 0"
    changed = False
    fstab = Path("/etc/fstab")
    if not fstab.exists():
        fstab.write_text(entry + "\n", encoding="utf-8")
        return True
    lines = fstab.read_text(encoding="utf-8").splitlines()
    if any(line.strip().split()[:1] == [str(swapfile)] for line in lines):
        return False
    lines.append(entry)
    fstab.write_text("\n".join(lines) + "\n", encoding="utf-8")
    changed = True
    return changed


def remove_fstab_entry(swapfile: Path) -> bool:
    fstab = Path("/etc/fstab")
    if not fstab.exists():
        return False
    lines = fstab.read_text(encoding="utf-8").splitlines()
    filtered = [line for line in lines if line.strip().split()[:1] != [str(swapfile)]]
    if filtered == lines:
        return False
    fstab.write_text("\n".join(filtered) + "\n", encoding="utf-8")
    return True


def ensure_swap_capacity(
    min_size: int,
    swapfile: Path = DEFAULT_SWAPFILE,
    max_size: Optional[int] = None,
    dry_run: bool = False,
    quiet: bool = False,
    devices: Optional[List[SwapDevice]] = None,
) -> Dict[str, object]:
    if devices is None:
        devices = list_swap_devices()
    total_bytes = sum(dev.size_bytes for dev in devices)
    file_device = next((dev for dev in devices if dev.name == str(swapfile)), None)
    current_file_bytes = file_device.size_bytes if file_device else (swapfile.stat().st_size if swapfile.exists() else 0)
    other_bytes = total_bytes - (file_device.size_bytes if file_device else 0)
    if total_bytes >= min_size:
        if not quiet:
            print(f"[INFO] swap total {human_readable(total_bytes)} already >= {human_readable(min_size)}")
        return {
            "changed": False,
            "total_bytes": total_bytes,
            "file_bytes": current_file_bytes,
        }

    needed = min_size - total_bytes
    target_size = current_file_bytes + needed
    if max_size is not None:
        target_size = min(target_size, max_size)
    if target_size <= current_file_bytes:
        return {
            "changed": False,
            "total_bytes": total_bytes,
            "file_bytes": current_file_bytes,
        }

    parent = swapfile.parent
    parent.mkdir(parents=True, exist_ok=True)
    statv = shutil.disk_usage(parent)
    free_bytes = statv.free
    growth = target_size - current_file_bytes
    if growth > free_bytes:
        raise SwapError(
            f"Not enough free space in {parent}: need {human_readable(growth)}, available {human_readable(free_bytes)}"
        )

    commands: List[List[str]] = []
    if file_device:
        commands.append(["swapoff", str(swapfile)])
    commands.append(["fallocate", "-l", str(target_size), str(swapfile)])
    commands.append(["chmod", "600", str(swapfile)])
    commands.append(["mkswap", str(swapfile)])
    commands.append(["swapon", str(swapfile)])

    if dry_run:
        return {
            "changed": True,
            "commands": commands,
            "target_bytes": target_size,
            "previous_bytes": current_file_bytes,
        }

    for cmd in commands:
        run(cmd, check=True)

    ensure_fstab_entry(swapfile)

    return {
        "changed": True,
        "target_bytes": target_size,
        "previous_bytes": current_file_bytes,
        "total_bytes": target_size + other_bytes,
    }


def disable_swapfile(swapfile: Path, purge: bool = False, dry_run: bool = False) -> Dict[str, object]:
    result: Dict[str, object] = {"swapfile": str(swapfile), "purge": purge}
    is_active = any(dev.name == str(swapfile) for dev in list_swap_devices())
    if dry_run:
        result["would_swapoff"] = is_active
        result["would_remove"] = purge
        return result

    if is_active:
        run(["swapoff", str(swapfile)], check=True)
    if purge and swapfile.exists():
        swapfile.unlink()
    remove_fstab_entry(swapfile)
    result["changed"] = True
    return result


def tune_sysctl(swappiness: Optional[int], vfs_cache_pressure: Optional[int], dry_run: bool = False) -> Dict[str, object]:
    updates: Dict[str, int] = {}
    if swappiness is not None:
        if not (0 <= swappiness <= 200):
            raise SwapError("swappiness must be between 0 and 200")
        updates["vm.swappiness"] = swappiness
    if vfs_cache_pressure is not None:
        if not (1 <= vfs_cache_pressure <= 1000):
            raise SwapError("vfs_cache_pressure must be between 1 and 1000")
        updates["vm.vfs_cache_pressure"] = vfs_cache_pressure
    if not updates:
        raise SwapError("No sysctl values provided")
    lines = [f"{key} = {value}" for key, value in updates.items()]
    if dry_run:
        return {"dry_run": True, "sysctl": updates}
    SYSCTL_FILE.parent.mkdir(parents=True, exist_ok=True)
    SYSCTL_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")
    for key, value in updates.items():
        run(["sysctl", f"{key}={value}"], check=True)
    return {"changed": True, "sysctl": updates}


def print_status(devices: List[SwapDevice], json_output: bool = False) -> int:
    total = sum(dev.size_bytes for dev in devices)
    used = sum(dev.used_bytes for dev in devices)
    swappiness = get_swappiness()
    vfs_cache_pressure = get_vfs_cache_pressure()
    si, so = read_vmstat()
    summary = {
        "devices": [dev.to_dict() for dev in devices],
        "total_bytes": total,
        "used_bytes": used,
        "swappiness": swappiness,
        "vfs_cache_pressure": vfs_cache_pressure,
        "vmstat": {"si": si, "so": so},
    }
    if json_output:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        print("Swap Devices")
        print("-" * 48)
        if not devices:
            print("No active swap devices.")
        else:
            print(f"{'Name':<25} {'Type':<8} {'Size':>10} {'Used':>10} {'Prio':>5}")
            for dev in devices:
                print(
                    f"{dev.name:<25} {dev.type:<8} {human_readable(dev.size_bytes):>10} "
                    f"{human_readable(dev.used_bytes):>10} {dev.priority:>5}"
                )
        print()
        print(f"Total: {human_readable(total)}  Used: {human_readable(used)}")
        ratio = (used / total * 100) if total else 0
        print(f"Usage: {ratio:.1f}%")
        print(f"vm.swappiness: {swappiness}")
        print(f"vm.vfs_cache_pressure: {vfs_cache_pressure}")
        print(f"vmstat (last 1s) si={si}  so={so}")
        print()
        if total == 0:
            print("[WARNING] Swap is disabled.")
        elif ratio >= 95:
            print("[WARNING] Swap usage exceeds 95%. Consider expanding swap.")
        elif swappiness > 30:
            print("[NOTE] Consider lowering vm.swappiness to 10-20 for heavy Magento workloads.")
    if total == 0 or (total > 0 and used / total >= 0.95):
        return 2
    return 0


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="SaltGoat swap management helper")
    sub = parser.add_subparsers(dest="command", required=True)

    status = sub.add_parser("status", help="Show swap devices and metrics")
    status.add_argument("--json", action="store_true", help="Output JSON summary")

    ensure = sub.add_parser("ensure", help="Ensure minimum swap capacity")
    ensure.add_argument("--min-size", default=DEFAULT_MIN_SIZE)
    ensure.add_argument("--max-size", default=DEFAULT_MAX_SIZE)
    ensure.add_argument("--swapfile", default=str(DEFAULT_SWAPFILE))
    ensure.add_argument("--dry-run", action="store_true")
    ensure.add_argument("--quiet", action="store_true")

    create = sub.add_parser("create", help="Create swapfile with given size")
    create.add_argument("--size", required=True)
    create.add_argument("--swapfile", default=str(DEFAULT_SWAPFILE))
    create.add_argument("--dry-run", action="store_true")

    resize = sub.add_parser("resize", help="Resize managed swapfile")
    resize.add_argument("--size", required=True)
    resize.add_argument("--swapfile", default=str(DEFAULT_SWAPFILE))
    resize.add_argument("--dry-run", action="store_true")

    disable = sub.add_parser("disable", help="Swapoff the managed swapfile")
    disable.add_argument("--swapfile", default=str(DEFAULT_SWAPFILE))
    disable.add_argument("--purge", action="store_true", help="Remove file and fstab entry")
    disable.add_argument("--dry-run", action="store_true")

    purge = sub.add_parser("purge", help="Swapoff and remove the managed swapfile")
    purge.add_argument("--swapfile", default=str(DEFAULT_SWAPFILE))
    purge.add_argument("--dry-run", action="store_true")

    tune = sub.add_parser("tune", help="Adjust swappiness / vfs cache pressure")
    tune.add_argument("--swappiness", type=int)
    tune.add_argument("--vfs-cache-pressure", type=int)
    tune.add_argument("--dry-run", action="store_true")

    menu = sub.add_parser("menu", help="Interactive swap menu")

    return parser.parse_args(argv)


def interactive_menu() -> None:
    while True:
        devices = list_swap_devices()
        total = sum(dev.size_bytes for dev in devices)
        used = sum(dev.used_bytes for dev in devices)
        print("=" * 50)
        print(f"Swap total: {human_readable(total)}  Used: {human_readable(used)}")
        print("1) Status")
        print("2) Ensure minimum 8G")
        print("3) Resize swapfile")
        print("4) Tune swappiness (set to 20)")
        print("5) Disable swapfile")
        print("6) Exit")
        choice = input("Select an option: ").strip()
        if choice == "1":
            print_status(devices, json_output=False)
        elif choice == "2":
            try:
                ensure_swap_capacity(parse_size("8G"))
            except SwapError as exc:  # pragma: no cover - interactive
                print(f"[ERROR] {exc}")
        elif choice == "3":
            size = input("Target size (e.g. 12G): ").strip()
            try:
                ensure_swap_capacity(parse_size(size), DEFAULT_SWAPFILE)
            except SwapError as exc:
                print(f"[ERROR] {exc}")
        elif choice == "4":
            try:
                tune_sysctl(20, None)
            except SwapError as exc:
                print(f"[ERROR] {exc}")
        elif choice == "5":
            confirm = input("Disable swapfile? (yes/no) ").strip().lower()
            if confirm == "yes":
                disable_swapfile(DEFAULT_SWAPFILE, purge=False)
        elif choice == "6":
            break
        else:
            print("Unknown selection.")


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)
    try:
        if args.command == "status":
            return print_status(list_swap_devices(), json_output=args.json)
        if args.command == "ensure":
            result = ensure_swap_capacity(
                min_size=parse_size(args.min_size),
                swapfile=Path(args.swapfile),
                max_size=parse_size(args.max_size) if args.max_size else None,
                dry_run=args.dry_run,
                quiet=args.quiet,
            )
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0
        if args.command == "create":
            result = ensure_swap_capacity(
                min_size=parse_size(args.size),
                swapfile=Path(args.swapfile),
                max_size=parse_size(args.size),
                dry_run=args.dry_run,
            )
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0
        if args.command == "resize":
            result = ensure_swap_capacity(
                min_size=parse_size(args.size),
                swapfile=Path(args.swapfile),
                max_size=parse_size(args.size),
                dry_run=args.dry_run,
            )
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0
        if args.command == "disable":
            result = disable_swapfile(Path(args.swapfile), purge=args.purge, dry_run=args.dry_run)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0
        if args.command == "purge":
            result = disable_swapfile(Path(args.swapfile), purge=True, dry_run=args.dry_run)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0
        if args.command == "tune":
            result = tune_sysctl(args.swappiness, args.vfs_cache_pressure, dry_run=args.dry_run)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0
        if args.command == "menu":
            interactive_menu()
            return 0
    except SwapError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
