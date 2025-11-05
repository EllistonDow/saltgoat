#!/bin/bash
# 帮助系统模块 - 分层帮助显示
# lib/help.sh

# 主帮助函数
show_help() {
    case "$1" in
        "install")
            show_install_help
            ;;
        "nginx")
            show_nginx_help
            ;;
        "monitor")
            show_monitor_help
            ;;
        "maintenance")
            show_maintenance_help
            ;;
        "pillar")
            show_pillar_help
            ;;
        "optimize")
            show_optimize_help
            ;;
        "speedtest")
            show_speedtest_help
            ;;
        "xtrabackup")
            show_xtrabackup_help
            ;;
        "monitoring")
            show_monitoring_help
            ;;
        "diagnose")
            show_diagnose_help
            ;;
        "profile")
            show_profile_help
            ;;
        "version-lock")
            show_version_lock_help
            ;;
        "magetools")
            show_magetools_help
            ;;
        "analyse")
            show_analyse_help
            ;;
        "minio")
            show_minio_help
            ;;
        "fun")
            show_fun_help
            ;;
        "cockpit")
            show_cockpit_help
            ;;
        "adminer")
            show_adminer_help
            ;;
        "uptime-kuma")
            show_uptime_kuma_help
            ;;
        "ssl")
            show_ssl_help
            ;;
        "pwa")
            show_pwa_help
            ;;
        "git")
            show_git_help
            ;;
        "all")
            show_complete_help
            ;;
        *)
            show_main_help
            ;;
    esac
}

# 帮助输出工具
help_title() {
    echo -e "${PURPLE}$1${NC}"
}

help_subtitle() {
    echo -e "${CYAN}$1${NC}"
}

help_command() {
    local cmd="$1"
    local desc="$2"
    printf "  ${GREEN}%-30s${NC} %s\n" "$cmd" "$desc"
}

help_note() {
    echo -e "  ${YELLOW}NOTE:${NC} $1"
}

# 主帮助菜单
show_main_help() {
    help_title "SaltGoat $SCRIPT_VERSION"
    echo -e "用法: ${GREEN}saltgoat <command> [options]${NC}"
    echo ""

    help_note "除少数只读命令（help/git/lint/format）外，建议使用 'sudo saltgoat ...' 执行以读取 /etc 与 Salt 资源。"
    echo ""

    help_subtitle "核心功能"
    help_command "install"                         "安装 LEMP 栈或指定组件"
    help_command "pillar"                          "初始化 / 查看 / 刷新 Pillar 凭据"
    help_command "nginx"                           "站点与负载管理"
    help_command "maintenance"                     "系统维护、更新与清理"
    help_command "optimize"                        "系统 / Magento 优化"
    help_command "monitor"                         "系统与服务监控"
    help_command "magetools"                       "Magento 专用工具集"
    help_command "pwa"                             "PWA 部署与管理工具"
    help_command "analyse"                         "部署网站分析与可观测组件"
    help_command "git"                             "Git 快速发布工具"
    help_command "minio"                           "自托管对象存储部署/健康检查"
    help_command "postfix --smtp <名称> [--enable|--disable]" "切换 SMTP 帐号并可同步开启/关闭 Postfix"
    help_command "fun <status|joke|tip>"            "健康面板 + 趣味命令（详见 docs/OPS_TOOLING.md）"
    echo ""

    help_subtitle "诊断与状态"
    help_command "status"                          "查看关键服务运行状态"
    help_command "versions"                        "列出 SaltGoat 及依赖版本"
    help_command "passwords [--refresh]"           "查看或刷新服务密码"
    help_command "diagnose <type>"                 "故障诊断 (nginx/mysql/php/system/network/all)"
    help_command "profile analyze <type>"          "性能分析 (system/nginx/mysql/php/...)"
    help_command "version-lock <action>"           "版本锁定 (lock/unlock/show/status)"
    help_command "doctor"                          "汇总 Goat Pulse/磁盘/告警信息，输出本地体检报告"
    echo ""

    help_subtitle "质量与安全"
    help_command "lint [path]"                     "运行 shellcheck 进行静态检查"
    help_command "format [path]"                   "使用 shfmt 自动格式化"
    help_command "security-scan"                   "执行安全扫描与敏感文件检查"
    help_command "verify"                          "一键执行 scripts/code-review.sh 与 python3 -m unittest 自检"
    help_command "gitops-watch"                    "在 Git hook/CI 中运行 verify + monitor auto-sites --dry-run"
    help_command "smoke-suite"                     "执行 verify / monitor auto-sites / quick-check / doctor 快速冒烟"
    help_command "monitoring <type>"               "Prometheus / Grafana 等监控集成"
    echo ""

    help_subtitle "面板与证书"
    help_command "saltgui <action>"                "SaltGUI Web 面板管理"
    help_command "cockpit|adminer|uptime-kuma"     "系统/数据库/监控面板安装"
    help_command "ssl <action>"                    "证书申请、续期与备份"
    echo ""

    help_subtitle "常用示例"
    help_command "saltgoat pillar init"            "生成默认 Pillar 模板（自带随机密码）"
    help_command "saltgoat install all --optimize-magento" "安装并立即调优 Magento"
    help_command "saltgoat optimize magento --plan" "以 Dry-run 方式查看调优结果"
    help_command "saltgoat passwords --refresh"    "同步 Pillar 后重新应用核心状态"
    help_command "saltgoat help <command>"         "查看具体子命令帮助"
    echo ""
    help_note "完整文档与更多示例请参阅 README 与 docs/ 目录。"
}

