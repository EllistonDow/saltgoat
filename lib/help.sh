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

# 主帮助菜单
show_main_help() {
    echo "版本: $SCRIPT_VERSION"
    echo "用法: saltgoat <command> [options]"
    echo ""
    echo "主要功能:"
    echo "  install                    - 安装 LEMP 组件"
    echo "  nginx                      - Nginx 管理"
    echo "  database                   - 数据库管理"
    echo "  monitor                    - 系统监控"
    echo "  maintenance                - 系统维护"
    echo "  optimize                   - 系统优化"
    echo "  speedtest                  - 网络速度测试"
    echo "  auto-tune                  - 自动调优"
    echo "  benchmark                  - 基准测试"
    echo ""
    echo "诊断分析:"
    echo "  diagnose <type>             - 故障诊断 (nginx/mysql/php/system/network/all)"
    echo "  profile analyze <type>     - 性能分析 (system/nginx/mysql/php/memory/disk/network/all)"
    echo "  version-lock <action>       - 版本锁定 (lock/unlock/show/status)"
    echo ""
    echo "代码质量:"
    echo "  lint [file]                - 代码检查 (shellcheck)"
    echo "  format [file]              - 代码格式化 (shfmt)"
    echo "  security-scan              - 安全扫描"
    echo ""
    echo "状态管理:"
    echo "  state list                 - 列出所有状态"
    echo "  state apply <name>         - 应用特定状态"
    echo "  state rollback <name>      - 回滚状态"
    echo ""
    echo "监控集成:"
    echo "  monitoring prometheus       - Prometheus监控集成"
    echo "  monitoring grafana         - Grafana仪表板集成"
    echo "  monitoring smart           - 智能监控"
    echo "  monitoring dynamic         - 动态监控"
    echo "  monitoring cost           - 成本优化监控"
    echo ""
    echo "系统管理:"
    echo "  env <action>               - 环境配置管理"
    echo "  system <action>            - 系统安装/卸载"
    echo "  saltgui <action>           - SaltGUI管理"
    echo "  automation <action>         - 任务自动化"
    echo "  reports <type>             - 报告生成"
    echo ""
    echo "Magento工具:"
    echo "  magetools <command>        - Magento工具集"
    echo ""
    echo "管理面板:"
    echo "  cockpit <action>           - Cockpit系统管理面板"
    echo "  adminer <action>           - Adminer数据库管理面板"
    echo "  uptime-kuma <action>        - Uptime Kuma监控面板"
    echo ""
    echo "SSL证书管理:"
    echo "  ssl <action>               - SSL证书管理"
    echo ""
    echo "系统信息:"
    echo "  status                     - 查看系统状态"
    echo "  versions                   - 查看版本信息"
    echo "  passwords                  - 查看配置密码"
    echo ""
    echo "获取详细帮助:"
    echo "  saltgoat help <command>    - 查看特定命令帮助"
    echo "  saltgoat help all          - 查看完整帮助"
    echo ""
    echo "示例:"
    echo "  saltgoat install all       - 安装所有组件"
    echo "  saltgoat nginx create      - 创建 Nginx 站点"
    echo "  saltgoat database mysql    - MySQL 数据库管理"
    echo "  saltgoat monitor system    - 系统监控"
    echo "  saltgoat optimize          - 智能优化建议"
    echo "  saltgoat speedtest         - 网络速度测试"
}

# 安装帮助
show_install_help() {
    echo "=========================================="
    echo "    SaltGoat 安装功能帮助"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat install <component> [options]"
    echo ""
    echo "组件:"
    echo "  all                        - 安装所有组件"
    echo "  core                       - 安装核心组件 (Nginx, MySQL, PHP)"
    echo "  optional                   - 安装可选组件 (Valkey, OpenSearch, RabbitMQ)"
    echo ""
    echo "选项:"
    echo "  --skip-deps                - 跳过依赖检查"
    echo "  --force                    - 强制重新安装"
    echo "  --dry-run                  - 模拟运行"
    echo ""
    echo "示例:"
    echo "  saltgoat install all"
    echo "  saltgoat install core --skip-deps"
    echo "  saltgoat install optional --dry-run"
}

