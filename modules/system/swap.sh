#!/bin/bash
# Swap management CLI wrapper

: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SWAP_HELPER="${SCRIPT_DIR}/modules/lib/swap_helper.py"

swap_usage() {
    cat <<'EOF'
用法: saltgoat swap <command> [options]

可用子命令:
  status                显示当前 swap 设备、使用率、si/so、swappiness
  ensure                自动创建/扩容 swapfile (默认 /swapfile，至少 8G)
  create|resize         手工创建或调整 swapfile 大小
  disable|purge         swapoff 指定 swapfile，并可选删除文件及 fstab 条目
  tune                  设置 vm.swappiness / vm.vfs_cache_pressure 并写入 sysctl
  menu                  交互式菜单

示例:
  saltgoat swap status
  saltgoat swap ensure --min-size 8G --max-size 16G
  saltgoat swap tune --swappiness 15 --vfs-cache-pressure 50
  saltgoat swap disable --purge
EOF
}

swap_runner() {
    if [[ ! -f "$SWAP_HELPER" ]]; then
        log_error "缺少 swap helper: ${SWAP_HELPER}"
        exit 1
    fi
    local subcommand="$1"
    shift || true
    case "$subcommand" in
        ""|"help"|"--help"|"-h")
            swap_usage
            ;;
        status|ensure|create|resize|disable|purge|tune|menu)
            python3 "$SWAP_HELPER" "$subcommand" "$@"
            ;;
        *)
            log_error "未知的 swap 子命令: ${subcommand}"
            swap_usage
            exit 1
            ;;
    esac
}
