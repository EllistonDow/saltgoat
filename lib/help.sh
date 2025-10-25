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

# 安装帮助
show_install_help() {
    help_title "安装功能"
    echo -e "用法: ${GREEN}saltgoat install <component> [options]${NC}"
    echo ""

    help_subtitle "组件"
    help_command "all"        "安装核心 + 可选组件（推荐使用 Pillar 密码）"
    help_command "core"       "仅安装 Nginx / PHP / MySQL"
    help_command "optional"   "部署 Valkey、RabbitMQ、OpenSearch、Webmin 等"
    echo ""

    help_subtitle "常用选项"
    help_command "--skip-deps"                 "跳过依赖检查（自备环境时使用）"
    help_command "--force"                     "强制重新安装对应组件"
    help_command "--dry-run"                   "模拟安装流程（不写入系统）"
    help_command "--optimize-magento[=profile]" "安装完成后执行 Magento 调优，可指定档位"
    help_command "--optimize-magento-profile"  "显式设置调优档位 (auto|low|standard|... )"
    help_command "--optimize-magento-site"     "为生成的报告记录站点名称"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat pillar init"        "生成默认 Pillar（包含随机密码）"
    help_command "saltgoat install all"        "使用 Pillar 值安装所有组件"
    help_command "saltgoat install all --optimize-magento" "安装后自动调优 Magento"
    help_command "saltgoat install optional --dry-run" "验证可选组件的安装流程"
}

# Pillar 帮助
show_pillar_help() {
    help_title "Pillar 配置管理"
    echo -e "用法: ${GREEN}saltgoat pillar <action>${NC}"
    echo ""
    help_subtitle "操作"
    help_command "init"       "生成默认 Pillar 模板（包含随机密码与示例邮箱）"
    help_command "show"       "查看当前 Pillar 内容"
    help_command "refresh"    "刷新 Salt Pillar 缓存"
    echo ""
    help_subtitle "示例"
    help_command "saltgoat pillar init"        "首次部署前生成模板"
    help_command "saltgoat pillar show"        "安装前确认密码与邮箱设置"
    help_command "saltgoat pillar refresh"     "手动编辑后立即刷新缓存"
    help_note "Pillar 文件位于 ${SCRIPT_DIR}/salt/pillar/saltgoat.sls，务必妥善保管"
}

# Nginx帮助
show_nginx_help() {
    help_title "Nginx 站点与安全"
    echo -e "用法: ${GREEN}saltgoat nginx <action> [options]${NC}"
    echo ""

    help_subtitle "站点管理"
    help_command "create <site> <domains> [path]"  "创建新站点，支持多域名映射"
    help_command "delete <site>"                   "删除站点并移除配置"
    help_command "list"                            "列出站点及根目录"
    help_command "enable|disable <site>"           "启用或禁用站点"
    help_command "reload"                          "重新加载 Nginx 配置"
    help_command "test"                            "执行 nginx -t 语法检查"
    echo ""

    help_subtitle "证书管理"
    help_command "add-ssl <site> <domains> [email]" "申请/续期 Let's Encrypt 证书（默认使用 Pillar 邮箱）"
    echo ""

    help_subtitle "ModSecurity"
    help_command "modsecurity level <1-10>"        "调整规则严格度（7 推荐生产）"
    help_command "modsecurity status"              "查看当前 ModSecurity 状态"
    help_command "modsecurity enable|disable"      "启用或禁用 ModSecurity"
    echo ""

    help_subtitle "Content-Security-Policy"
    help_command "csp level <1-5>"                 "设置 CSP 安全等级（1 宽松 / 5 最严格）"
    help_command "csp status"                      "查看当前 CSP 状态摘要"
    help_command "csp enable|disable"              "启用或禁用 CSP 管控"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat nginx create shop \"shop.com www.shop.com\"" "创建站点并绑定多域名"
    help_command "saltgoat nginx add-ssl shop \"shop.com www.shop.com\"" "使用默认邮箱申请证书"
    help_command "saltgoat nginx modsecurity level 7"                   "强化 Web 应用防火墙"
    help_command "saltgoat nginx csp status"                            "快速核对当前 CSP 配置"
}