# 分析平台帮助
show_analyse_help() {
    help_title "Analyse 分析平台"
    echo -e "用法: ${GREEN}saltgoat analyse <action> [options]${NC}"
    echo ""

    help_subtitle "当前可用组件"
    help_command "install matomo"                 "部署 Matomo (自托管网站分析平台)"
    echo ""

    help_subtitle "Matomo 安装配置"
    help_command "pillar matomo:install_dir"      "默认 /var/www/matomo"
    help_command "pillar matomo:domain"           "默认 matomo.local"
    help_command "pillar matomo:php_fpm_socket"   "默认 /run/php/php8.3-fpm.sock"
    help_note "可在 Pillar 的 matomo 节点中覆盖安装目录、域名、PHP-FPM 套接字等参数。"
    echo ""

    help_subtitle "数据库引导"
    help_command "--with-db"                      "启用数据库自动配置（默认使用 Pillar 中的 matomo:db.* 设置）"
    help_command "--db-name|--db-user|--db-host|--db-socket" "覆盖数据库名称/用户/主机/套接字"
    help_command "--db-provider <existing|mariadb>" "选择数据库提供者，existing 复用现有 MySQL/Percona，mariadb 将安装 MariaDB"
    help_command "--db-password"                  "覆盖数据库密码，未指定时自动生成随机密码"
    help_command "--db-admin-user|--db-admin-password" "用于创建数据库的管理账号；若系统存在 /etc/salt/mysql_saltuser.cnf 会自动读取 saltuser 凭据"
    help_command "--init-pillar"                  "若 Pillar 尚无 matomo 配置，自动写入默认块并刷新 Pillar"
    help_command "--install-dir <path>"            "覆盖安装目录（同时写入 Pillar matomo:install_dir）"
    help_command "--php-socket <path>"             "覆盖 PHP-FPM 套接字路径"
    help_command "--owner|--group <name>"          "自定义站点文件属主/属组，默认 www-data"
    help_note "首次执行可结合 --init-pillar --with-db，一次性写入 Pillar 并创建数据库/用户。"
    help_note "自动生成的数据库密码会写入 /var/lib/saltgoat/reports/matomo-db-password.txt，完成后请同步到 Pillar 并删除该文件。"
    echo ""

    help_subtitle "安装后步骤"
    help_command "1" "浏览 http://<域名>/ 进入 Matomo 安装向导"
    help_command "2" "若启用了 --with-db，可直接使用自动创建的数据库/用户信息"
    help_command "3" "如需 HTTPS，可在安装后执行 saltgoat nginx add-ssl"
    echo ""

    help_subtitle "常用命令"
    help_command "saltgoat analyse install matomo --with-db --init-pillar" "写入默认 Pillar、创建数据库后部署 Matomo"
    help_command "sudo salt-call --local state.apply optional.analyse" "在已有部署上重新应用配置"
    echo ""

    help_note "Matomo 安装包含 PHP 依赖、Nginx 虚拟主机和文件权限；--with-db 可选地预建数据库及授权。"
}

show_fun_help() {
    help_title "Fun 命令"
    echo -e "用法: ${GREEN}saltgoat fun <command> [options]${NC}"
    echo ""

    help_command "fun status [sites...]" "调用 scripts/health-panel.sh，输出 systemd/HTTP/磁盘三合一健康面板"
    help_command "fun joke"              "随机输出 SaltGoat 主题冷笑话（含 ASCII 山羊）"
    help_command "fun ascii"             "打印 ASCII 山羊 + 鼓励提示"
    help_command "fun tip"               "输出一个运维小贴士（提醒 varnish/backup/fail2ban 工具）"
    help_note "更多运维工具详见 docs/OPS_TOOLING.md。"
}

# 安装帮助
show_install_help() {
    help_title "安装向导"
    echo -e "用法: ${GREEN}saltgoat install <component> [options]${NC}"
    echo ""

    help_subtitle "组件包"
    help_command "all"                        "核心 LEMP + 可选服务（推荐，含 RabbitMQ/Valkey 等）"
    help_command "core"                       "仅安装 Nginx / PHP / MySQL（最小化环境）"
    help_command "optional"                   "补齐 Valkey、RabbitMQ、OpenSearch、Webmin 等附加服务"
    echo ""

    help_subtitle "常用选项"
    help_command "--skip-deps"                 "跳过依赖检查（自行准备依赖时使用）"
    help_command "--force"                     "强制重新部署组件，覆盖已有安装"
    help_command "--dry-run"                   "模拟安装流程，验证执行计划"
    help_command "--optimize-magento[=profile]" "安装完成后运行 Magento 优化（默认 auto）"
    help_command "--optimize-magento-profile"  "显式指定调优档位 (auto|low|standard|high...)"
    help_command "--optimize-magento-site"     "为优化报告标记站点名称，便于归档"
    echo ""

    help_subtitle "场景示例"
    help_command "saltgoat pillar init"        "首次部署：生成 Pillar 并写入随机密码"
    help_command "saltgoat install all"        "标准安装流程（推荐结合 Pillar 凭据）"
    help_command "saltgoat install all --optimize-magento" "一键部署并对 Magento 进行调优"
    help_command "saltgoat install optional --dry-run" "验证可选组件部署是否成功"
    help_note "所有凭据来自 Pillar（salt/pillar/saltgoat.sls），请先执行 \`saltgoat pillar init\`。"
}

