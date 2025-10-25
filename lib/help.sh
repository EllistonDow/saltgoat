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
        "database")
            show_database_help
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

    help_subtitle "核心功能"
    help_command "install"                         "安装 LEMP 栈或指定组件"
    help_command "pillar"                          "初始化 / 查看 / 刷新 Pillar 凭据"
    help_command "nginx"                           "站点与负载管理"
    help_command "database"                        "MySQL、Valkey 运维工具"
    help_command "maintenance"                     "系统维护、更新与清理"
    help_command "optimize"                        "系统 / Magento 优化"
    help_command "monitor"                         "系统与服务监控"
    help_command "magetools"                       "Magento 专用工具集"
    help_command "analyse"                         "部署网站分析与可观测组件"
    help_command "git"                             "Git 快速发布工具"
    echo ""

    help_subtitle "诊断与状态"
    help_command "status"                          "查看关键服务运行状态"
    help_command "versions"                        "列出 SaltGoat 及依赖版本"
    help_command "passwords [--refresh]"           "查看或刷新服务密码"
    help_command "diagnose <type>"                 "故障诊断 (nginx/mysql/php/system/network/all)"
    help_command "profile analyze <type>"          "性能分析 (system/nginx/mysql/php/...)"
    help_command "version-lock <action>"           "版本锁定 (lock/unlock/show/status)"
    echo ""

    help_subtitle "质量与安全"
    help_command "lint [path]"                     "运行 shellcheck 进行静态检查"
    help_command "format [path]"                   "使用 shfmt 自动格式化"
    help_command "security-scan"                   "执行安全扫描与敏感文件检查"
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

    help_subtitle "📦 当前可用组件"
    help_command "install matomo"                 "部署 Matomo (自托管网站分析平台)"
    echo ""

    help_subtitle "⚙️ Matomo 安装配置"
    help_command "pillar matomo:install_dir"      "默认 /var/www/matomo"
    help_command "pillar matomo:domain"           "默认 matomo.local"
    help_command "pillar matomo:php_fpm_socket"   "默认 /run/php/php8.3-fpm.sock"
    help_note "可在 Pillar 的 matomo 节点中覆盖安装目录、域名、PHP-FPM 套接字等参数。"
    echo ""

    help_subtitle "📋 安装后步骤"
    help_command "1" "浏览 http://<域名>/ 进入 Matomo 安装向导"
    help_command "2" "使用现有 MySQL 凭据创建数据库并完成配置"
    help_command "3" "如需 HTTPS，可在安装后执行 saltgoat nginx add-ssl"
    echo ""

    help_subtitle "🛠 常用命令"
    help_command "saltgoat analyse install matomo" "部署 Matomo 及其依赖、Nginx 虚拟主机"
    help_command "sudo salt-call --local state.apply optional.matomo" "在已有部署上重新应用配置"
    echo ""

    help_note "Matomo 安装包含 PHP 依赖、Nginx 虚拟主机和文件权限。数据库创建需在向导中完成。"
}

# 安装帮助
show_install_help() {
    help_title "安装向导"
    echo -e "用法: ${GREEN}saltgoat install <component> [options]${NC}"
    echo ""

    help_subtitle "🧩 组件包"
    help_command "all"                        "核心 LEMP + 可选服务（推荐，含 RabbitMQ/Valkey 等）"
    help_command "core"                       "仅安装 Nginx / PHP / MySQL（最小化环境）"
    help_command "optional"                   "补齐 Valkey、RabbitMQ、OpenSearch、Webmin 等附加服务"
    echo ""

    help_subtitle "⚙️ 常用选项"
    help_command "--skip-deps"                 "跳过依赖检查（自行准备依赖时使用）"
    help_command "--force"                     "强制重新部署组件，覆盖已有安装"
    help_command "--dry-run"                   "模拟安装流程，验证执行计划"
    help_command "--optimize-magento[=profile]" "安装完成后运行 Magento 优化（默认 auto）"
    help_command "--optimize-magento-profile"  "显式指定调优档位 (auto|low|standard|high...)"
    help_command "--optimize-magento-site"     "为优化报告标记站点名称，便于归档"
    echo ""

    help_subtitle "📋 场景示例"
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
    help_subtitle "🛠 基础操作"
    help_command "init"                           "生成默认 Pillar 模板（随机密码、示例邮箱）"
    help_command "show"                           "查看当前 Pillar 内容（隐藏密码只显示哈希）"
    help_command "refresh"                        "刷新 Salt Pillar 缓存，立即生效最新配置"
    echo ""
    help_subtitle "🔐 凭据管理"
    help_command "saltgoat passwords"              "读取当前密码摘要（不输出明文）"
    help_command "saltgoat passwords --refresh"    "重置随机密码并重新应用相关状态"
    echo ""
    help_subtitle "📋 示例"
    help_command "saltgoat pillar init"            "首次部署前生成模板并填写邮箱"
    help_command "saltgoat pillar show"            "安装前核对数据库/缓存等凭据"
    help_command "saltgoat pillar refresh"         "手动编辑 Pillar 后立即刷新缓存"
    help_note "Pillar 文件位于 ${SCRIPT_DIR}/salt/pillar/saltgoat.sls，请使用安全通道同步。"
}

