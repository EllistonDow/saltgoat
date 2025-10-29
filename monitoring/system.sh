#!/bin/bash
# 系统监控模块 - 完全 Salt 原生功能
# services/monitor.sh

# 监控配置
MONITOR_LOG_DIR="/var/log/saltgoat/monitor"
MONITOR_CONFIG_DIR="/etc/saltgoat/monitor"
MONITOR_THRESHOLD_CPU=80
MONITOR_THRESHOLD_MEMORY=85
MONITOR_THRESHOLD_DISK=90

# 确保监控目录存在
ensure_monitor_dirs() {
    salt-call --local file.mkdir "$MONITOR_LOG_DIR" >/dev/null 2>&1
    salt-call --local file.mkdir "$MONITOR_CONFIG_DIR" >/dev/null 2>&1
}

# 系统状态监控
monitor_system_status() {
    log_highlight "系统状态监控..."
    
    echo "系统基本信息:"
    echo "=========================================="
    
    # 系统信息
    local hostname
    hostname=$(salt-call --local cmd.run "hostname" 2>/dev/null)
    local uptime
    uptime=$(salt-call --local cmd.run "uptime" 2>/dev/null)
    local load_avg
    load_avg=$(salt-call --local cmd.run "uptime" 2>/dev/null | grep -o 'load average:.*' | cut -d: -f2)
    
    echo "主机名: $hostname"
    echo "运行时间: $uptime"
    echo "系统负载: $load_avg"
    
    echo ""
    echo "系统资源使用情况:"
    echo "----------------------------------------"
    
    # CPU 使用率
    local cpu_usage
    cpu_usage=$(salt-call --local cmd.run "top -bn1" 2>/dev/null | grep 'Cpu(s)' | awk '{print $2}' | sed 's/%//')
    echo "CPU 使用率: ${cpu_usage}%"
    
    # 内存使用情况
    local mem_info
    mem_info=$(salt-call --local cmd.run "free -h" 2>/dev/null)
    echo "内存使用情况:"
    echo "$mem_info"
    
    # 磁盘使用情况
    local disk_info
    disk_info=$(salt-call --local cmd.run "df -h" 2>/dev/null)
    echo "磁盘使用情况:"
    echo "$disk_info"
    
    echo ""
    echo "网络连接状态:"
    echo "----------------------------------------"
    local network_info
    network_info=$(salt-call --local cmd.run "ss -tlnp" 2>/dev/null)
    echo "$network_info"
}

# 服务状态监控
monitor_service_status() {
    log_highlight "服务状态监控..."
    
    echo "关键服务状态:"
    echo "=========================================="
    
    local services=("nginx" "mysql" "php8.3-fpm" "valkey" "rabbitmq" "opensearch")
    
    for service in "${services[@]}"; do
        local status
        status=$(salt-call --local service.status "$service" 2>/dev/null | grep -o "True\|False")
        if [[ "$status" == "True" ]]; then
            log_success "✅ $service: 正在运行"
        else
            log_error "❌ $service: 未运行"
        fi
    done
    
    echo ""
    echo "服务详细信息:"
    echo "----------------------------------------"
    
    # 检查服务配置
    for service in "${services[@]}"; do
        local status
        status=$(salt-call --local service.status "$service" 2>/dev/null | grep -o "True\|False")
        if [[ "$status" == "True" ]]; then
            local pid
            pid=$(systemctl show "$service" --property=MainPID --value 2>/dev/null | tr -d ' ')
            if [[ -z "$pid" || "$pid" == "0" ]]; then
                pid=$(pgrep -f "$service" 2>/dev/null | head -1)
            fi

            if [[ -n "$pid" ]]; then
                local proc_info
                proc_info=$(ps -o pid,ppid,%cpu,%mem,cmd -p "$pid" 2>/dev/null | tail -n +2)
                if [[ -n "$proc_info" ]]; then
                    echo "$service (PID: $pid):"
                    echo "$proc_info"
                else
                    echo "$service (PID: $pid): 进程信息不可用"
                fi
            else
                echo "$service (PID: 未找到):"
            fi
            echo "----------------------------------------"
        fi
    done
}

