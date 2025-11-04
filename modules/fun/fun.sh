#!/bin/bash
# SaltGoat playful commands: jokes, ASCII goats, and quick status peeks.

set -euo pipefail

fun_show_status() {
    local sites=("$@")
    if [[ ${#sites[@]} -eq 0 ]]; then
        sites=(bank tank pwas)
    fi
    if [[ -x "${SCRIPT_DIR}/scripts/health-panel.sh" ]]; then
        "${SCRIPT_DIR}/scripts/health-panel.sh" "${sites[@]}"
    else
        log_warning "health-panel.sh 未找到，无法展示状态"
    fi
}

fun_ascii_goat() {
    local message="$1"
    cat <<'GOAT'
          __         __
         (  \.-"""-./  )
          \    : :    /
           |   ___   |
           |  (___)  |
           \  /   \  /
            '.___.'
GOAT
    printf "🐐 %s\n" "$message"
}

fun_joke() {
    local jokes=(
        "Varnish 说：我缓存了整片前端，可还是忘不了你那一次 cache:flush。"
        "MySQL 问 Valkey：为什么你这么快？Valkey：我一直 in-memory 啊。"
        "盐山羊名言：没有什么是一键 highstate 解决不了的，如果有，那就两次。"
        "运维的浪漫：我想把 /var/log 写成诗，把 502 调成歌。"
    )
    local idx=$((RANDOM % ${#jokes[@]}))
    fun_ascii_goat "${jokes[$idx]}"
}

fun_tip() {
    local tips=(
        "tests/test_varnish_regression.sh bank tank —— 回归切换 Varnish 前先 dry-run。"
        "scripts/health-panel.sh —— 一行命令查看 systemd + HTTP + 磁盘三合一。"
        "tests/test_magento_cli_suite.sh /var/www/<site> —— 让 Magento CLI 先说话。"
        "/opt/saltgoat-security/fail2ban_watch.py —— 每 5 分钟扫一次可疑 IP，别忘了看 Telegram。"
        "saltgoat magetools varnish diagnose <site> —— 记得在 enable 前先体检。"
    )
    local idx=$((RANDOM % ${#tips[@]}))
    printf '🐐 Tip: %s\n' "${tips[$idx]}"
}

fun_fortune() {
    local fortunes=(
        "[FORTUNE] 缓存未失控，highstate 不放松。=> 试试 scripts/goat_pulse.py --once"
        "[FORTUNE] 人生苦短，别忘了 salt-call state.apply optional.fail2ban-watch"
        "[FORTUNE] 看日志要趁热：cat /var/log/saltgoat/alerts.log | tail"
        "[FORTUNE] 不是所有 502 都怪 PHP，curl scripts/health-panel.sh 先看看"
    )
    local idx=$((RANDOM % ${#fortunes[@]}))
    printf '%s\n' "${fortunes[$idx]}"
}

fun_handler() {
    local action="${1:-status}"
    shift || true
    case "$action" in
        status)
            fun_show_status "$@"
            ;;
        joke)
            fun_joke
            ;;
        ascii)
            fun_ascii_goat "SaltGoat 在岗，systemctl status 一切正常。"
            ;;
        tip)
            fun_tip
            ;;
        fortune)
            fun_fortune
            ;;
        help|--help|-h)
            cat <<'EOF'
saltgoat fun status [sites...]   # 调用 health-panel.sh 展示服务与站点状态
saltgoat fun joke                # 随机输出一句 Goat 风格冷笑话
saltgoat fun ascii               # 打印 ASCII 山羊 + 状态寄语
saltgoat fun tip                 # 输出一个 SaltGoat 运维小贴士
saltgoat fun fortune             # 输出一个 Goat Fortune + 建议动作
EOF
            ;;
        *)
            log_error "未知 fun 命令: ${action}"
            fun_handler help
            ;;
    esac
}
