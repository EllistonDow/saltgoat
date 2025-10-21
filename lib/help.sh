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
    echo "  create <domain>            - 创建新站点"
    echo "  delete <domain>            - 删除站点"
    echo "  list                       - 列出所有站点"
    echo "  enable <domain>            - 启用站点"
    echo "  disable <domain>           - 禁用站点"
    echo "  reload                     - 重新加载配置"
    echo "  test                       - 测试配置"
    echo ""
    echo "示例:"
    echo "  saltgoat nginx create example.com"
    echo "  saltgoat nginx delete test.com"
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