# 资源使用监控
monitor_resource_usage() {
    log_highlight "资源使用监控..."
    
    echo "CPU 使用情况:"
    echo "=========================================="
    
    # CPU 详细信息
    local cpu_info
    cpu_info=$(salt-call --local cmd.run "lscpu" 2>/dev/null)
    echo "$cpu_info"
    
    echo ""
    echo "CPU 使用率最高的进程:"
    echo "----------------------------------------"
    local top_processes
    top_processes=$(salt-call --local cmd.run "ps aux" 2>/dev/null | sort -k3 -nr | head -10)
    echo "$top_processes"
    
    echo ""
    echo "内存使用情况:"
    echo "----------------------------------------"
    
    # 内存详细信息
    local mem_info
    mem_info=$(salt-call --local cmd.run "cat /proc/meminfo" 2>/dev/null)
    echo "$mem_info"
    
    echo ""
    echo "内存使用率最高的进程:"
    echo "----------------------------------------"
    local top_mem_processes
    top_mem_processes=$(salt-call --local cmd.run "ps aux" 2>/dev/null | sort -k4 -nr | head -10)
    echo "$top_mem_processes"
    
    echo ""
    echo "磁盘 I/O 统计:"
    echo "----------------------------------------"
    local disk_io
    disk_io=$(salt-call --local cmd.run "iostat -xz 1 2" 2>/dev/null)
    echo "$disk_io"
}

# 网络监控
monitor_network_status() {
    log_highlight "网络状态监控..."
    
    echo "网络接口状态:"
    echo "=========================================="
    
    # 网络接口信息
    local network_interfaces
    network_interfaces=$(salt-call --local cmd.run "ip -s link" 2>/dev/null)
    echo "$network_interfaces"
    
    echo ""
    echo "网络连接统计:"
    echo "----------------------------------------"
    local connection_stats
    connection_stats=$(salt-call --local cmd.run "ss -s" 2>/dev/null)
    echo "$connection_stats"
    
    echo ""
    echo "监听端口:"
    echo "----------------------------------------"
    local listening_ports
    listening_ports=$(salt-call --local cmd.run "ss -tlnp" 2>/dev/null)
    echo "$listening_ports"
    
    echo ""
    echo "网络流量统计:"
    echo "----------------------------------------"
    local traffic_stats
    traffic_stats=$(salt-call --local cmd.run "cat /proc/net/dev" 2>/dev/null)
    echo "$traffic_stats"
}

# 日志监控
monitor_log_status() {
    log_highlight "日志状态监控..."
    
    echo "系统日志状态:"
    echo "=========================================="
    
    # 检查关键日志文件
    local log_files=(
        "/var/log/syslog"
        "/var/log/auth.log"
        "/var/log/kern.log"
        "/var/log/nginx/error.log"
        "/var/log/mysql/error.log"
        "/var/log/php8.3-fpm.log"
    )
    
    for log_file in "${log_files[@]}"; do
        if salt-call --local file.file_exists "$log_file" --out=txt 2>/dev/null | grep -q "True"; then
            local size
            size=$(salt-call --local cmd.run "du -h $log_file" 2>/dev/null)
            local lines
            lines=$(salt-call --local cmd.run "wc -l $log_file" 2>/dev/null)
            echo "✅ $log_file: $size ($lines 行)"
        else
            echo "❌ $log_file: 不存在"
        fi
    done
    
    echo ""
    echo "最近错误日志:"
    echo "----------------------------------------"
    
    # 检查最近的错误
    for log_file in "${log_files[@]}"; do
        if salt-call --local file.file_exists "$log_file" --out=txt 2>/dev/null | grep -q "True"; then
            local recent_errors
            recent_errors=$(salt-call --local cmd.run "bash -lc 'tail -n 5 \"$log_file\" | grep -i error || true'" 2>/dev/null)
            if [[ -n "$recent_errors" ]]; then
                echo "=== $log_file ==="
                echo "$recent_errors"
            fi
        fi
    done
}