# Pillar 帮助
show_pillar_help() {
    help_title "Pillar 配置管理"
    echo -e "用法: ${GREEN}saltgoat pillar <action>${NC}"
    echo ""
    help_subtitle "基础操作"
    help_command "init"                           "生成默认 Pillar 模板（随机密码、示例邮箱）"
    help_command "show"                           "查看当前 Pillar 内容（隐藏密码只显示哈希）"
    help_command "refresh"                        "刷新 Salt Pillar 缓存，立即生效最新配置"
    help_command "backup"                         "打包备份 salt/pillar 目录到 /var/lib/saltgoat/pillar-backups/"
    echo ""
    help_subtitle "凭据管理"
    help_command "saltgoat passwords"              "读取当前密码摘要（不输出明文）"
    help_command "saltgoat passwords --refresh"    "重置随机密码并重新应用相关状态"
    echo ""
    help_subtitle "示例"
    help_command "saltgoat pillar init"            "首次部署前生成模板并填写邮箱"
    help_command "saltgoat pillar show"            "安装前核对数据库/缓存等凭据"
    help_command "saltgoat pillar refresh"         "手动编辑 Pillar 后立即刷新缓存"
    help_note "Pillar 文件位于 ${SCRIPT_DIR}/salt/pillar/saltgoat.sls，请使用安全通道同步。"
}

show_minio_help() {
    help_title "MinIO 对象存储"
    echo -e "用法: ${GREEN}saltgoat minio <command>${NC}"
    echo ""

    help_subtitle "部署与配置"
    help_command "apply"                       "套用 optional.minio，创建用户/目录并注册 systemd 服务"
    help_command "info"                        "读取 Pillar 并输出 JSON 摘要（监听端口、凭据、健康端点）"
    help_command "env"                         "查看 /etc/minio/minio.env（需 sudo）"
    echo ""

    help_subtitle "运行维护"
    help_command "health"                      "调用 Pillar 中定义的 /minio/health/* URL，失败即退出非零"
    help_command "status"                      "systemctl status minio（含最近日志）"
    help_note "可通过变量 MINIO_HEALTH_TIMEOUT=10 saltgoat minio health 调整超时；Pillar 的 health.* 字段可自定义方案/主机/端口/路径。"
}

# Nginx帮助
show_nginx_help() {
    help_title "Nginx 站点与安全"
    echo -e "用法: ${GREEN}saltgoat nginx <action> [options]${NC}"
    echo ""

    help_subtitle "快速建站"
    help_command "create <site> \"dom1 dom2\" [path] [--magento]" "创建站点，支持多域名；加 --magento 自动套用 Magento 模板"
    help_command "list"                               "列出站点、根目录与证书状态"
    help_command "enable|disable <site>"              "立即切换站点上线/下线"
    help_command "delete <site>"                      "移除站点配置并清理符号链接"
    echo ""

    help_subtitle "运行操作"
    help_command "reload"                             "平滑重载 nginx，保持现有连接"
    help_command "test"                               "执行 nginx -t 语法检查"
    help_command "add-ssl <site> [domain] [email] [-dry-on]"   "申请或续期 Let's Encrypt（默认读取 Pillar 邮箱）"
    help_note "邮箱默认取自 salt/pillar/nginx.sls 的 ssl_email，可在命令后追加覆盖。"
    echo ""

    help_subtitle "安全强化"
    help_command "modsecurity level <0-10> [--admin-path /admin]" "调整 WAF 严格度（0 禁用，7 为生产推荐）"
    help_command "modsecurity status"                 "查看 WAF 等级与后台路径"
    help_command "csp level <0-5>"                    "设置 Content-Security-Policy 安全档位（0 禁用）"
    help_command "csp status"                         "检查当前 CSP 等级与策略摘要"
    echo ""

    help_subtitle "常用示例"
    help_command "saltgoat nginx create shop \"shop.com www.shop.com\" --magento" "建站 + Magento 配置模板"
    help_command "saltgoat nginx add-ssl shop \"shop.com\""             "申请 Let's Encrypt 证书"
    help_command "saltgoat nginx modsecurity level 7"                  "一键切换至严格 WAF"
    help_command "saltgoat nginx csp status"                           "检查 CSP 是否生效"
    help_note "需要自定义邮箱或 DNS 验证时，可先运行 \`saltgoat pillar show\` 确认 ssl_email。"
}