# Nginx帮助
show_nginx_help() {
    echo "=========================================="
    echo "    SaltGoat Nginx 管理帮助"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat nginx <action> [options]"
    echo ""
    echo "操作:"
    echo "  create <site> <domain> [path] - 创建新站点"
    echo "  delete <site>            - 删除站点"
    echo "  list                      - 列出所有站点"
    echo "  enable <site>            - 启用站点"
    echo "  disable <site>           - 禁用站点"
    echo "  reload                    - 重新加载配置"
    echo "  test                      - 测试配置"
    echo ""
    echo "示例:"
    echo "  saltgoat nginx create site1 example1.com"
    echo "  saltgoat nginx delete site1"
    echo "  saltgoat nginx list"
}

# 数据库帮助
show_database_help() {
    echo "=========================================="
    echo "    SaltGoat 数据库管理帮助"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat database <type> <action> [options]"
    echo ""
    echo "数据库类型:"
    echo "  mysql                      - MySQL/Percona 数据库"
    echo "  valkey                     - Valkey (Redis兼容)"
    echo ""
    echo "MySQL 操作:"
    echo "  create <dbname>            - 创建数据库"
    echo "  list                       - 列出数据库"
    echo "  backup <dbname> [name]     - 备份数据库"
    echo "  delete <dbname>            - 删除数据库"
    echo "  status                     - 查看状态"
    echo "  restore <dbname> <file>    - 恢复数据库"
    echo ""
    echo "示例:"
    echo "  saltgoat database mysql create mydb"
    echo "  saltgoat database mysql backup mydb"
    echo "  saltgoat database mysql status"
}

# 监控帮助
show_monitor_help() {
    echo "=========================================="
    echo "    SaltGoat 监控功能帮助"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat monitor <type> [options]"
    echo ""
    echo "监控类型:"
    echo "  system                     - 系统状态监控"
    echo "  services                   - 服务状态监控"
    echo "  resources                  - 资源使用监控"
    echo "  network                    - 网络状态监控"
    echo "  logs                       - 日志状态监控"
    echo "  security                   - 安全状态监控"
    echo "  performance                - 性能监控"
    echo "  report [name]              - 生成监控报告"
    echo "  realtime [seconds]        - 实时监控"
    echo ""
    echo "示例:"
    echo "  saltgoat monitor system"
    echo "  saltgoat monitor services"
    echo "  saltgoat monitor report daily"
}

# 维护帮助
show_maintenance_help() {
    echo "=========================================="
    echo "    SaltGoat 系统维护帮助"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat maintenance <action> [options]"
    echo ""
    echo "操作:"
    echo "  update <action>            - 系统更新管理"
    echo "    check                    - 检查更新"
    echo "    upgrade                  - 执行更新"
    echo "    dist-upgrade             - 系统升级"
    echo "    autoremove               - 清理无用包"
    echo "    clean                    - 清理缓存"
    echo ""
    echo "  service <action> <name>    - 服务管理"
    echo "    restart                  - 重启服务"
    echo "    start                    - 启动服务"
    echo "    stop                     - 停止服务"
    echo "    reload                   - 重新加载"
    echo "    status                   - 查看状态"
    echo ""
    echo "  cleanup <type>             - 系统清理"
    echo "    logs                     - 清理日志"
    echo "    temp                     - 清理临时文件"
    echo "    cache                    - 清理缓存"
    echo "    all                      - 完整清理"
    echo ""
    echo "示例:"
    echo "  saltgoat maintenance update check"
    echo "  saltgoat maintenance service restart nginx"
    echo "  saltgoat maintenance cleanup logs"
}