# 安全监控
monitor_security_status() {
    log_highlight "安全状态监控..."
    
    echo "安全状态检查:"
    echo "=========================================="
    
    # 检查防火墙状态
    local firewall_status
    firewall_status=$(salt-call --local cmd.run "ufw status" 2>/dev/null)
    echo "防火墙状态:"
    echo "$firewall_status"
    
    echo ""
    echo "最近登录记录:"
    echo "----------------------------------------"
    local login_records
    login_records=$(salt-call --local cmd.run "last -n 10" 2>/dev/null)
    echo "$login_records"
    
    echo ""
    echo "SSH 连接状态:"
    echo "----------------------------------------"
    local ssh_connections
    ssh_connections=$(salt-call --local cmd.run "bash -lc 'ss -tlnp | grep ssh || true'" 2>/dev/null)
    echo "$ssh_connections"
    
    echo ""
    echo "系统更新状态:"
    echo "----------------------------------------"
    local update_status
    update_status=$(salt-call --local cmd.run "bash -lc 'apt list --upgradable 2>/dev/null | wc -l'" 2>/dev/null)
    echo "可用更新数量: $update_status"
}

# 性能监控
monitor_performance() {
    log_highlight "性能监控..."
    
    echo "系统性能指标:"
    echo "=========================================="
    
    # 系统负载
    local load_info
    load_info=$(salt-call --local cmd.run "cat /proc/loadavg" 2>/dev/null)
    echo "系统负载: $load_info"

    # CPU 使用率
    local cpu_usage
    cpu_usage=$(LC_ALL=C top -bn1 2>/dev/null | awk '/Cpu\(s\)/ {print $2}' | tr -d '%us,')
    echo "CPU 使用率: ${cpu_usage}%"

    # CPU 核心数
    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null)
    echo "CPU 核心数: $cpu_cores"

    # 内存使用率
    local mem_usage
    mem_usage=$(free 2>/dev/null | awk '/Mem/ {printf "%.1f", ($3/$2)*100.0}')
    echo "内存使用率: ${mem_usage}%"

    # 磁盘使用率
    local disk_usage
    disk_usage=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}')
    echo "根分区使用率: $disk_usage"
    
    echo ""
    echo "性能警告:"
    echo "----------------------------------------"
    
    # 检查性能阈值
    local cpu_usage_num
    cpu_usage_num="${cpu_usage%.*}"
    if [[ -z "$cpu_usage_num" ]]; then
        cpu_usage_num=0
    fi
    local mem_usage_num
    mem_usage_num="${mem_usage%.*}"
    if [[ -z "$mem_usage_num" ]]; then
        mem_usage_num=0
    fi

    if [[ $cpu_usage_num -gt $MONITOR_THRESHOLD_CPU ]]; then
        log_warning "⚠️ CPU 使用率过高: ${cpu_usage}% (阈值: ${MONITOR_THRESHOLD_CPU}%)"
    fi

    if [[ $mem_usage_num -gt $MONITOR_THRESHOLD_MEMORY ]]; then
        log_warning "⚠️ 内存使用率过高: ${mem_usage}% (阈值: ${MONITOR_THRESHOLD_MEMORY}%)"
    fi
    
    if [[ "$disk_usage" =~ [0-9]+% ]]; then
        local disk_num
        disk_num="${disk_usage%\%}"
        if [[ $disk_num -gt $MONITOR_THRESHOLD_DISK ]]; then
            log_warning "⚠️ 磁盘使用率过高: $disk_usage (阈值: ${MONITOR_THRESHOLD_DISK}%)"
        fi
    fi
}

# 生成监控报告
monitor_generate_report() {
    local report_name="$1"
    
    if [[ -z "$report_name" ]]; then
        report_name="monitor_report_$(date +%Y%m%d_%H%M%S)"
    fi
    
    log_highlight "生成监控报告: $report_name"
    ensure_monitor_dirs
    
    local report_file="$MONITOR_LOG_DIR/${report_name}.txt"
    
    # 生成报告内容
    {
        echo "SaltGoat 系统监控报告"
        echo "======================"
        echo "生成时间: $(date)"
        echo "系统信息: $(uname -a)"
        echo ""
        
        echo "=== 系统状态 ==="
        monitor_system_status
        
        echo ""
        echo "=== 服务状态 ==="
        monitor_service_status
        
        echo ""
        echo "=== 资源使用 ==="
        monitor_resource_usage
        
        echo ""
        echo "=== 网络状态 ==="
        monitor_network_status
        
        echo ""
        echo "=== 日志状态 ==="
        monitor_log_status
        
        echo ""
        echo "=== 安全状态 ==="
        monitor_security_status
        
        echo ""
        echo "=== 性能监控 ==="
        monitor_performance
        
        echo ""
        echo "======================"
        echo "报告结束"
    } > "$report_file" 2>&1
    
    log_success "监控报告已生成: $report_file"
}