# 监控帮助
show_monitor_help() {
    help_title "运行状态与监控"
    echo -e "用法: ${GREEN}saltgoat monitor <type> [options]${NC}"
    echo ""

    help_subtitle "即时巡检"
    help_command "system"                        "CPU / 内存 / 磁盘占用与负载"
    help_command "services"                      "关键服务状态 + 最近重启次数"
    help_command "network"                       "连通性、丢包率与端口监控"
    help_command "logs"                          "聚合系统、nginx、php 等错误日志"
    help_command "security"                      "SSH、sudo、弱口令等基线检查"
    echo ""

    help_subtitle "深度分析"
    help_command "resources"                     "追踪内存热点、IO Wait、Top 进程"
    help_command "performance"                   "收集扩容建议所需的性能指标"
    help_command "report [daily|weekly]"         "生成 Markdown 报告至 reports/"
    help_command "realtime [seconds]"            "以 watch 模式实时刷新（默认 60s）"
    help_command "install"                       "安装 salt-minion 并同步事件监控栈"
    help_command "install-master"                "部署本地 salt-master 并写入默认配置"
    help_command "verify-master"                 "验证 salt-master / Reactor / Beacons"
    help_command "enable-beacons"                "一键启用 Salt Beacons + Reactor"
    help_command "beacons-status"                "查看 Beacon / Reactor / Schedule 状态"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat monitor install"      "首次部署 Salt 事件监控栈"
    help_command "saltgoat monitor install-master" "安装 salt-master 并执行功能验证"
    help_command "saltgoat monitor verify-master"  "复检已部署 master 与事件总线"
    help_command "saltgoat monitor system"       "例行巡检主机健康"
    help_command "saltgoat monitor report daily" "输出日报并存档"
    help_command "saltgoat monitor realtime 30"  "部署后短期监控瓶颈"
    help_command "saltgoat monitor enable-beacons" "启用服务自愈与资源告警"
    help_note "监控日志保存在 /var/log/saltgoat/monitor，事件告警写入 /var/log/saltgoat/alerts.log，可配合 Prometheus/Grafana 集成。"
}

# 维护帮助
show_maintenance_help() {
    help_title "系统维护与调整"
    echo -e "用法: ${GREEN}saltgoat maintenance <category> <action>${NC}"
    echo ""

    help_subtitle "🆙 系统更新"
    help_command "update check"                 "检查可用更新与 CVE 修复"
    help_command "update upgrade"               "常规 apt upgrade（保留配置）"
    help_command "update dist-upgrade"          "发行版级别升级"
    help_command "update autoremove|clean"      "清理旧内核与 apt 缓存"
    echo ""

    help_subtitle "服务管控"
    help_command "service status <name>"        "查看 systemd 状态与最近日志"
    help_command "service restart <name>"       "重启服务（失败自动回显日志）"
    help_command "service start|stop <name>"    "启动或停止任意受管服务"
    help_command "service reload <name>"        "重新加载配置（nginx/mysql 等）"
    echo ""

    help_subtitle "清理任务"
    help_command "cleanup logs|temp|cache"      "按类型清理日志/临时/缓存"
    help_command "cleanup all"                  "全量清理，适合发布前瘦身"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat maintenance update check"   "维护窗口前确认更新"
    help_command "saltgoat maintenance cleanup logs"   "释放日志占用空间"
    help_command "saltgoat maintenance service restart php8.3-fpm" "快速重启 PHP"
    help_note "建议在执行 update/cleanup 前先运行 \`saltgoat monitor system\` 观察资源趋势。"
}

# 优化帮助
show_optimize_help() {
    help_title "系统与 Magento 优化"
    echo -e "用法: ${GREEN}saltgoat optimize [type] [options]${NC}"
    echo ""

    help_subtitle "主要类型"
    help_command "(无参数)"                     "扫描主机资源并给出优化建议"
    help_command "magento"                       "应用 Magento 2 调优模板（结合 Pillar）"
    help_command "auto-tune"                     "根据 CPU / 内存自动调优 nginx/php/mysql 等"
    help_command "benchmark"                     "运行性能基准，输出评分与瓶颈提示"
    echo ""

    help_subtitle "Magento 专属参数"
    help_command "--profile <auto|low|...>"      "指定档位，默认 auto 依照内存选择"
    help_command "--site <name>"                 "在报告中标记站点名称，便于归档"
    help_command "--dry-run | --plan"            "仅模拟执行，显示将修改的配置"
    help_command "--show-results"                "打印最近一次优化报告摘要"
    echo ""

    help_subtitle "常用示例"
    help_command "saltgoat optimize"                               "获取整体优化建议"
    help_command "saltgoat optimize magento"                       "使用自动档位调优 Magento"
    help_command "saltgoat optimize magento --profile high --site shop01" "高性能档 + 标记站点"
    help_command "saltgoat optimize magento --plan --show-results" "Dry-run 并查看预期改动"
    help_command "saltgoat auto-tune"                              "快速根据资源执行调优"
    help_command "saltgoat benchmark"                              "记录基准分，比较变更前后"
    help_note "调优会生成报告保存于 /var/lib/saltgoat/reports，可配合 Git/工单留痕。"
}

# 速度测试帮助
show_speedtest_help() {
    help_title "网络速度测试"
    echo -e "用法: ${GREEN}saltgoat speedtest [action]${NC}"
    echo ""

    help_subtitle "测速模式"
    help_command "(无参数)"                     "完整测速：下载 / 上传 / 延迟 / 抖动"
    help_command "quick"                         "轻量测速：下载 + 延迟"
    help_command "server <id>"                   "指定服务器 ID，保持结果可比性"
    help_command "list"                          "列出可选服务器及所在城市"
    echo ""

    help_subtitle "常用示例"
    help_command "saltgoat speedtest"            "首次部署记录网络基线"
    help_command "saltgoat speedtest quick"      "例行巡检快速验证网络"
    help_command "saltgoat speedtest server 1234" "锁定到指定运营商节点测速"
    help_note "结果日志默认写入 /var/log/saltgoat/speedtest.log，便于追踪波动。"
}

