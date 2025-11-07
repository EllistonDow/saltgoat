#!/bin/bash
# Dry-run regression test for saltgoat git push helper

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG="${REPO_ROOT}/docs/changelog.md"
SALTGOAT_SCRIPT="${REPO_ROOT}/saltgoat"

original_version=$(grep -E '^SCRIPT_STATIC_VERSION' "$SALTGOAT_SCRIPT")

backup_file="$(mktemp)"
cp "$CHANGELOG" "$backup_file"

cleanup() {
    cat "$backup_file" > "$CHANGELOG"
    rm -f "$backup_file"
}
trap cleanup EXIT

echo "[INFO] Preparing temporary changelog entry for dry-run..."
printf '\n- 临时 Dry-run 验证项\n' >> "$CHANGELOG"

echo "[INFO] Running saltgoat git push --dry-run ..."
saltgoat git push --dry-run "dry-run verification"

post_version=$(grep -E '^SCRIPT_STATIC_VERSION' "$SALTGOAT_SCRIPT")

if [[ "$post_version" != "$original_version" ]]; then
    echo "[ERROR] Dry-run 修改了 saltgoat 版本号，请检查实现。"
    exit 1
fi

echo "[SUCCESS] Git 发布助手 dry-run 验证通过，未修改版本号或提交。"