# 优化帮助
show_optimize_help() {
    echo "=========================================="
    echo "    SaltGoat 系统优化帮助"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat optimize [type]"
    echo ""
    echo "优化类型:"
    echo "  (无参数)                  - 智能优化建议"
    echo "  magento                   - Magento2 专用优化"
    echo ""
    echo "相关命令:"
    echo "  auto-tune                 - 自动调优配置"
    echo "  benchmark                 - 性能基准测试"
    echo ""
    echo "示例:"
    echo "  saltgoat optimize         - 智能优化建议"
    echo "  saltgoat optimize magento - Magento2 优化"
    echo "  saltgoat auto-tune        - 自动调优"
    echo "  saltgoat benchmark        - 性能测试"
}

# 速度测试帮助
show_speedtest_help() {
    echo "=========================================="
    echo "    SaltGoat 网络速度测试帮助"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat speedtest [action] [options]"
    echo ""
    echo "操作:"
    echo "  (无参数)                  - 完整速度测试"
    echo "  quick                     - 快速速度测试"
    echo "  server <id>               - 指定服务器测试"
    echo "  list                      - 列出可用服务器"
    echo ""
    echo "示例:"
    echo "  saltgoat speedtest        - 完整测试"
    echo "  saltgoat speedtest quick   - 快速测试"
    echo "  saltgoat speedtest list    - 服务器列表"
    echo "  saltgoat speedtest server 1234 - 指定服务器"
}

# 完整帮助
show_complete_help() {
    echo "=========================================="
    echo "    SaltGoat 完整功能帮助"
    echo "=========================================="
    echo ""
    echo "版本: $SCRIPT_VERSION"
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
    show_monitoring_help
    echo ""
    show_ssl_help
    echo ""
    echo "=========================================="
    echo "    更多信息请访问项目文档"
    echo "=========================================="
}

# 显示监控集成帮助
show_monitoring_help() {
    local server_ip=$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
    echo "=========================================="
    echo "    监控集成帮助"
    echo "=========================================="
    echo ""
    echo "监控集成功能:"
    echo "  monitoring prometheus       - 安装配置Prometheus"
    echo "  monitoring grafana         - 安装配置Grafana"
    echo ""
    echo "访问地址:"
    echo "  Prometheus: http://${server_ip}:9090"
    echo "  Grafana: http://${server_ip}:3000 (admin/admin)"
    echo ""
    echo "使用步骤:"
    echo "  1. 运行 saltgoat monitoring prometheus"
    echo "  2. 运行 saltgoat monitoring grafana"
    echo "  3. 访问 Grafana 并登录"
    echo "  4. 添加 Prometheus 数据源"
    echo "  5. 导入推荐仪表板"
    echo ""
    echo "防火墙配置:"
    echo "  - 自动检测并配置UFW、Firewalld、iptables"
    echo "  - Prometheus: 9090端口"
    echo "  - Grafana: 3000端口"
    echo "  - Node Exporter: 9100端口"
    echo ""
    echo "推荐仪表板:"
    echo "  - Node Exporter: 1860"
    echo "  - Nginx: 12559"
    echo "  - MySQL: 7362"
    echo "  - Valkey: 11835"
    echo ""
}

# 故障诊断帮助
show_diagnose_help() {
    echo "=========================================="
    echo "    SaltGoat 故障诊断帮助"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat diagnose <type>"
    echo ""
    echo "诊断类型:"
    echo "  nginx                      - Nginx服务诊断"
    echo "  mysql                      - MySQL服务诊断"
    echo "  php                        - PHP服务诊断"
    echo "  system                     - 系统状态诊断"
    echo "  network                    - 网络连接诊断"
    echo "  all                        - 完整系统诊断"
    echo ""
    echo "诊断内容:"
    echo "  - 服务运行状态检查"
    echo "  - 配置文件语法验证"
    echo "  - 端口占用情况分析"
    echo "  - 权限和日志检查"
    echo "  - 性能指标评估"
    echo ""
    echo "示例:"
    echo "  saltgoat diagnose nginx"
    echo "  saltgoat diagnose mysql"
    echo "  saltgoat diagnose all"
    echo ""
    echo "输出说明:"
    echo "  ✅ 绿色 - 正常状态"
    echo "  ⚠️  黄色 - 警告信息"
    echo "  ❌ 红色 - 错误问题"
}