# 数据库帮助
show_database_help() {
    help_title "数据库与缓存管理"
    echo -e "用法: ${GREEN}saltgoat database <mysql|valkey> <action> [options]${NC}"
    echo ""

    help_subtitle "MySQL / Percona"
    help_command "create <dbname>"               "创建数据库（使用 Pillar 凭据）"
    help_command "list"                          "列出数据库与字符集摘要"
    help_command "backup <dbname> [name]"        "生成备份（默认保存到 /var/backups/mysql）"
    help_command "restore <dbname> <file>"       "从备份恢复数据库"
    help_command "delete <dbname>"               "删除数据库并清理权限"
    help_command "status"                        "查看运行状态、版本与连接数"
    echo ""

    help_subtitle "Valkey (Redis 兼容)"
    help_command "create <name>"                 "初始化命名空间（保留密码）"
    help_command "list"                          "列出 Valkey 数据库映射"
    help_command "flush <name>"                  "清理命名空间数据"
    help_command "stats"                         "输出内存与命中率统计"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat database mysql backup magento" "备份 Magento 数据库"
    help_command "saltgoat database mysql status"         "快速查看 MySQL 运行情况"
    help_command "saltgoat database valkey stats"         "确认缓存是否命中"
}

# 监控帮助
show_monitor_help() {
    help_title "运行状态与监控"
    echo -e "用法: ${GREEN}saltgoat monitor <type> [options]${NC}"
    echo ""

    help_subtitle "即时检查"
    help_command "system"                        "输出 CPU / 内存 / 磁盘占用及负载"
    help_command "services"                      "核心服务状态与最近失败重启"
    help_command "resources"                     "扩展资源追踪（内存热点/IO 等）"
    help_command "network"                       "网络连通性、丢包率与开放端口"
    help_command "logs"                          "聚合最近错误日志摘要"
    help_command "security"                      "安全基线检测（SSH、sudo、弱口令）"
    echo ""

    help_subtitle "长期分析"
    help_command "performance"                   "收集性能指标用于扩容建议"
    help_command "report [daily|weekly]"         "生成 Markdown 报告保存到 reports/"
    help_command "realtime [seconds]"            "以秒为单位执行 watch 模式"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat monitor system"       "查看常规健康检查"
    help_command "saltgoat monitor report daily" "生成日报并保存历史"
}

# 维护帮助
show_maintenance_help() {
    help_title "系统维护与调整"
    echo -e "用法: ${GREEN}saltgoat maintenance <category> <action>${NC}"
    echo ""

    help_subtitle "系统更新"
    help_command "update check"                 "检查可用更新与安全修复"
    help_command "update upgrade"               "执行正常升级（apt upgrade）"
    help_command "update dist-upgrade"          "进行发行版级升级"
    help_command "update autoremove|clean"      "清理旧包与 apt 缓存"
    echo ""

    help_subtitle "服务管理"
    help_command "service status <name>"        "查看 systemd 服务状态"
    help_command "service restart <name>"       "重启指定服务"
    help_command "service start|stop <name>"    "启动或停止服务"
    help_command "service reload <name>"        "重新加载配置"
    echo ""

    help_subtitle "清理任务"
    help_command "cleanup logs|temp|cache"      "按类型清理日志、临时文件、缓存"
    help_command "cleanup all"                  "执行全量清理（适合发布前）"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat maintenance update check"  "在维护窗口前确认更新"
    help_command "saltgoat maintenance cleanup logs"  "释放日志占用空间"
}

# 优化帮助
show_optimize_help() {
    help_title "系统与 Magento 优化"
    echo -e "用法: ${GREEN}saltgoat optimize [type] [options]${NC}"
    echo ""
    help_subtitle "优化类型"
    help_command "(no args)"                 "输出当前主机的优化建议"
    help_command "magento"                   "应用 Magento 2 优化策略（详见参数）"
    help_command "auto-tune"                 "根据主机资源自动调优核心服务"
    help_command "benchmark"                 "运行基准测试，评估性能"
    echo ""
    help_subtitle "Magento 参数"
    help_command "--profile <auto|low|...>"  "指定档位，默认 auto 根据内存自动选择"
    help_command "--site <name>"             "记录站点名称，用于报告与日志"
    help_command "--dry-run | --plan"        "仅模拟执行，输出预期改动"
    help_command "--show-results"            "打印最近一次优化报告"
    echo ""
    help_subtitle "示例"
    help_command "saltgoat optimize"                         "分析当前主机优化建议"
    help_command "saltgoat optimize magento"                 "使用自动档位优化 Magento"
    help_command "saltgoat optimize magento --profile high --site shop01" "指定档位并标记站点"
    help_command "saltgoat optimize magento --plan --show-results" "Dry-run 并查看报告详情"
    help_command "saltgoat auto-tune"                        "快速应用自动调优策略"
    help_command "saltgoat benchmark"                        "运行性能基准测试"
}