# 实时监控
monitor_realtime() {
    local duration="${1:-60}"
    
    log_highlight "实时监控 (持续 $duration 秒)..."
    log_info "按 Ctrl+C 停止监控"

    if [[ -z "${TERM:-}" ]]; then
        export TERM=xterm-256color
    fi
    
    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + duration))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        clear
        echo "=========================================="
        echo "    SaltGoat 实时监控"
        echo "=========================================="
        echo "监控时间: $(date)"
        echo "剩余时间: $((end_time - $(date +%s))) 秒"
        echo ""
        
        # 显示关键指标
        local cpu_usage
        cpu_usage=$(LC_ALL=C top -bn1 2>/dev/null | awk '/Cpu\(s\)/ {print $2}' | tr -d '%us,')
        local mem_usage
        mem_usage=$(free 2>/dev/null | awk '/Mem/ {printf "%.1f", ($3/$2)*100.0}')
        local load_avg
        load_avg=$(uptime 2>/dev/null | grep -o 'load average:.*' | cut -d: -f2)
        
        echo "CPU 使用率: ${cpu_usage}%"
        echo "内存使用率: ${mem_usage}%"
        echo "系统负载: $load_avg"
        
        echo ""
        echo "活跃进程 (前5名):"
        echo "----------------------------------------"
        ps aux --sort=-%cpu 2>/dev/null | head -6
        
        sleep 5
    done
    
    log_success "实时监控完成"
}

# 监控配置
monitor_config() {
    log_highlight "监控配置管理..."
    
    echo "当前监控配置:"
    echo "=========================================="
    echo "CPU 阈值: ${MONITOR_THRESHOLD_CPU}%"
    echo "内存阈值: ${MONITOR_THRESHOLD_MEMORY}%"
    echo "磁盘阈值: ${MONITOR_THRESHOLD_DISK}%"
    echo "监控日志目录: $MONITOR_LOG_DIR"
    echo "监控配置目录: $MONITOR_CONFIG_DIR"
    
    echo ""
    echo "监控功能:"
    echo "----------------------------------------"
    echo "✅ 系统状态监控"
    echo "✅ 服务状态监控"
    echo "✅ 资源使用监控"
    echo "✅ 网络状态监控"
    echo "✅ 日志状态监控"
    echo "✅ 安全状态监控"
    echo "✅ 性能监控"
    echo "✅ 实时监控"
    echo "✅ 监控报告生成"
}

# 清理监控日志
monitor_cleanup() {
    local days="${1:-7}"
    
    log_highlight "清理监控日志（保留 $days 天）..."
    ensure_monitor_dirs
    
    # 清理旧的监控日志
    local old_files
    old_files=$(salt-call --local file.find "$MONITOR_LOG_DIR" name="*.txt" mtime="+$days" --out=txt 2>/dev/null | tail -n +2 | awk '{print $2}')
    
    local cleaned_count=0
    for file in $old_files; do
        if [[ -n "$file" ]]; then
            local filename
            filename=$(basename "$file")
            log_info "删除过期监控日志: $filename"
            salt-call --local file.remove "$file" >/dev/null 2>&1
            ((cleaned_count++))
        fi
    done
    
    log_success "监控日志清理完成，删除了 $cleaned_count 个文件"
}