# 性能分析帮助
show_profile_help() {
    echo "=========================================="
    echo "    SaltGoat 性能分析帮助"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat profile analyze <type>"
    echo ""
    echo "分析类型:"
    echo "  system                     - 系统性能分析"
    echo "  nginx                      - Nginx性能分析"
    echo "  mysql                      - MySQL性能分析"
    echo "  php                        - PHP性能分析"
    echo "  memory                     - 内存性能分析"
    echo "  disk                       - 磁盘性能分析"
    echo "  network                    - 网络性能分析"
    echo "  all                        - 完整性能分析"
    echo ""
    echo "分析指标:"
    echo "  - CPU使用率和负载"
    echo "  - 内存使用和泄漏检查"
    echo "  - 磁盘I/O和空间使用"
    echo "  - 网络连接和延迟"
    echo "  - 服务配置和性能"
    echo "  - 进程资源占用"
    echo ""
    echo "评分标准:"
    echo "  90-100分: 优秀 (绿色)"
    echo "  80-89分:  良好 (蓝色)"
    echo "  70-79分:  一般 (黄色)"
    echo "  <70分:    需要优化 (红色)"
    echo ""
    echo "示例:"
    echo "  saltgoat profile analyze system"
    echo "  saltgoat profile analyze nginx"
    echo "  saltgoat profile analyze all"
}

# Magento工具帮助
show_magetools_help() {
    echo "=========================================="
    echo "    Magento 工具集帮助"
    echo "=========================================="
    echo ""
    echo "Magento工具集提供以下功能:"
    echo ""
    echo "📦 工具安装:"
    echo "  install n98-magerun2 - 安装N98 Magerun2 (Magento 2 CLI工具)"
    echo "  install phpunit      - 安装PHPUnit单元测试框架"
    echo "  install xdebug      - 安装Xdebug调试工具"
    echo ""
    echo "🔧 权限管理:"
    echo "  permissions fix      - 修复Magento权限"
    echo "  permissions check    - 检查权限状态"
    echo "  permissions reset    - 重置权限"
    echo ""
    echo "🔄 站点转换:"
    echo "  convert magento2     - 转换Nginx配置为Magento2格式"
    echo "  convert check        - 检查Magento2兼容性"
    echo ""
    echo "🔄 Valkey缓存管理:"
    echo "  valkey-renew <site>  - Valkey缓存自动续期 (随机分配数据库编号)"
    echo ""
    echo "🔄 RabbitMQ队列管理:"
    echo "  rabbitmq all <site> [threads]   - 配置所有消费者（21个）"
    echo "  rabbitmq smart <site> [threads] - 智能配置（仅核心消费者）"
    echo "  rabbitmq check <site>           - 检查消费者状态"
    echo ""
    echo "示例:"
    echo "  saltgoat magetools install n98-magerun2"
    echo "  saltgoat magetools permissions fix"
    echo "  saltgoat magetools convert magento2"
    echo "  saltgoat magetools valkey-renew tank"
    echo "  saltgoat magetools rabbitmq check tank"
    echo ""
}