# 完整帮助
show_complete_help() {
    help_title "SaltGoat 全量帮助"
    echo -e "版本: ${GREEN}${SCRIPT_VERSION}${NC}"
    echo ""

    show_install_help
    echo ""
    show_nginx_help
    echo ""
    show_analyse_help
    echo ""
    show_monitor_help
    echo ""
    show_maintenance_help
    echo ""
    show_optimize_help
    echo ""
    show_speedtest_help
    echo ""
    show_pillar_help
    echo ""
    show_monitoring_help
    echo ""
    show_ssl_help
    echo ""
    help_note "更多示例请查看 docs/ 目录以及 README 中的操作指南。"
}

# 显示监控集成帮助
show_monitoring_help() {
    local server_ip
    server_ip=$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
    help_title "监控集成"
    echo -e "用法: ${GREEN}saltgoat monitoring <prometheus|grafana|exporter>${NC}"
    echo ""

    help_subtitle "核心组件"
    help_command "prometheus"                   "安装 Prometheus Server（监听 9090）"
    help_command "grafana"                      "安装 Grafana（默认 admin/admin）"
    help_command "exporter"                     "部署 Node Exporter + 服务指标采集器"
    echo ""

    help_subtitle "默认访问"
    help_command "Prometheus"                   "http://${server_ip:-<server-ip>}:9090"
    help_command "Grafana"                      "http://${server_ip:-<server-ip>}:3000"
    help_note "首次登录 Grafana 后请立即修改密码，并添加 Prometheus 数据源。"
    echo ""

    help_subtitle "快速上手"
    help_command "saltgoat monitoring prometheus" "安装 Prometheus 并注册 systemd 服务"
    help_command "saltgoat monitoring grafana"    "部署 Grafana 并加载默认仪表板"
    help_command "saltgoat monitoring exporter"   "安装 Node Exporter（9100/tcp）"
    help_note "推荐 Dashboard：1860 / 12559 / 7362 / 11835（Grafana.com ID）。"
    echo ""

    help_subtitle "防火墙端口"
    help_command "Prometheus"                   "9090/tcp"
    help_command "Grafana"                      "3000/tcp"
    help_command "Node Exporter"                "9100/tcp"
}

# 故障诊断帮助
show_diagnose_help() {
    help_title "故障诊断"
    echo -e "用法: ${GREEN}saltgoat diagnose <nginx|mysql|php|system|network|all>${NC}"
    echo ""

    help_subtitle "诊断类型"
    help_command "nginx"                        "检查服务状态、配置语法与监听端口"
    help_command "mysql"                        "验证进程、权限、慢查询与磁盘空间"
    help_command "php"                          "检测 PHP-FPM 进程、配置与错误日志"
    help_command "system"                       "汇总内存、CPU、磁盘 IO 与内核日志"
    help_command "network"                      "测试 DNS / 路由 / 端口连通性"
    help_command "all"                          "执行完整诊断并生成报告"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat diagnose nginx"      "定位站点 502/504 等问题"
    help_command "saltgoat diagnose all"        "一键导出所有诊断细节"
    help_note "输出使用 OK 表示正常 / WARN 表示警告 / ERROR 表示失败，请按提示修复。"
}

# 性能分析帮助
show_profile_help() {
    help_title "性能画像与分析"
    echo -e "用法: ${GREEN}saltgoat profile analyze <type>${NC}"
    echo ""

    help_subtitle "分析范围"
    help_command "system"                       "收集 CPU/内存/磁盘/负载指标"
    help_command "nginx"                        "统计 QPS、连接数、错误率"
    help_command "mysql"                        "分析慢查询、Buffer Pool 命中率"
    help_command "php"                          "检查 PHP-FPM 队列、慢日志"
    help_command "memory|disk|network"          "针对单项资源进行深度分析"
    help_command "all"                          "生成全量性能报告（建议保留）"
    echo ""

    help_subtitle "评分标准"
    help_command "90-100"                       "优秀（绿色）"
    help_command "80-89"                        "良好（蓝色）"
    help_command "70-79"                        "一般（黄色）"
    help_command "<70"                          "需要优化（红色）"
    help_note "报告保存于 reports/ 目录，可与历史结果对比。"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat profile analyze system" "例行评估整体资源使用"
    help_command "saltgoat profile analyze all"    "生成综合性能报告"
}

