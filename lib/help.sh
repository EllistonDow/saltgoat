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
    echo "=========================================="
    echo "    SaltGoat - LEMP Stack Automation"
    echo "=========================================="
    echo ""
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
    echo "=========================================="
    echo "    更多信息请访问项目文档"
    echo "=========================================="
}