# 版本锁定帮助
show_version_lock_help() {
    echo "=========================================="
    echo "    SaltGoat 版本锁定帮助"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat version-lock <action>"
    echo ""
    echo "操作:"
    echo "  lock                        - 锁定核心软件版本"
    echo "  unlock                      - 解锁软件版本"
    echo "  show                        - 显示锁定的软件包"
    echo "  status                      - 检查软件版本状态"
    echo ""
    echo "锁定策略:"
    echo "  ✅ 锁定软件:"
    echo "    - Nginx 1.29.1+ModSecurity"
    echo "    - Percona MySQL 8.4"
    echo "    - PHP 8.3"
    echo "    - RabbitMQ 4.1"
    echo "    - OpenSearch 2.19"
    echo "    - Valkey 8"
    echo "    - Varnish 7.6"
    echo "    - Composer 2.8"
    echo ""
    echo "  🔄 允许更新:"
    echo "    - 系统内核安全补丁"
    echo "    - 其他工具软件"
    echo ""
    echo "示例:"
    echo "  saltgoat version-lock lock    # 锁定版本"
    echo "  saltgoat version-lock status  # 检查状态"
    echo "  saltgoat version-lock unlock  # 解锁版本"
    echo ""
    echo "注意事项:"
    echo "  - 锁定后系统更新不会影响核心软件版本"
    echo "  - 如需更新核心软件，请先解锁"
    echo "  - 建议定期检查版本状态"
}

# Cockpit 帮助
show_cockpit_help() {
    echo "=========================================="
    echo "    Cockpit 系统管理面板帮助"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat cockpit <action> [options]"
    echo ""
    echo "操作:"
    echo "  install                     - 安装 Cockpit 及其插件"
    echo "  uninstall                   - 卸载 Cockpit"
    echo "  status                      - 查看服务状态和访问信息"
    echo "  config <action>             - 配置管理 (show|firewall|ssl)"
    echo "  logs [lines]                - 查看日志 (可选行数，默认50)"
    echo "  restart                     - 重启服务"
    echo ""
    echo "访问地址:"
    echo "  https://your-server-ip:9091"
    echo ""
    echo "功能特性:"
    echo "  - 系统监控 (CPU、内存、磁盘)"
    echo "  - 服务管理 (启动、停止、重启)"
    echo "  - 网络管理 (接口配置)"
    echo "  - 存储管理 (分区、挂载)"
    echo "  - 用户管理 (系统用户和组)"
    echo "  - 容器支持 (Docker管理)"
    echo "  - 虚拟机支持 (VM管理)"
    echo ""
    echo "示例:"
    echo "  saltgoat cockpit install"
    echo "  saltgoat cockpit status"
    echo "  saltgoat cockpit config firewall"
    echo "  saltgoat cockpit logs 100"
}

# Adminer 帮助
show_adminer_help() {
    echo "=========================================="
    echo "    Adminer 数据库管理面板帮助"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat adminer <action> [options]"
    echo ""
    echo "操作:"
    echo "  install                     - 安装 Adminer"
    echo "  uninstall                   - 卸载 Adminer"
    echo "  status                      - 查看状态和访问信息"
    echo "  config <action>             - 配置管理 (show|update|theme)"
    echo "  security                    - 配置安全设置"
    echo "  backup                      - 备份配置"
    echo ""
    echo "访问地址:"
    echo "  http://your-server-ip:8081"
    echo "  http://your-server-ip:8081/login.php (安全访问)"
    echo ""
    echo "功能特性:"
    echo "  - 多数据库支持 (MySQL、PostgreSQL、SQLite等)"
    echo "  - 轻量级单文件应用"
    echo "  - 快速响应和低资源占用"
    echo "  - 多种主题支持"
    echo "  - 移动设备友好"
    echo "  - 内置安全功能"
    echo ""
    echo "主题支持:"
    echo "  default, nette, hydra, konya"
    echo ""
    echo "示例:"
    echo "  saltgoat adminer install"
    echo "  saltgoat adminer status"
    echo "  saltgoat adminer config theme nette"
    echo "  saltgoat adminer security"
}