# 安装 salt-minion 并启用事件监控
monitor_install_stack() {
    log_highlight "部署 Salt 监控栈..."
    ensure_monitor_dirs

    local need_install=0
    if ! command -v salt-call >/dev/null 2>&1; then
        need_install=1
        log_info "未检测到 salt-call，准备安装 salt-minion..."
    elif ! dpkg -s salt-minion >/dev/null 2>&1; then
        need_install=1
        log_info "salt-call 已存在，但系统未注册 salt-minion 包，准备安装..."
    fi

    if [[ $need_install -eq 1 ]]; then
        sudo apt-get update
        if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y salt-minion; then
            log_info "salt-minion 已通过发行版仓库安装"
        else
            log_warning "apt 未找到 salt-minion，尝试使用 Salt 官方 bootstrap 脚本"
            local bootstrap_script bootstrap_url
            bootstrap_url="https://github.com/saltstack/salt-bootstrap/releases/latest/download/bootstrap-salt.sh"
            bootstrap_script=$(mktemp /tmp/install_salt.XXXXXX)
            if curl -fsSL "$bootstrap_url" -o "$bootstrap_script"; then
                if sudo sh "$bootstrap_script" -P; then
                    log_info "Salt bootstrap 安装完成"
                else
                    log_error "Salt bootstrap 安装失败，请根据输出手动排查"
                    rm -f "$bootstrap_script"
                    return 1
                fi
            else
                log_error "无法下载 Salt bootstrap 脚本，请检查网络后重试"
                rm -f "$bootstrap_script"
                return 1
            fi
            rm -f "$bootstrap_script"
        fi
    else
        log_info "检测到 salt-minion 包已安装，跳过安装步骤"
    fi

    if ! command -v salt-call >/dev/null 2>&1; then
        log_error "salt-call 仍不可用，请检查 salt-minion 安装日志"
        return 1
    fi

    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "^salt-minion\\.service"; then
        if ! systemctl is-enabled salt-minion >/dev/null 2>&1; then
            log_info "启用 salt-minion 服务开机自启..."
            sudo systemctl enable salt-minion >/dev/null 2>&1 || true
        fi
        if ! systemctl is-active salt-minion >/dev/null 2>&1; then
            log_info "启动 salt-minion 服务..."
            sudo systemctl start salt-minion || true
        else
            log_info "salt-minion 服务已在运行"
        fi
    else
        log_warning "未检测到 salt-minion systemd 单元，尝试重新安装以恢复..."
        if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall salt-minion; then
            if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "^salt-minion\\.service"; then
                sudo systemctl enable salt-minion >/dev/null 2>&1 || true
                sudo systemctl start salt-minion || true
            else
                log_warning "重新安装后仍未发现 salt-minion 服务，请手动检查 systemd 配置"
            fi
        else
            log_warning "重新安装 salt-minion 失败，请手动检查"
        fi
    fi

    monitor_enable_events
    log_success "Salt 监控栈部署完成"
}