# Nginx帮助
show_nginx_help() {
    help_title "Nginx 站点与安全"
    echo -e "用法: ${GREEN}saltgoat nginx <action> [options]${NC}"
    echo ""

    help_subtitle "🚀 快速建站"
    help_command "create <site> \"dom1 dom2\" [path]" "创建站点并一次性绑定多域名"
    help_command "list"                               "列出站点、根目录与证书状态"
    help_command "enable|disable <site>"              "立即切换站点上线/下线"
    help_command "delete <site>"                      "移除站点配置并清理符号链接"
    echo ""

    help_subtitle "🛠 运行操作"
    help_command "reload"                             "平滑重载 nginx，保持现有连接"
    help_command "test"                               "执行 nginx -t 语法检查"
    help_command "add-ssl <site> <domains> [email]"   "申请或续期 Let's Encrypt（默认使用 Pillar 邮箱）"
    echo ""

    help_subtitle "🛡️ 安全强化"
    help_command "modsecurity level <1-10>"           "调整 WAF 严格度（7 为生产推荐）"
    help_command "modsecurity status"                 "查看规则版本与命中统计"
    help_command "csp level <1-5>"                    "设置 Content-Security-Policy 安全档位"
    help_command "csp enable|disable"                 "启用/禁用 CSP 与 ModSecurity"
    echo ""

    help_subtitle "📋 常用示例"
    help_command "saltgoat nginx create shop \"shop.com www.shop.com\"" "建站 + 多域名指向"
    help_command "saltgoat nginx add-ssl shop \"shop.com\""             "申请 Let's Encrypt 证书"
    help_command "saltgoat nginx modsecurity level 7"                  "一键切换至严格 WAF"
    help_command "saltgoat nginx csp status"                           "检查 CSP 是否生效"
    help_note "需要自定义邮箱或 DNS 验证时，可先运行 \`saltgoat pillar show\` 确认 ssl_email。"
}

# 数据库帮助
show_database_help() {
    help_title "数据库与缓存管理"
    echo -e "用法: ${GREEN}saltgoat database <mysql|valkey> <action> [options]${NC}"
    echo ""

    help_subtitle "🗄️ MySQL 常用操作"
    help_command "create <dbname>"                 "按 Pillar 凭据创建库与用户"
    help_command "list"                            "列出数据库 / 字符集 / 大小"
    help_command "status"                          "查看版本、连接数、InnoDB 摘要"
    help_command "delete <dbname>"                 "移除数据库并撤销权限"
    echo ""

    help_subtitle "💾 备份 & 恢复"
    help_command "backup <dbname> [name]"          "mysqldump + gzip，默认入 /var/backups/mysql"
    help_command "restore <dbname> <file>"         "支持 .sql 与 .sql.gz 自动识别"
    help_command "cleanup-backups [days]"          "清理过期备份并统计空间"
    echo ""

    help_subtitle "⚡ Valkey (Redis 兼容)"
    help_command "create <name>"                   "创建命名空间并记录在 Pillar"
    help_command "list"                            "查看命名空间、DB 映射与内存"
    help_command "flush <name>"                    "清空指定命名空间数据"
    help_command "stats"                           "输出命中率、最大内存与策略"
    echo ""

    help_subtitle "📋 常用场景"
    help_command "saltgoat database mysql backup magento"  "滚动备份应用数据库"
    help_command "saltgoat database mysql status"          "上线前确认数据库健康"
    help_command "saltgoat database valkey stats"          "验证缓存命中情况"
    help_note "所有敏感凭据来自 Pillar，可通过 \`saltgoat passwords --refresh\` 重新同步。"
}