# Uptime Kuma 帮助
show_uptime_kuma_help() {
    echo "=========================================="
    echo "    Uptime Kuma 监控面板帮助"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat uptime-kuma <action> [options]"
    echo ""
    echo "操作:"
    echo "  install                     - 安装 Uptime Kuma"
    echo "  uninstall                   - 卸载 Uptime Kuma"
    echo "  status                      - 查看服务状态"
    echo "  config <action>             - 配置管理 (show|port|update|backup|restore)"
    echo "  logs [lines]                - 查看日志 (可选行数，默认50)"
    echo "  restart                     - 重启服务"
    echo "  monitor                     - 配置 SaltGoat 服务监控"
    echo ""
    echo "访问地址:"
    echo "  http://your-server-ip:3001"
    echo "  默认账户: admin / admin"
    echo ""
    echo "功能特性:"
    echo "  - 多协议监控 (HTTP/HTTPS、TCP、Ping、DNS)"
    echo "  - 实时状态页面"
    echo "  - 多种通知方式 (邮件、Slack、Discord、Telegram)"
    echo "  - 响应时间监控"
    echo "  - SSL证书监控"
    echo "  - 移动应用支持"
    echo "  - API接口支持"
    echo ""
    echo "监控类型:"
    echo "  - HTTP/HTTPS 网站监控"
    echo "  - Ping 网络连通性"
    echo "  - TCP 端口监控"
    echo "  - DNS 解析监控"
    echo "  - 数据库连接监控"
    echo ""
    echo "示例:"
    echo "  saltgoat uptime-kuma install"
    echo "  saltgoat uptime-kuma status"
    echo "  saltgoat uptime-kuma config port 3002"
    echo "  saltgoat uptime-kuma monitor"
}

# SSL 证书管理帮助
show_ssl_help() {
    echo "=========================================="
    echo "    SSL 证书管理帮助"
    echo "=========================================="
    echo ""
    echo "用法: saltgoat ssl <action> [options]"
    echo ""
    echo "操作:"
    echo "  generate-self-signed <domain> [days] - 生成自签名证书"
    echo "  generate-csr <domain> <country> <state> <city> <org> - 生成证书签名请求"
    echo "  view <certificate_file>              - 查看证书信息"
    echo "  verify <certificate_file> <domain>   - 验证证书"
    echo "  list                                 - 列出所有证书"
    echo "  renew <domain> [method]              - 续期证书"
    echo "  backup [backup_name]                 - 备份证书"
    echo "  cleanup-expired [days]               - 清理过期证书"
    echo "  status                               - 查看SSL状态"
    echo ""
    echo "证书类型:"
    echo "  🔒 自签名证书 - 用于测试和内部使用"
    echo "  📋 CSR证书请求 - 用于向CA申请正式证书"
    echo "  ✅ Let's Encrypt - 免费SSL证书 (通过certbot)"
    echo ""
    echo "证书位置:"
    echo "  /etc/ssl/certs/     - 证书文件目录"
    echo "  /etc/ssl/private/   - 私钥文件目录"
    echo "  /etc/ssl/csr/       - CSR文件目录"
    echo "  /var/backups/ssl/   - 备份目录"
    echo ""
    echo "Let's Encrypt 集成:"
    echo "  nginx add-ssl <site> <domain> [email] - 为Nginx站点申请SSL证书"
    echo "  (email参数可选，默认使用.env中的SSL_EMAIL配置)"
    echo ""
    echo "示例:"
    echo "  saltgoat ssl generate-self-signed example.com 365"
    echo "  saltgoat ssl generate-csr example.com US California SanFrancisco MyCompany"
    echo "  saltgoat ssl view /etc/ssl/certs/example.com.crt"
    echo "  saltgoat ssl verify /etc/ssl/certs/example.com.crt example.com"
    echo "  saltgoat ssl list"
    echo "  saltgoat ssl renew example.com"
    echo "  saltgoat ssl backup my-backup"
    echo "  saltgoat ssl status"
    echo ""
    echo "Nginx SSL 集成:"
    echo "  saltgoat nginx add-ssl mysite example.com                    # 使用.env中的SSL_EMAIL"
    echo "  saltgoat nginx add-ssl mysite example.com admin@example.com # 使用指定邮箱"
    echo ""
    echo "注意事项:"
    echo "  - 自签名证书浏览器会显示安全警告"
    echo "  - Let's Encrypt证书需要域名解析到服务器"
    echo "  - 证书续期建议设置自动任务"
    echo "  - 私钥文件权限必须为600"
}