# 速度测试帮助
show_speedtest_help() {
    help_title "网络速度测试"
    echo -e "用法: ${GREEN}saltgoat speedtest [action]${NC}"
    echo ""

    help_subtitle "测试模式"
    help_command "(无参数)"                     "执行完整测速（下载/上传/延迟）"
    help_command "quick"                         "快速模式，仅采样下载与延迟"
    help_command "server <id>"                   "指定测速服务器 ID"
    help_command "list"                          "列出可用服务器及地理位置"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat speedtest"            "运行完整测速以记录基线"
    help_command "saltgoat speedtest quick"      "部署后快速验证网络"
    help_command "saltgoat speedtest server 1234" "固定到指定运营商节点"
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
    local server_ip=$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
    help_title "监控集成"
    echo -e "用法: ${GREEN}saltgoat monitoring <prometheus|grafana|exporter>${NC}"
    echo ""

    help_subtitle "核心组件"
    help_command "prometheus"                   "安装 Prometheus Server（监听端口 9090）"
    help_command "grafana"                      "安装 Grafana 看板（默认账号 admin/admin）"
    help_command "exporter"                     "部署 Node Exporter 与服务指标采集器"
    echo ""

    help_subtitle "访问地址"
    help_command "Prometheus"                   "http://${server_ip:-<server-ip>}:9090"
    help_command "Grafana"                      "http://${server_ip:-<server-ip>}:3000"
    help_note "首次登录 Grafana 后请立即修改默认密码。"
    echo ""

    help_subtitle "快速上手"
    help_command "saltgoat monitoring prometheus" "安装 Prometheus 并注册 systemd 服务"
    help_command "saltgoat monitoring grafana"    "部署 Grafana 并加载默认仪表板"
    help_command "saltgoat monitoring exporter"   "安装 Node Exporter 与服务采集模块"
    help_note "Grafana 中添加 Prometheus 数据源后导入 1860/12559/7362/11835 等推荐仪表板。"
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
    help_command "network"                      "测试 DNS/路由/端口连通性"
    help_command "all"                          "执行完整诊断并生成报告"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat diagnose nginx"      "定位站点 502/504 等问题"
    help_command "saltgoat diagnose all"        "一键导出全部诊断细节"
    echo ""

    help_note "输出使用 ✅ 正常、⚠️ 警告、❌ 错误，请根据提示执行相应修复。"
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
    help_command "php"                          "检查 PHP-FPM 队列与慢日志"
    help_command "memory|disk|network"          "针对单项资源进行深度分析"
    help_command "all"                          "生成全量性能报告（建议保留）"
    echo ""

    help_subtitle "评分标准"
    help_command "90-100"                       "优秀（绿色）"
    help_command "80-89"                        "良好（蓝色）"
    help_command "70-79"                        "一般（黄色）"
    help_command "<70"                          "需要优化（红色）"
    help_note "报告会保存到 reports/，可与历史数据对比以评估效果。"
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

    help_subtitle "工具安装"
    help_command "install n98-magerun2"         "安装 N98 Magerun2 CLI"
    help_command "install phpunit"              "安装 PHPUnit 以运行单元测试"
    help_command "install xdebug"               "安装 Xdebug 调试扩展"
    echo ""

    help_subtitle "权限助手"
    help_command "permissions fix [path]"       "修复 Magento 目录权限 (默认当前目录)"
    help_command "permissions check [path]"     "检测文件/目录权限异常"
    help_command "permissions reset [path]"     "重置为官方推荐权限"
    help_note "遵循最佳实践：使用 \`sudo -u www-data php bin/magento\` 执行命令，详见 docs/MAGENTO_PERMISSIONS.md。"
    echo ""

    help_subtitle "站点配置转换"
    help_command "convert magento2"             "将现有 Nginx 虚拟主机转换为 Magento 模板"
    help_command "convert check"                "验证站点是否符合 Magento2 规范"
    echo ""

    help_subtitle "Valkey 管理"
    help_command "valkey-renew <site>"          "为站点重新分配缓存 DB 并更新 env.php"
    help_command "valkey-check <site>"          "验证 Valkey 连接、认证与权限"
    help_note "Valkey 默认凭据来自 Pillar，可通过 \`saltgoat passwords\` 查看。"
    echo ""

    help_subtitle "RabbitMQ 队列"
    help_command "rabbitmq all <site> [threads]"   "部署全部消费者（21 个），支持并发线程"
    help_command "rabbitmq smart <site> [threads]" "仅启用核心消费者以降低资源占用"
    help_command "rabbitmq check <site>"           "检查队列堆积与消费者状态"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat magetools install n98-magerun2" "安装 Magento CLI 工具"
    help_command "saltgoat magetools permissions fix /var/www/shop" "修复线上站点权限"
    help_command "saltgoat magetools valkey-renew shop"             "为站点重新绑定缓存"
    help_command "saltgoat magetools rabbitmq smart shop 4"         "按需启用消费者并限制线程"
}