# 监控帮助
show_monitor_help() {
    help_title "运行状态与监控"
    echo -e "用法: ${GREEN}saltgoat monitor <type> [options]${NC}"
    echo ""

    help_subtitle "🧩 即时巡检"
    help_command "system"                        "CPU / 内存 / 磁盘占用与负载"
    help_command "services"                      "关键服务状态 + 最近重启次数"
    help_command "network"                       "连通性、丢包率与端口监控"
    help_command "logs"                          "聚合系统、nginx、php 等错误日志"
    help_command "security"                      "SSH、sudo、弱口令等基线检查"
    echo ""

    help_subtitle "📈 深度分析"
    help_command "resources"                     "追踪内存热点、IO Wait、Top 进程"
    help_command "performance"                   "收集扩容建议所需的性能指标"
    help_command "report [daily|weekly]"         "生成 Markdown 报告至 reports/"
    help_command "realtime [seconds]"            "以 watch 模式实时刷新（默认 60s）"
    echo ""

    help_subtitle "📋 示例"
    help_command "saltgoat monitor system"       "例行巡检主机健康"
    help_command "saltgoat monitor report daily" "输出日报并存档"
    help_command "saltgoat monitor realtime 30"  "部署后短期监控瓶颈"
    help_note "监控日志保存在 /var/log/saltgoat/monitor，可配合 Prometheus/Grafana 集成。"
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

    help_subtitle "⚙️ 服务管控"
    help_command "service status <name>"        "查看 systemd 状态与最近日志"
    help_command "service restart <name>"       "重启服务（失败自动回显日志）"
    help_command "service start|stop <name>"    "启动或停止任意受管服务"
    help_command "service reload <name>"        "重新加载配置（nginx/mysql 等）"
    echo ""

    help_subtitle "🧹 清理任务"
    help_command "cleanup logs|temp|cache"      "按类型清理日志/临时/缓存"
    help_command "cleanup all"                  "全量清理，适合发布前瘦身"
    echo ""

    help_subtitle "📋 示例"
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

    help_subtitle "⚙️ 主要类型"
    help_command "(无参数)"                     "扫描主机资源并给出优化建议"
    help_command "magento"                       "应用 Magento 2 调优模板（结合 Pillar）"
    help_command "auto-tune"                     "根据 CPU / 内存自动调优 nginx/php/mysql 等"
    help_command "benchmark"                     "运行性能基准，输出评分与瓶颈提示"
    echo ""

    help_subtitle "🛒 Magento 专属参数"
    help_command "--profile <auto|low|...>"      "指定档位，默认 auto 依照内存选择"
    help_command "--site <name>"                 "在报告中标记站点名称，便于归档"
    help_command "--dry-run | --plan"            "仅模拟执行，显示将修改的配置"
    help_command "--show-results"                "打印最近一次优化报告摘要"
    echo ""

    help_subtitle "📋 常用示例"
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

    help_subtitle "🌐 测速模式"
    help_command "(无参数)"                     "完整测速：下载 / 上传 / 延迟 / 抖动"
    help_command "quick"                         "轻量测速：下载 + 延迟"
    help_command "server <id>"                   "指定服务器 ID，保持结果可比性"
    help_command "list"                          "列出可选服务器及所在城市"
    echo ""

    help_subtitle "📋 常用示例"
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
    show_database_help
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

    help_subtitle "📊 核心组件"
    help_command "prometheus"                   "安装 Prometheus Server（监听 9090）"
    help_command "grafana"                      "安装 Grafana（默认 admin/admin）"
    help_command "exporter"                     "部署 Node Exporter + 服务指标采集器"
    echo ""

    help_subtitle "🌐 默认访问"
    help_command "Prometheus"                   "http://${server_ip:-<server-ip>}:9090"
    help_command "Grafana"                      "http://${server_ip:-<server-ip>}:3000"
    help_note "首次登录 Grafana 后请立即修改密码，并添加 Prometheus 数据源。"
    echo ""

    help_subtitle "🚀 快速上手"
    help_command "saltgoat monitoring prometheus" "安装 Prometheus 并注册 systemd 服务"
    help_command "saltgoat monitoring grafana"    "部署 Grafana 并加载默认仪表板"
    help_command "saltgoat monitoring exporter"   "安装 Node Exporter（9100/tcp）"
    help_note "推荐 Dashboard：1860 / 12559 / 7362 / 11835（Grafana.com ID）。"
    echo ""

    help_subtitle "🛡️ 防火墙端口"
    help_command "Prometheus"                   "9090/tcp"
    help_command "Grafana"                      "3000/tcp"
    help_command "Node Exporter"                "9100/tcp"
}