# Magento工具帮助
show_magetools_help() {
    help_title "Magento 专用工具集"
    echo -e "用法: ${GREEN}saltgoat magetools <command> [options]${NC}"
    echo ""

    help_note "除 help 之外的 magetools 命令默认需要 root，请使用 'sudo saltgoat magetools ...'"
    echo ""

    help_subtitle "工具安装"
    help_command "install n98-magerun2"         "安装 N98 Magerun2 CLI（常用管理命令）"
    help_command "install phpunit"              "安装 PHPUnit 以运行单元测试"
    help_command "install xdebug"               "安装 Xdebug 调试扩展"
    echo ""

    help_subtitle "权限助手"
    help_command "permissions fix [path]"       "调用 Salt state 修复站点权限（默认当前目录）"
    help_command "permissions check [path]"     "使用 test=True 检查权限差异"
    help_command "permissions reset [path]"     "重新应用权限 state（操作前会确认）"
    help_note "命令内部执行 sudo salt-call state.apply optional.magento-permissions-* (pillar=site_path)；详见 docs/MAGENTO_PERMISSIONS.md。"
    echo ""

    help_subtitle "缓存 / 队列"
    help_command "valkey-check <site>"          "验证 Valkey 连接、密码与权限"
    help_command "rabbitmq-salt smart|all <site>" "使用 Salt 状态启用消费者（默认 1 线程）"
    help_command "rabbitmq-salt check <site>"     "对照 Pillar 检测 AMQP/消费者状态"
    help_command "rabbitmq-salt list <site|all>"  "列出指定站点或全局的 systemd unit"
    help_command "rabbitmq-salt remove <site>"    "停用消费者并清理 env.php queue 配置"
    help_command "varnish enable <site>"          "启用 Varnish（前端 Nginx → Varnish → backend Nginx/PHP）"
    help_command "varnish disable <site>"         "停用 Varnish 并恢复原始 Nginx/PHP 模式"
    help_command "varnish diagnose <site>"        "体检 Varnish/Nginx/Magento 关键配置（只读诊断）"
    help_note "旧版 \`rabbitmq all|smart|check\` 仍可用，但推荐迁移至 rabbitmq-salt。"
    help_note "Valkey/RabbitMQ 凭据来自 Pillar，可通过 \`saltgoat passwords\` 查看。"
    echo ""

    help_subtitle "主题管理"
    help_command "reset-theme <site> [locale ...]" "卸载自定义主题/模块并恢复官方主题（默认自动检测语言）"
    help_note "自动禁用 Codazon_* 及引用其类的模块、移除 app/code|app/design|vendor 目录并清理数据库引用，重新编译静态资源并 reload PHP-FPM；可追加语言，如 reset-theme tank ja_JP。"
    echo ""

    help_subtitle "备份"
    help_command "backup restic install"       "应用 Restic 可选模块（需在 Pillar 配置 backup.restic）"
    help_command "backup restic run"           "立即触发一次 Restic 备份"
    help_command "backup restic snapshots"     "列出 Restic 快照（需已启用模块）"
    help_command "backup restic logs 200"      "查看最近备份日志"
    help_command "backup restic summary"       "汇总所有站点的快照与服务状态"
    help_command "backup restic exec <cmd>"    "直接调用 restic（restore/mount/init 等）"
    help_note "大多数 Restic 命令涉及 /etc/restic，建议加 sudo 执行"
    help_note "install 支持 --site/--repo/--paths，脚本会自动安装 restic 并写入 Pillar，密码可通过 'saltgoat passwords --show' 查看"
    help_note "run 支持 --site/--paths/--backup-dir/--tag 等参数，可用于单站点/本地仓库快照"
    help_note "旧版本地备份可通过 \`saltgoat magetools backup magento\` 执行。"
    echo ""

    help_subtitle "数据库备份"
    help_command "xtrabackup mysql install"    "部署 Percona XtraBackup 自动化（需在 Pillar 配置 mysql_backup）"
    help_command "xtrabackup mysql run"        "即时触发一次数据库热备"
    help_command "xtrabackup mysql logs 200"   "查看数据库备份日志"
    help_command "xtrabackup mysql summary"    "汇总备份目录、容量与服务状态"
    help_command "xtrabackup mysql dump --database <name>" "导出单库 mysqldump，可带 --backup-dir / --repo-owner"
    help_note "数据库备份同样推荐使用 sudo，确保能读取 /etc/mysql/mysql-backup.env；旧命令 'backup mysql' 仍可用但已弃用"
    help_note "备份结果会按日期保存在 Pillar 指定目录，可配合 Restic 继续归档"
    echo ""

    help_subtitle "数据库管理"
    help_command "mysql create --database shopmage --user shop --password 'Passw0rd!'" "创建数据库与账号，默认授予 ALL + PROCESS/SUPER"
    help_note "可通过 --host/--charset/--collation/--no-super 调整参数"
    echo ""

    help_subtitle "业务洞察"
    help_command "stats --period daily --site bank" "汇总订单与新客户（支持 daily/weekly/monthly，可多站点）"
    help_command "stats --period weekly --site bank --no-telegram" "生成报表但仅输出到终端/日志，不推送 Telegram"
    echo ""

    help_subtitle "站点诊断"
    help_command "maintenance <site> daily|weekly|..." "通过 Salt 状态执行维护任务"
    help_command "cron status|enable <site>"    "查看或启用 magento cron 计划"
    help_command "schedule list|auto"           "自动检测并安装 Salt Schedule（多站点智能处理）"
    help_note "auto 会为缺省站点补齐 cron/php/health、API Watch、mysqldump、stats 任务，可再用 Pillar 精细化覆盖"
    help_command "monitor auto-sites"           "扫描站点生成 health check Pillar，仅在变更时刷新 Pillar/Telegram"
    help_command "monitor quick-check"          "立即执行一次资源 & 站点巡检并打印结果"
    help_command "migrate-detect <path>"        "检测站点迁移风险与遗留配置"
    help_command "opensearch-auth <site>"       "修复 Magento ↔ OpenSearch 鉴权"
    echo ""

    help_subtitle "常用示例"
    help_command "saltgoat magetools install n98-magerun2"          "部署 Magento CLI 工具组合"
    help_command "saltgoat magetools permissions fix /var/www/shop" "快速修复线上站点权限"
}