# 版本锁定帮助
show_version_lock_help() {
    help_title "版本锁定"
    echo -e "用法: ${GREEN}saltgoat version-lock <lock|unlock|show|status>${NC}"
    echo ""

    help_subtitle "操作"
    help_command "lock"                        "锁定核心软件包版本防止升级"
    help_command "unlock"                      "解除锁定以允许升级"
    help_command "show"                        "列出被锁定的软件包清单"
    help_command "status"                      "显示 apt pin 优先级与当前状态"
    echo ""

    help_subtitle "锁定范围"
    help_command "Web"                         "Nginx 1.29.1 + ModSecurity"
    help_command "Database"                    "Percona MySQL 8.4"
    help_command "PHP"                         "php8.3-fpm 与扩展"
    help_command "Cache"                       "Valkey 8"
    help_command "Search"                      "OpenSearch 2.19"
    help_command "Queue"                       "RabbitMQ 4.1"
    help_command "其他"                        "Varnish 7.6、Composer 2.8 等"
    help_note "系统安全更新与通用工具包仍允许升级。"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat version-lock lock"    "锁定所有核心组件"
    help_command "saltgoat version-lock status"  "检查当前锁定状态"
    help_command "saltgoat version-lock unlock"  "升级前解除锁定"
    help_note "升级核心组件前务必先 unlock，再执行更新，完成后重新 lock。"
}

# Cockpit 帮助
show_cockpit_help() {
    help_title "Cockpit 系统面板"
    echo -e "用法: ${GREEN}saltgoat cockpit <command>${NC}"
    echo ""

    help_subtitle "操作"
    help_command "install"                     "安装 Cockpit 及常用插件"
    help_command "uninstall"                   "移除 Cockpit 并清理服务"
    help_command "status"                      "显示服务状态与登录地址"
    help_command "config show|firewall|ssl"    "查看配置 / 放通端口 / 配置自签证书"
    help_command "logs [lines]"                "查看最近日志（默认 50 行）"
    help_command "restart"                     "重启 Cockpit 服务"
    echo ""

    help_subtitle "访问地址"
    help_command "Cockpit"                     "https://your-server-ip:9091"
    help_note "首次登录请使用系统账户，并启用双因素认证。"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat cockpit install"    "安装并自动放通 9091 端口"
    help_command "saltgoat cockpit config firewall" "快速放通额外来源地址"
    help_command "saltgoat cockpit logs 100"   "查看最近 100 行访问日志"
}