# 故障诊断帮助
show_diagnose_help() {
    help_title "故障诊断"
    echo -e "用法: ${GREEN}saltgoat diagnose <nginx|mysql|php|system|network|all>${NC}"
    echo ""

    help_subtitle "🩺 诊断类型"
    help_command "nginx"                        "检查服务状态、配置语法与监听端口"
    help_command "mysql"                        "验证进程、权限、慢查询与磁盘空间"
    help_command "php"                          "检测 PHP-FPM 进程、配置与错误日志"
    help_command "system"                       "汇总内存、CPU、磁盘 IO 与内核日志"
    help_command "network"                      "测试 DNS / 路由 / 端口连通性"
    help_command "all"                          "执行完整诊断并生成报告"
    echo ""

    help_subtitle "📋 示例"
    help_command "saltgoat diagnose nginx"      "定位站点 502/504 等问题"
    help_command "saltgoat diagnose all"        "一键导出所有诊断细节"
    help_note "输出使用 ✅ 正常 / ⚠️ 警告 / ❌ 错误，请按提示修复。"
}

# 性能分析帮助
show_profile_help() {
    help_title "性能画像与分析"
    echo -e "用法: ${GREEN}saltgoat profile analyze <type>${NC}"
    echo ""

    help_subtitle "📈 分析范围"
    help_command "system"                       "收集 CPU/内存/磁盘/负载指标"
    help_command "nginx"                        "统计 QPS、连接数、错误率"
    help_command "mysql"                        "分析慢查询、Buffer Pool 命中率"
    help_command "php"                          "检查 PHP-FPM 队列、慢日志"
    help_command "memory|disk|network"          "针对单项资源进行深度分析"
    help_command "all"                          "生成全量性能报告（建议保留）"
    echo ""

    help_subtitle "🏅 评分标准"
    help_command "90-100"                       "优秀（绿色）"
    help_command "80-89"                        "良好（蓝色）"
    help_command "70-79"                        "一般（黄色）"
    help_command "<70"                          "需要优化（红色）"
    help_note "报告保存于 reports/ 目录，可与历史结果对比。"
    echo ""

    help_subtitle "📋 示例"
    help_command "saltgoat profile analyze system" "例行评估整体资源使用"
    help_command "saltgoat profile analyze all"    "生成综合性能报告"
}