monitor_install_master() {
    log_highlight "安装 Salt Master 并验证事件驱动能力..."

    local has_minion_service=0
    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "^salt-minion\\.service"; then
        has_minion_service=1
    fi

    if ! command -v salt-call >/dev/null 2>&1 || [[ $has_minion_service -eq 0 ]]; then
        log_info "检测到 salt-minion 未就绪，先执行 Salt 监控栈安装..."
        if ! monitor_install_stack; then
            log_error "部署 salt-minion 失败，无法继续安装 salt-master"
            return 1
        fi
    fi

    local need_master_install=1
    if command -v salt-master >/dev/null 2>&1 && dpkg -s salt-master >/dev/null 2>&1; then
        need_master_install=0
        log_info "salt-master 已安装，跳过软件包安装步骤"
    fi

    if [[ $need_master_install -eq 1 ]]; then
        log_info "安装 salt-master 软件包..."
        sudo apt-get update
        if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y salt-master; then
            log_error "salt-master 安装失败，请检查 APT 输出"
            return 1
        fi
    fi

    local states_dir="${SCRIPT_DIR}/salt/states"
    local pillar_dir="${SCRIPT_DIR}/salt/pillar"
    local module_dir="${SCRIPT_DIR}/salt/_modules"
    local runner_dir="${SCRIPT_DIR}/salt/runners"
    local reactor_dir="${SCRIPT_DIR}/salt/reactor"

    log_info "配置 salt-master 访问本地 SaltGoat 目录..."
    sudo mkdir -p /etc/salt/master.d
    sudo tee /etc/salt/master.d/saltgoat.conf >/dev/null <<EOF
# 自动生成，请使用 saltgoat monitor install-master 更新
file_roots:
  base:
    - "${states_dir}"

pillar_roots:
  base:
    - "${pillar_dir}"

module_dirs:
  - "${module_dir}"
runner_dirs:
  - "${runner_dir}"
reactor_dirs:
  - "${reactor_dir}"
EOF
    sudo chmod 640 /etc/salt/master.d/saltgoat.conf

    log_info "确保 salt-minion 指向本地 salt-master..."
    sudo mkdir -p /etc/salt/minion.d
    sudo tee /etc/salt/minion.d/saltgoat-master.conf >/dev/null <<EOF
master: 127.0.0.1
master_type: str
retry_dns: 30
gather_job_timeout: 10
module_dirs:
  - "${module_dir}"
EOF
    sudo chmod 640 /etc/salt/minion.d/saltgoat-master.conf

    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "^salt-minion\\.service"; then
        log_info "重启 salt-minion 服务以载入 master 配置..."
        sudo systemctl restart salt-minion || log_warning "salt-minion 重启失败，请检查日志"
    fi

    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files | grep -q "^salt-master\\.service" 2>/dev/null; then
            log_info "启用并启动 salt-master 服务..."
            if sudo systemctl enable --now salt-master; then
                log_success "salt-master 服务已运行"
            else
                log_error "salt-master 服务启动失败，请查看 systemctl 日志"
                return 1
            fi
        else
            log_warning "未检测到 salt-master systemd 单元，尝试后台启动 salt-master..."
            if sudo salt-master -d >/dev/null 2>&1; then
                log_success "salt-master 已在后台运行"
            else
                log_error "salt-master 后台启动失败"
                return 1
            fi
        fi
    else
        log_warning "systemctl 不可用，尝试后台启动 salt-master..."
        if sudo salt-master -d >/dev/null 2>&1; then
            log_success "salt-master 已在后台运行"
        else
            log_error "salt-master 后台启动失败"
            return 1
        fi
    fi

    if command -v salt-run >/dev/null 2>&1; then
        log_info "刷新 Salt 扩展模块（不清空状态树）..."
        sudo salt-run saltutil.sync_modules >/dev/null 2>&1 || true
        sudo salt-run saltutil.sync_runners >/dev/null 2>&1 || true
    fi

    log_info "重新应用 Beacon / Reactor 配置..."
    monitor_enable_events

    monitor_verify_master
}

# 启用 Salt Beacons 与 Reactor
monitor_enable_events() {
    log_highlight "配置 Salt Beacons 与 Reactor..."

    sudo salt-call --local saltutil.sync_modules >/dev/null 2>&1 || true

    local result
    result=$(sudo salt-call --local saltgoat.enable_beacons 2>&1)
    echo "$result"
    if echo "$result" | grep -qi "\[ERROR\]"; then
        log_error "[ERROR] 配置 beacons/reactor 失败"
        return 1
    fi
    
    if getent group salt >/dev/null 2>&1; then
        sudo salt-call --local file.chown /etc/salt/minion.d root salt >/dev/null 2>&1 || true
        sudo salt-call --local file.set_mode /etc/salt/minion.d 0750 >/dev/null 2>&1 || true
        if [[ -f /etc/salt/minion.d/beacons.conf ]]; then
            sudo salt-call --local file.chown /etc/salt/minion.d/beacons.conf root salt >/dev/null 2>&1 || true
            sudo salt-call --local file.set_mode /etc/salt/minion.d/beacons.conf 0640 >/dev/null 2>&1 || true
        fi
    fi

    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "^salt-minion\\.service"; then
        if ! systemctl is-active salt-minion >/dev/null 2>&1; then
            log_info "重启 salt-minion 服务以载入新配置..."
            sudo systemctl restart salt-minion || log_warning "salt-minion 重启失败，请检查日志"
        fi
    fi

    log_info "显示当前 Beacon 列表:"
    local beacon_output
    beacon_output=$(sudo salt-call --local beacons.list 2>&1 || true)
    echo "$beacon_output"
    if echo "$beacon_output" | grep -q "beacons: null"; then
        if command -v systemctl >/dev/null 2>&1 && systemctl is-active salt-minion >/dev/null 2>&1; then
            log_warning "beacons.list 返回空结果，Salt Onedir 在本地模式下可能不会回显配置，请改查 /var/log/salt/minion"
        else
            log_warning "未检测到激活的 Beacon，salt-minion 服务可能未运行"
        fi
    fi
    
    log_info "显示当前 Reactor 配置:"
    if command -v salt-run >/dev/null 2>&1; then
        if ! sudo salt-run reactor.list; then
            log_warning "无法读取 reactor 列表（salt-master 未安装或未运行）"
        fi
    else
        log_warning "未检测到 salt-run 命令，跳过 reactor 配置检查"
    fi
}