# PWA 工具帮助
show_pwa_help() {
    help_title "PWA 部署与管理"
    echo -e "用法: ${GREEN}saltgoat pwa <command> [options]${NC}"
    echo ""

    help_subtitle "核心命令"
    help_command "install <site> [--with-pwa|--no-pwa]" "读取 Pillar (magento-pwa.sls) 并一键部署 Magento + Venia PWA 前端"
    help_command "help"                          "显示本帮助"
    echo ""

    help_subtitle "选项说明"
    help_command "--with-pwa"                    "强制构建 PWA Studio，即便 Pillar 中未启用"
    help_command "--no-pwa"                      "跳过前端构建，仅部署后端"
    help_note "脚本会检测 Node/Yarn、创建数据库、执行 setup:install，并可按 Pillar 自动调用 valkey-setup / rabbitmq-salt / cron。"
    help_note "覆盖文件位于 modules/pwa/overrides/，用于保持 MOS GraphQL 兼容与本地定制。"
    echo ""

    help_subtitle "相关文档"
    help_command "docs/MAGENTO_PWA.md"          "安装流程与注意事项"
    help_command "docs/pwa-todo.md"             "UI 与 Page Builder 推进计划"
    echo ""

    help_note "旧命令 'saltgoat magetools pwa' 已兼容转发，请尽快迁移至新命名空间。"
}

# XtraBackup 帮助
show_xtrabackup_help() {
    help_title "Percona XtraBackup 自动化"
    echo -e "用法: ${GREEN}saltgoat magetools xtrabackup mysql <subcommand> [options]${NC}"
    echo ""

    help_subtitle "核心命令"
  help_command "install"                     "根据 Pillar 应用 optional.mysql-backup（启用 PXB 8.4 仓库）"
  help_command "run"                         "立即触发一次热备（systemd service oneshot）"
  help_command "status"                      "查看 service/timer 状态"
  help_command "logs [N]"                    "打印最近 N 行备份日志（默认 100）"
  help_command "summary"                     "汇总备份目录、容量与最近执行时间"
  help_command "dump --database <name>"      "mysqldump 导出单库，可指定 --backup-dir / --repo-owner / --no-compress"
    echo ""

    help_subtitle "前置要求"
    help_command "Pillar mysql_backup.*"       "需在 Pillar 中定义账号、目录、定时策略（示例见 docs/MYSQL_BACKUP.md）"
    help_command "mysql_password"              "root 凭据默认读取 pillar['mysql_password']"
    help_command "systemd"                     "安装流程会创建 saltgoat-mysql-backup.{service,timer}"
    help_note "首次执行 install 会自动启用 percona-release pxb-84-lts 仓库，并卸载旧版 PXB 套件。"
    echo ""

    help_subtitle "常用选项"
  help_command "--help"                      "查看 magetools 子命令帮助"
  help_command "backup mysql ..."            "兼容旧命令，仍会调用 xtrabackup 并给出迁移提示"
  help_command "--backup-dir <path>"         "dump 输出目录（默认 /var/backups/mysql/dumps）"
  help_command "--repo-owner <user>"         "导出文件的属主（默认读取 mysql-backup.env）"
  help_command "--no-compress"               "关闭 gzip，输出未压缩的 .sql 文件"
  help_note "所有命令建议加 sudo 运行，以读取 /etc/mysql/mysql-backup.env 与 systemd 资源。"
    echo ""

    help_subtitle "示例"
    help_command "sudo saltgoat magetools xtrabackup mysql install" "初始化备份账号、脚本与 systemd timer"
    help_command "sudo saltgoat magetools xtrabackup mysql run"     "立即执行一次热备并写入时间戳目录"
    help_command "sudo saltgoat magetools xtrabackup mysql summary" "巡检备份容量与最近执行时间"
    help_command "sudo saltgoat magetools backup mysql run"         "沿用旧命令，内部转发至 xtrabackup 流程"
    help_note "详细使用说明、恢复步骤与排错指南请参见 docs/MYSQL_BACKUP.md。"
}

# 版本锁定帮助
show_version_lock_help() {
    help_title "版本锁定"
    echo -e "用法: ${GREEN}saltgoat version-lock <lock|unlock|show|status>${NC}"
    echo ""

    help_subtitle "操作"
    help_command "lock"                        "锁定核心软件包版本，避免意外升级"
    help_command "unlock"                      "解除锁定，允许升级（升级完成后请再次 lock）"
    help_command "show"                        "列出当前锁定的包及 pin 优先级"
    help_command "status"                      "检查 apt pin 状态与锁定策略"
    echo ""

    help_subtitle "默认锁定范围"
    help_command "Web"                         "Nginx 1.29.1 + ModSecurity"
    help_command "Database"                    "Percona MySQL 8.4"
    help_command "PHP"                         "php8.3-fpm 及扩展"
    help_command "Cache/Search/Queue"          "Valkey 8 / OpenSearch 2.19 / RabbitMQ 4.1"
    help_command "Others"                      "Varnish 7.6、Composer 2.8 等关键组件"
    help_note "系统安全更新与通用工具仍可升级，锁定仅覆盖核心栈。"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat version-lock lock"    "锁定全部核心组件"
    help_command "saltgoat version-lock status"  "检查 pin 应用是否生效"
    help_command "saltgoat version-lock unlock"  "在升级前解除锁定"
    help_note "升级流程：unlock → apt upgrade → 功能验证 → lock。"
}