# Magento工具帮助
show_magetools_help() {
    help_title "Magento 专用工具集"
    echo -e "用法: ${GREEN}saltgoat magetools <command> [options]${NC}"
    echo ""

    help_subtitle "🧰 工具安装"
    help_command "install n98-magerun2"         "安装 N98 Magerun2 CLI（常用管理命令）"
    help_command "install phpunit"              "安装 PHPUnit 以运行单元测试"
    help_command "install xdebug"               "安装 Xdebug 调试扩展"
    echo ""

    help_subtitle "🛡️ 权限助手"
    help_command "permissions fix [path]"       "修复目录权限（默认当前目录）"
    help_command "permissions check [path]"     "检测文件/目录权限异常"
    help_command "permissions reset [path]"     "重置为官方推荐权限"
    help_note "操作 Magento CLI 时请使用 \`sudo -u www-data php bin/magento\`，详见 docs/MAGENTO_PERMISSIONS.md。"
    echo ""

    help_subtitle "📦 配置转换"
    help_command "convert magento2"             "将 Nginx 虚拟主机自动转换为 Magento 模板"
    help_command "convert check"                "校验站点是否满足 Magento2 要求"
    echo ""

    help_subtitle "⚡ 缓存 / 队列"
    help_command "valkey-renew <site>"          "重新分配 Valkey 数据库并更新 env.php"
    help_command "valkey-check <site>"          "验证 Valkey 连接、密码与权限"
    help_command "rabbitmq all <site> [threads]"   "部署全部消费者（21 个），可设线程数"
    help_command "rabbitmq smart <site> [threads]" "只启用核心消费者，低资源模式"
    help_command "rabbitmq check <site>"           "检查队列堆积与消费者状态"
    help_note "Valkey/RabbitMQ 凭据来自 Pillar，可通过 \`saltgoat passwords\` 查看。"
    echo ""

    help_subtitle "🩺 站点诊断"
    help_command "cron status|enable <site>"    "查看或启用 magento cron 计划"
    help_command "migrate-detect <path>"        "检测站点迁移风险与遗留配置"
    help_command "opensearch-auth <site>"       "修复 Magento ↔ OpenSearch 鉴权"
    echo ""

    help_subtitle "📋 常用示例"
    help_command "saltgoat magetools install n98-magerun2"          "部署 Magento CLI 工具组合"
    help_command "saltgoat magetools permissions fix /var/www/shop" "快速修复线上站点权限"
    help_command "saltgoat magetools valkey-renew shop"             "为站点重新绑定缓存库"
    help_command "saltgoat magetools rabbitmq smart shop 4"         "按需启用消费者并限制线程数"
}

# 版本锁定帮助
show_version_lock_help() {
    help_title "版本锁定"
    echo -e "用法: ${GREEN}saltgoat version-lock <lock|unlock|show|status>${NC}"
    echo ""

    help_subtitle "🔒 操作"
    help_command "lock"                        "锁定核心软件包版本，避免意外升级"
    help_command "unlock"                      "解除锁定，允许升级（升级完成后请再次 lock）"
    help_command "show"                        "列出当前锁定的包及 pin 优先级"
    help_command "status"                      "检查 apt pin 状态与锁定策略"
    echo ""

    help_subtitle "📦 默认锁定范围"
    help_command "Web"                         "Nginx 1.29.1 + ModSecurity"
    help_command "Database"                    "Percona MySQL 8.4"
    help_command "PHP"                         "php8.3-fpm 及扩展"
    help_command "Cache/Search/Queue"          "Valkey 8 / OpenSearch 2.19 / RabbitMQ 4.1"
    help_command "Others"                      "Varnish 7.6、Composer 2.8 等关键组件"
    help_note "系统安全更新与通用工具仍可升级，锁定仅覆盖核心栈。"
    echo ""

    help_subtitle "📋 示例"
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

    help_subtitle "⚙️ 运维操作"
    help_command "install"                     "安装 Cockpit 及常用插件（默认端口 9091）"
    help_command "uninstall"                   "卸载 Cockpit 并清理 systemd 服务"
    help_command "status"                      "查看服务状态与登录 URL"
    help_command "restart"                     "重启 Cockpit 服务"
    help_command "logs [lines]"                "查看最新日志（默认 50 行）"
    echo ""

    help_subtitle "🔐 配置管理"
    help_command "config show"                 "显示运行目录、端口、证书信息"
    help_command "config firewall"             "放通 9091/TCP 或自定义端口"
    help_command "config ssl"                  "生成自签证书并绑定到 Cockpit"
    help_note "首登请使用系统账户，并在 Cockpit UI 中启用双因素认证。"
    echo ""

    help_subtitle "📋 示例"
    help_command "saltgoat cockpit install"          "安装并自动向 UFW 开放端口"
    help_command "saltgoat cockpit config firewall"  "额外放通白名单 IP"
    help_command "saltgoat cockpit logs 100"         "查看最近 100 行访问日志"
}