# 查看 Beacon 状态
monitor_beacon_status() {
    log_highlight "Salt Beacon & Schedule 状态..."
    
    echo ""
    log_info "Beacons:"
    local beacon_status
    beacon_status=$(sudo salt-call --local beacons.list 2>&1 || true)
    echo "$beacon_status"
    if echo "$beacon_status" | grep -q "beacons: null"; then
        if command -v systemctl >/dev/null 2>&1 && systemctl is-active salt-minion >/dev/null 2>&1; then
            log_warning "beacons.list 返回空结果，Salt Onedir 在本地模式下可能不会回显配置，请改查 /var/log/salt/minion"
        else
            log_warning "未检测到激活的 Beacon，salt-minion 服务可能未运行"
        fi
    fi
    
    echo ""
    log_info "Salt Schedule:"
    sudo salt-call --local schedule.list --out=yaml

    if command -v salt-run >/dev/null 2>&1; then
        echo ""
        log_info "Reactor 列表:"
        if ! sudo salt-run reactor.list; then
            log_warning "无法读取 reactor 列表（salt-master 未安装或未运行）"
        fi
    fi
}

monitor_verify_master() {
    log_highlight "验证 Salt Master 与事件驱动组件..."

    if ! command -v salt-master >/dev/null 2>&1; then
        log_error "未检测到 salt-master 命令，请先执行 'saltgoat monitor install-master'"
        return 1
    fi

    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "^salt-master\\.service"; then
        if systemctl is-active salt-master >/dev/null 2>&1; then
            log_success "salt-master 服务处于运行状态"
        else
            log_warning "salt-master 服务未运行，尝试启动..."
            if sudo systemctl restart salt-master; then
                log_success "salt-master 服务已启动"
            else
                log_error "无法启动 salt-master 服务，请检查 systemctl 日志"
                return 1
            fi
        fi
    else
        log_warning "未发现 salt-master systemd 单元，跳过服务状态检查"
    fi

    if command -v salt-run >/dev/null 2>&1; then
        log_info "列出已连接的 Minion:"
        local manage_output
        manage_output=$(sudo salt-run manage.up 2>&1 || true)
        echo "$manage_output"
        if ! grep -q '\S' <<<"$manage_output"; then
            log_warning "未检测到在线的 Salt Minion，请确认 salt-minion 已连接并信任 master"
        fi

        log_info "同步扩展模块..."
        if sudo salt-run saltutil.sync_all >/dev/null 2>&1; then
            log_success "saltutil.sync_all 执行成功"
        else
            log_warning "saltutil.sync_all 执行返回非零，请检查 master 日志"
        fi

        log_info "发送测试事件 'saltgoat/test' ..."
        if sudo salt-run event.send 'saltgoat/test' '{"msg": "salt-master verification"}' >/dev/null 2>&1; then
            log_success "事件发送成功，返回码 0"
        else
            log_warning "测试事件发送失败，请确认 salt-master 事件总线运行正常"
        fi
    else
        log_warning "未检测到 salt-run 命令，跳过 Reactor 验证"
    fi

    log_info "当前 Beacon / Schedule / Reactor 状态:"
    monitor_beacon_status

    log_success "Salt Master 验证流程完成"
}