# Adminer 帮助
show_adminer_help() {
    help_title "Adminer 数据库面板"
    echo -e "用法: ${GREEN}saltgoat adminer <command>${NC}"
    echo ""

    help_subtitle "操作"
    help_command "install"                     "安装 Adminer 并配置 systemd 服务"
    help_command "uninstall"                   "卸载 Adminer 及 nginx 反向代理"
    help_command "status"                      "查看运行状态与访问信息"
    help_command "config show|update|theme"    "查看配置 / 更新端口 / 切换主题"
    help_command "security"                    "启用 HTTP 基本认证与 IP 限制"
    help_command "backup"                      "备份配置与凭据到 /var/backups/adminer"
    echo ""

    help_subtitle "访问地址"
    help_command "Adminer"                     "http://your-server-ip:8081"
    help_command "安全入口"                     "http://your-server-ip:8081/login.php"
    help_note "安装后建议立刻执行 \`saltgoat adminer security\` 强化访问控制。"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat adminer install"    "快速部署数据库面板"
    help_command "saltgoat adminer config theme nette" "切换为 Nette 主题"
    help_command "saltgoat adminer security"   "开启认证并限制来源"
}

# Uptime Kuma 帮助
show_uptime_kuma_help() {
    help_title "Uptime Kuma 状态面板"
    echo -e "用法: ${GREEN}saltgoat uptime-kuma <command>${NC}"
    echo ""

    help_subtitle "操作"
    help_command "install"                     "安装并配置 Uptime Kuma 服务"
    help_command "uninstall"                   "卸载服务并移除数据目录"
    help_command "status"                      "查看服务状态与访问地址"
    help_command "config show|port|update"     "查看配置 / 修改端口 / 升级版本"
    help_command "config backup|restore"       "备份或恢复监控配置"
    help_command "logs [lines]"                "查看实时日志（默认 50 行）"
    help_command "restart"                     "重启服务"
    help_command "monitor"                     "导入 SaltGoat 核心组件监控项"
    echo ""

    help_subtitle "访问地址"
    help_command "Uptime Kuma"                 "http://your-server-ip:3001"
    help_note "默认账户 admin/admin，首次登录后请立即修改密码。"
    echo ""

    help_subtitle "监控能力"
    help_command "HTTP/HTTPS"                  "站点可用性、响应时间与 SSL 到期"
    help_command "Ping/TCP/DNS"                "网络连通性、端口可用性"
    help_command "自定义"                       "Webhook、脚本、数据库连接等"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat uptime-kuma install" "快速部署监控面板"
    help_command "saltgoat uptime-kuma config port 3002" "修改监听端口"
    help_command "saltgoat uptime-kuma monitor" "导入 SaltGoat 默认监控清单"
}

# SSL 证书管理帮助
show_ssl_help() {
    help_title "SSL 证书管理"
    echo -e "用法: ${GREEN}saltgoat ssl <command>${NC}"
    echo ""

    help_subtitle "证书操作"
    help_command "generate-self-signed <domain> [days]" "创建自签名证书用于测试"
    help_command "generate-csr <domain> <C> <ST> <L> <O>" "生成提交 CA 的 CSR 文件"
    help_command "view <cert>"                          "查看证书详情与有效期"
    help_command "verify <cert> <domain>"               "验证证书链与域名匹配"
    help_command "list"                                 "列出已部署证书"
    help_command "renew <domain> [method]"              "续期证书（支持自签/Let’s Encrypt）"
    help_command "backup [name]"                        "备份证书到 /var/backups/ssl"
    help_command "cleanup-expired [days]"               "清理超过指定天数的过期证书"
    help_command "status"                               "输出证书摘要与即将过期提醒"
    echo ""

    help_subtitle "证书目录"
    help_command "/etc/ssl/certs"                       "证书文件 (.crt)"
    help_command "/etc/ssl/private"                     "私钥文件 (.key) — 权限需 600"
    help_command "/etc/ssl/csr"                         "证书请求 (.csr)"
    help_command "/var/backups/ssl"                     "证书备份存储目录"
    echo ""

    help_subtitle "Let's Encrypt 集成"
    help_command "saltgoat nginx add-ssl <site> <domain> [email]" "为站点申请/续期证书（默认使用 Pillar 中 ssl_email）"
    help_command "saltgoat ssl renew <domain> letsencrypt"        "手动触发 certbot 续期"
    echo ""

    help_subtitle "示例"
    help_command "saltgoat ssl generate-self-signed shop.com 365" "生成一年期测试证书"
    help_command "saltgoat ssl view /etc/ssl/certs/shop.com.crt"  "查看证书信息"
    help_command "saltgoat ssl cleanup-expired 30"                "清理 30 天前的过期证书"
    help_note "Let’s Encrypt 需要域名指向服务器，重启 nginx 后证书即生效。"
}