# Adminer 帮助
show_adminer_help() {
    help_title "Adminer 数据库面板"
    echo -e "用法: ${GREEN}saltgoat adminer <command>${NC}"
    echo ""

    help_subtitle "⚙️ 运维操作"
    help_command "install"                     "安装 Adminer 并配置 Nginx/systemd"
    help_command "uninstall"                   "移除 Adminer 与关联配置"
    help_command "status"                      "查看运行状态与访问信息"
    help_command "restart"                     "重启 Adminer Nginx 虚拟主机（如有变更）"
    echo ""

    help_subtitle "🎨 配置选项"
    help_command "config show"                 "展示当前端口、路径与配置内容"
    help_command "config update"               "重新部署最新版本"
    help_command "config theme <name>"         "切换主题（默认 nette）"
    help_command "backup"                      "备份配置和凭据到 /var/backups/adminer"
    help_note "建议安装后立刻执行 \`saltgoat adminer security\`，启用基本认证与 IP 白名单。"
    echo ""

    help_subtitle "🌐 访问信息"
    help_command "UI"                          "http://your-server-ip:8081"
    help_command "登录入口"                     "http://your-server-ip:8081/login.php"
    echo ""

    help_subtitle "📋 示例"
    help_command "saltgoat adminer install"          "快速部署数据库面板"
    help_command "saltgoat adminer security"         "启用认证并限制来源 IP"
    help_command "saltgoat adminer config theme nette" "切换 Nette 主题"
}

# Uptime Kuma 帮助
show_uptime_kuma_help() {
    help_title "Uptime Kuma 状态面板"
    echo -e "用法: ${GREEN}saltgoat uptime-kuma <command>${NC}"
    echo ""

    help_subtitle "⚙️ 运维操作"
    help_command "install"                     "安装 Uptime Kuma（默认端口 3001）"
    help_command "uninstall"                   "卸载服务并移除数据目录"
    help_command "status"                      "查看运行状态、监听端口与数据目录"
    help_command "restart"                     "重启服务"
    help_command "logs [lines]"                "查看实时日志（默认 50 行）"
    echo ""

    help_subtitle "🗃 配置管理"
    help_command "config show"                 "显示安装目录、端口与用户"
    help_command "config port <number>"        "修改监听端口并重启服务"
    help_command "config update"               "更新到最新发行版"
    help_command "config backup|restore"       "备份或恢复监控配置"
    help_command "monitor"                     "导入 SaltGoat 默认监控项"
    help_note "默认账户 admin/admin，首次登录后请立即修改密码。"
    echo ""

    help_subtitle "📋 示例"
    help_command "saltgoat uptime-kuma install"        "部署面板并开放端口"
    help_command "saltgoat uptime-kuma config port 3002" "调整监听端口"
    help_command "saltgoat uptime-kuma monitor"        "导入核心组件监控模板"
}

# SSL 证书管理帮助
show_ssl_help() {
    help_title "SSL 证书管理"
    echo -e "用法: ${GREEN}saltgoat ssl <command>${NC}"
    echo ""

    help_subtitle "🧾 常规操作"
    help_command "generate-self-signed <domain> [days]" "创建自签证书用于测试"
    help_command "generate-csr <domain> <C> <ST> <L> <O>" "生成提交 CA 的 CSR 文件"
    help_command "view <cert>"                          "查看证书详情与有效期"
    help_command "verify <cert> <domain>"               "验证证书链与域名匹配"
    help_command "list"                                 "列出已部署证书"
    help_command "status"                               "输出摘要与即将过期提醒"
    echo ""

    help_subtitle "🔁 生命周期"
    help_command "renew <domain> [method]"              "续期证书（支持自签/Let’s Encrypt）"
    help_command "backup [name]"                        "备份证书到 /var/backups/ssl"
    help_command "cleanup-expired [days]"               "清理超过指定天数的过期证书"
    help_note "默认目录：/etc/ssl/certs, /etc/ssl/private, /etc/ssl/csr, /var/backups/ssl。"
    echo ""

    help_subtitle "🔐 Let’s Encrypt 集成"
    help_command "saltgoat nginx add-ssl <site> <domain> [email]" "结合 Nginx 虚拟主机申请/续期证书"
    help_command "saltgoat ssl renew <domain> letsencrypt"        "手动触发 certbot 续期流程"
    echo ""

    help_subtitle "📋 示例"
    help_command "saltgoat ssl generate-self-signed shop.com 365" "生成一年期测试证书"
    help_command "saltgoat ssl view /etc/ssl/certs/shop.com.crt"  "查看证书信息"
    help_command "saltgoat ssl cleanup-expired 30"                "清理 30 天前的过期证书"
    help_note "Let’s Encrypt 需域名指向服务器，成功申请后请 reload nginx 使证书生效。"
}