# Cockpit 帮助
show_cockpit_help() {
    help_title "Cockpit 系统面板"
    echo -e "用法: ${GREEN}saltgoat cockpit <command>${NC}"
    echo ""

    help_subtitle "运维操作"
    help_command "install"                     "安装 Cockpit 及常用插件（默认端口 9091）"
    help_command "uninstall"                   "卸载 Cockpit 并清理 systemd 服务"
    help_command "status"                      "查看服务状态与登录 URL"
    help_command "restart"                     "重启 Cockpit 服务"
    help_command "logs [lines]"                "查看最新日志（默认 50 行）"
    echo ""

    help_subtitle "配置管理"
    help_command "config show"                 "显示运行目录、端口、证书信息"
    help_command "config firewall"             "放通 9091/TCP 或自定义端口"
    help_command "config ssl"                  "生成自签证书并绑定到 Cockpit"
    help_note "首登请使用系统账户，并在 Cockpit UI 中启用双因素认证。"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat cockpit install"          "安装并自动向 UFW 开放端口"
    help_command "saltgoat cockpit config firewall"  "额外放通白名单 IP"
    help_command "saltgoat cockpit logs 100"         "查看最近 100 行访问日志"
}

# Adminer 帮助
show_adminer_help() {
    help_title "Adminer 数据库面板"
    echo -e "用法: ${GREEN}saltgoat adminer <command>${NC}"
    echo ""

    help_subtitle "运维操作"
    help_command "install"                     "安装 Adminer 并配置 Nginx/systemd"
    help_command "uninstall"                   "移除 Adminer 与关联配置"
    help_command "status"                      "查看运行状态与访问信息"
    help_command "restart"                     "重启 Adminer Nginx 虚拟主机（如有变更）"
    echo ""

    help_subtitle "配置选项"
    help_command "config show"                 "展示当前端口、路径与配置内容"
    help_command "config update"               "重新部署最新版本"
    help_command "config theme <name>"         "切换主题（默认 nette）"
    help_command "backup"                      "备份配置和凭据到 /var/backups/adminer"
    help_note "建议安装后立刻执行 \`saltgoat adminer security\`，启用基本认证与 IP 白名单。"
    echo ""

    help_subtitle "访问信息"
    help_command "UI"                          "http://your-server-ip:8081"
    help_command "登录入口"                     "http://your-server-ip:8081/login.php"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat adminer install"          "快速部署数据库面板"
    help_command "saltgoat adminer security"         "启用认证并限制来源 IP"
    help_command "saltgoat adminer config theme nette" "切换 Nette 主题"
}

# Uptime Kuma 帮助
show_uptime_kuma_help() {
    help_title "Uptime Kuma 状态面板"
    echo -e "用法: ${GREEN}saltgoat uptime-kuma <command>${NC}"
    echo ""

    help_subtitle "运维操作"
    help_command "install"                     "安装 Uptime Kuma（默认端口 3001）"
    help_command "uninstall"                   "卸载服务并移除数据目录"
    help_command "status"                      "查看运行状态、监听端口与数据目录"
    help_command "restart"                     "重启服务"
    help_command "logs [lines]"                "查看实时日志（默认 50 行）"
    echo ""

    help_subtitle "配置管理"
    help_command "config show"                 "显示安装目录、端口与用户"
    help_command "config port <number>"        "修改监听端口并重启服务"
    help_command "config update"               "更新到最新发行版"
    help_command "config backup|restore"       "备份或恢复监控配置"
    help_command "monitor"                     "导入 SaltGoat 默认监控项"
    help_note "默认账户 admin/admin，首次登录后请立即修改密码。"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat uptime-kuma install"        "部署面板并开放端口"
    help_command "saltgoat uptime-kuma config port 3002" "调整监听端口"
    help_command "saltgoat uptime-kuma monitor"        "导入核心组件监控模板"
}

# SSL 证书管理帮助
show_ssl_help() {
    help_title "SSL 证书管理"
    echo -e "用法: ${GREEN}saltgoat ssl <command>${NC}"
    echo ""

    help_subtitle "常规操作"
    help_command "generate-self-signed <domain> [days]" "创建自签证书用于测试"
    help_command "generate-csr <domain> <C> <ST> <L> <O>" "生成提交 CA 的 CSR 文件"
    help_command "view <cert>"                          "查看证书详情与有效期"
    help_command "verify <cert> <domain>"               "验证证书链与域名匹配"
    help_command "list"                                 "列出已部署证书"
    help_command "status"                               "输出摘要与即将过期提醒"
    echo ""

    help_subtitle "生命周期"
    help_command "renew <domain> [method]"              "续期证书（支持自签/Let’s Encrypt）"
    help_command "backup [name]"                        "备份证书到 /var/backups/ssl"
    help_command "cleanup-expired [days]"               "清理超过指定天数的过期证书"
    help_note "默认目录：/etc/ssl/certs, /etc/ssl/private, /etc/ssl/csr, /var/backups/ssl。"
    echo ""

    help_subtitle "Let’s Encrypt 集成"
    help_command "saltgoat nginx add-ssl <site> [domain] [email] [-dry-on]" "结合 Nginx 虚拟主机申请/续期证书"
    help_command "saltgoat ssl renew <domain> letsencrypt"        "手动触发 certbot 续期流程"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat ssl generate-self-signed shop.com 365" "生成一年期测试证书"
    help_command "saltgoat ssl view /etc/ssl/certs/shop.com.crt"  "查看证书信息"
    help_command "saltgoat ssl cleanup-expired 30"                "清理 30 天前的过期证书"
    help_note "Let’s Encrypt 需域名指向服务器，成功申请后请 reload nginx 使证书生效。"
}
