#!/bin/bash
# SaltGoat 配置一致性测试
# tests/consistency-test.sh

echo "SaltGoat 配置一致性测试"
echo "=========================================="

# 测试路径检测
test_path_detection() {
    echo "1. 路径检测测试:"
    echo "----------------------------------------"
    
    # Nginx路径检测
    if [ -f "/etc/nginx/nginx.conf" ]; then
        echo "  Nginx: /etc/nginx/nginx.conf ✅"
    elif [ -f "/usr/local/nginx/conf/nginx.conf" ]; then
        echo "  Nginx: /usr/local/nginx/conf/nginx.conf ✅"
    else
        echo "  Nginx: 未检测到配置文件 ❌"
    fi
    
    # PHP版本检测
    for version in 8.3 8.2 8.1 8.0 7.4; do
        if [ -f "/etc/php/$version/fpm/php.ini" ]; then
            echo "  PHP: $version (/etc/php/$version/fpm/php.ini) ✅"
            break
        fi
    done
    
    # MySQL路径检测
    if [ -f "/etc/mysql/mysql.conf.d/lemp.cnf" ]; then
        echo "  MySQL: /etc/mysql/mysql.conf.d/lemp.cnf ✅"
    elif [ -f "/etc/mysql/my.cnf" ]; then
        echo "  MySQL: /etc/mysql/my.cnf ✅"
    else
        echo "  MySQL: 未检测到配置文件 ❌"
    fi
}

# 测试防火墙检测
test_firewall_detection() {
    echo ""
    echo "2. 防火墙检测测试:"
    echo "----------------------------------------"
    
    if command -v ufw >/dev/null 2>&1; then
        echo "  UFW: 已安装 ✅"
        echo "  状态: $(sudo ufw status | head -1)"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        echo "  Firewalld: 已安装 ✅"
        echo "  状态: $(sudo firewall-cmd --state 2>/dev/null)"
    elif command -v iptables >/dev/null 2>&1; then
        echo "  iptables: 已安装 ✅"
        echo "  规则数量: $(sudo iptables -L | wc -l)"
    else
        echo "  防火墙: 未检测到 ❌"
    fi
}

# 测试系统资源检测
test_system_resources() {
    echo ""
    echo "3. 系统资源检测测试:"
    echo "----------------------------------------"
    
    # 内存检测
    TOTAL_MEMORY_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_MEMORY_GB=$((TOTAL_MEMORY_KB / 1024 / 1024))
    echo "  总内存: ${TOTAL_MEMORY_GB}GB"
    
    # CPU检测
    CPU_CORES=$(nproc)
    echo "  CPU核心: ${CPU_CORES}个"
    
    # 磁盘检测
    DISK_USAGE=$(df / | awk 'NR==2{print $5}')
    echo "  根分区使用率: ${DISK_USAGE}"
    
    # 网络检测
    SERVER_IP=$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
    echo "  服务器IP: ${SERVER_IP}"
}

# 测试服务检测
test_service_detection() {
    echo ""
    echo "4. 服务检测测试:"
    echo "----------------------------------------"
    
    local services=("nginx" "mysql" "php8.3-fpm" "valkey" "opensearch" "rabbitmq")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo "  $service: 运行中 ✅"
        elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
            echo "  $service: 已安装但未运行 ⚠️"
        else
            echo "  $service: 未安装 ❌"
        fi
    done
}

# 测试配置一致性
test_config_consistency() {
    echo ""
    echo "5. 配置一致性测试:"
    echo "----------------------------------------"
    
    # 检查SaltGoat版本
    local saltgoat_path
    saltgoat_path=$(which saltgoat 2>/dev/null || find /usr/local/bin /home -name "saltgoat" 2>/dev/null | head -1)
    if [ -n "$saltgoat_path" ] && [ -f "$saltgoat_path" ]; then
        SCRIPT_VERSION=$(grep "SCRIPT_STATIC_VERSION=" "$saltgoat_path" | cut -d'"' -f2)
        echo "  SaltGoat版本: $SCRIPT_VERSION ✅"
    fi
    
    # 检查配置文件权限
    local config_files=(
        "/etc/nginx/nginx.conf"
        "/etc/php/8.3/fpm/php.ini"
        "/etc/mysql/mysql.conf.d/lemp.cnf"
        "/etc/valkey/valkey.conf"
    )
    
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            PERMS=$(stat -c "%a" "$file" 2>/dev/null)
            OWNER=$(stat -c "%U:%G" "$file" 2>/dev/null)
            echo "  $(basename "$file"): $PERMS ($OWNER) ✅"
        fi
    done
}

# 运行所有测试
run_all_tests() {
    test_path_detection
    test_firewall_detection
    test_system_resources
    test_service_detection
    test_config_consistency
    
    echo ""
    echo "=========================================="
    echo "配置一致性测试完成"
    echo "=========================================="
}

# 主函数
main() {
    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        echo "用法: $0 [选项]"
        echo ""
        echo "选项:"
        echo "  --help, -h    显示帮助信息"
        echo "  --path        只测试路径检测"
        echo "  --firewall    只测试防火墙检测"
        echo "  --resources   只测试系统资源检测"
        echo "  --services    只测试服务检测"
        echo "  --config      只测试配置一致性"
        echo ""
        exit 0
    fi
    
    case "$1" in
        "--path")
            test_path_detection
            ;;
        "--firewall")
            test_firewall_detection
            ;;
        "--resources")
            test_system_resources
            ;;
        "--services")
            test_service_detection
            ;;
        "--config")
            test_config_consistency
            ;;
        *)
            run_all_tests
            ;;
    esac
}

# 执行主函数
main "$@"
