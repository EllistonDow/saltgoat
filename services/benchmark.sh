#!/bin/bash
# 性能基准测试模块 - 简化版本
# services/benchmark.sh

# 性能基准测试
benchmark() {
    log_highlight "SaltGoat 性能基准测试..."
    
    echo "系统性能基准测试"
    echo "=========================================="
    
    # 创建测试结果目录
    local benchmark_dir="/tmp/saltgoat_benchmark_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$benchmark_dir"
    
    # 系统信息收集
    benchmark_system_info "$benchmark_dir"
    
    # CPU 性能测试
    benchmark_cpu "$benchmark_dir"
    
    # 内存性能测试
    benchmark_memory "$benchmark_dir"
    
    # 磁盘 I/O 测试
    benchmark_disk "$benchmark_dir"
    
    # 网络性能测试
    benchmark_network "$benchmark_dir"
    
    # 数据库性能测试
    benchmark_database "$benchmark_dir"
    
    # Web 服务器性能测试
    benchmark_web "$benchmark_dir"
    
    # 生成测试报告
    benchmark_generate_report "$benchmark_dir"
    
    log_success "性能基准测试完成！"
    log_info "测试结果保存在: $benchmark_dir"
}

# 系统信息收集
benchmark_system_info() {
    local benchmark_dir="$1"
    
    echo "收集系统信息..."
    
    cat > "$benchmark_dir/system_info.txt" << EOF
SaltGoat 性能基准测试报告
测试时间: $(date)
==========================================

系统信息:
EOF
    
    # 使用直接命令收集系统信息
    echo "CPU 信息:" >> "$benchmark_dir/system_info.txt"
    lscpu >> "$benchmark_dir/system_info.txt" 2>/dev/null
    
    echo "" >> "$benchmark_dir/system_info.txt"
    echo "内存信息:" >> "$benchmark_dir/system_info.txt"
    free -h >> "$benchmark_dir/system_info.txt" 2>/dev/null
    
    echo "" >> "$benchmark_dir/system_info.txt"
    echo "磁盘信息:" >> "$benchmark_dir/system_info.txt"
    df -h >> "$benchmark_dir/system_info.txt" 2>/dev/null
    
    echo "  ✅ 系统信息收集完成"
}

# CPU 性能测试
benchmark_cpu() {
    local benchmark_dir="$1"
    
    echo "CPU 性能测试..."
    
    # 确保目录存在
    mkdir -p "$benchmark_dir"
    
    # CPU 基准测试 - 使用简单的计算测试
    local cpu_test_start=$(date +%s.%N)
    echo 'scale=1000; 4*a(1)' | bc -l >/dev/null 2>&1
    local cpu_test_end=$(date +%s.%N)
    local cpu_test_time=$(echo "$cpu_test_end - $cpu_test_start" | bc 2>/dev/null || echo "计算失败")
    
    # CPU 核心数
    local cpu_cores=$(nproc)
    
    cat > "$benchmark_dir/cpu_benchmark.txt" << EOF
CPU 性能测试结果
==========================================

CPU 核心数: $cpu_cores
基准测试时间: ${cpu_test_time}秒

CPU 使用率测试:
EOF
    
    # CPU 使用率测试
    top -bn1 | grep 'Cpu(s)' >> "$benchmark_dir/cpu_benchmark.txt" 2>/dev/null
    
    echo "  ✅ CPU 性能测试完成"
}

# 内存性能测试
benchmark_memory() {
    local benchmark_dir="$1"
    
    echo "内存性能测试..."
    
    # 确保目录存在
    mkdir -p "$benchmark_dir"
    
    # 内存分配测试
    local mem_test_start=$(date +%s.%N)
    dd if=/dev/zero of=/tmp/mem_test bs=1M count=100 2>/dev/null
    local mem_test_end=$(date +%s.%N)
    local mem_test_time=$(echo "$mem_test_end - $mem_test_start" | bc 2>/dev/null || echo "计算失败")
    
    # 内存读取测试
    local mem_read_start=$(date +%s.%N)
    dd if=/tmp/mem_test of=/dev/null bs=1M 2>/dev/null
    local mem_read_end=$(date +%s.%N)
    local mem_read_time=$(echo "$mem_read_end - $mem_read_start" | bc 2>/dev/null || echo "计算失败")
    
    cat > "$benchmark_dir/memory_benchmark.txt" << EOF
内存性能测试结果
==========================================

内存分配测试时间: ${mem_test_time}秒
内存读取测试时间: ${mem_read_time}秒

内存使用情况:
EOF
    
    free -h >> "$benchmark_dir/memory_benchmark.txt" 2>/dev/null
    
    # 清理测试文件
    rm -f /tmp/mem_test
    
    echo "  ✅ 内存性能测试完成"
}

# 磁盘 I/O 测试
benchmark_disk() {
    local benchmark_dir="$1"
    
    echo "磁盘 I/O 测试..."
    
    # 确保目录存在
    mkdir -p "$benchmark_dir"
    
    # 磁盘写入测试
    local disk_write_start=$(date +%s.%N)
    dd if=/dev/zero of=/tmp/disk_test bs=1M count=500 2>/dev/null
    local disk_write_end=$(date +%s.%N)
    local disk_write_time=$(echo "$disk_write_end - $disk_write_start" | bc 2>/dev/null || echo "计算失败")
    
    # 磁盘读取测试
    local disk_read_start=$(date +%s.%N)
    dd if=/tmp/disk_test of=/dev/null bs=1M 2>/dev/null
    local disk_read_end=$(date +%s.%N)
    local disk_read_time=$(echo "$disk_read_end - $disk_read_start" | bc 2>/dev/null || echo "计算失败")
    
    # 随机 I/O 测试
    local random_io_start=$(date +%s.%N)
    dd if=/dev/urandom of=/tmp/random_test bs=1M count=100 2>/dev/null
    local random_io_end=$(date +%s.%N)
    local random_io_time=$(echo "$random_io_end - $random_io_start" | bc 2>/dev/null || echo "计算失败")
    
    cat > "$benchmark_dir/disk_benchmark.txt" << EOF
磁盘 I/O 测试结果
==========================================

磁盘写入测试时间: ${disk_write_time}秒
磁盘读取测试时间: ${disk_read_time}秒
随机 I/O 测试时间: ${random_io_time}秒

磁盘使用情况:
EOF
    
    df -h >> "$benchmark_dir/disk_benchmark.txt" 2>/dev/null
    
    # 清理测试文件
    rm -f /tmp/disk_test /tmp/random_test
    
    echo "  ✅ 磁盘 I/O 测试完成"
}

# 网络性能测试
benchmark_network() {
    local benchmark_dir="$1"
    
    echo "网络性能测试..."
    
    # 确保目录存在
    mkdir -p "$benchmark_dir"
    
    # 网络延迟测试
    local ping_result=$(ping -c 4 8.8.8.8 2>/dev/null | grep "avg" | tail -1)
    
    # 网络速度测试 (如果有 wget)
    local download_speed="未测试"
    if command -v wget >/dev/null 2>&1; then
        local download_start=$(date +%s.%N)
        wget -O /dev/null http://speedtest.tele2.net/100MB.zip >/dev/null 2>&1
        local download_end=$(date +%s.%N)
        local download_time=$(echo "$download_end - $download_start" | bc 2>/dev/null || echo "计算失败")
        download_speed="下载时间: ${download_time}秒"
    fi
    
    cat > "$benchmark_dir/network_benchmark.txt" << EOF
网络性能测试结果
==========================================

网络延迟测试:
$ping_result

网络速度测试:
$download_speed

网络接口信息:
EOF
    
    ip addr show >> "$benchmark_dir/network_benchmark.txt" 2>/dev/null
    
    echo "  ✅ 网络性能测试完成"
}

# 数据库性能测试
benchmark_database() {
    local benchmark_dir="$1"
    
    echo "数据库性能测试..."
    
    # 确保目录存在
    mkdir -p "$benchmark_dir"
    
    # 检查 MySQL 是否运行
    local mysql_status=$(systemctl is-active mysql 2>/dev/null || echo "inactive")
    
    if [[ "$mysql_status" == "active" ]]; then
        cat > "$benchmark_dir/database_benchmark.txt" << EOF
数据库性能测试结果
==========================================

MySQL 服务状态: 运行中

数据库连接测试:
EOF
        
        # 数据库连接测试
        mysql -e 'SELECT 1;' >> "$benchmark_dir/database_benchmark.txt" 2>/dev/null
        
        echo "" >> "$benchmark_dir/database_benchmark.txt"
        echo "数据库状态信息:" >> "$benchmark_dir/database_benchmark.txt"
        mysql -e 'SHOW STATUS;' >> "$benchmark_dir/database_benchmark.txt" 2>/dev/null
        
        echo "  ✅ 数据库性能测试完成"
    else
        cat > "$benchmark_dir/database_benchmark.txt" << EOF
数据库性能测试结果
==========================================

MySQL 服务状态: 未运行
跳过数据库性能测试
EOF
        echo "  ⚠️  MySQL 未运行，跳过数据库测试"
    fi
}

# Web 服务器性能测试
benchmark_web() {
    local benchmark_dir="$1"
    
    echo "Web 服务器性能测试..."
    
    # 确保目录存在
    mkdir -p "$benchmark_dir"
    
    # 检查 Nginx 是否运行
    local nginx_status=$(systemctl is-active nginx 2>/dev/null || echo "inactive")
    
    if [[ "$nginx_status" == "active" ]]; then
        cat > "$benchmark_dir/web_benchmark.txt" << EOF
Web 服务器性能测试结果
==========================================

Nginx 服务状态: 运行中

Web 服务器配置:
EOF
        
        # Nginx 配置信息
        nginx -T 2>/dev/null | head -50 >> "$benchmark_dir/web_benchmark.txt"
        
        echo "" >> "$benchmark_dir/web_benchmark.txt"
        echo "Nginx 状态信息:" >> "$benchmark_dir/web_benchmark.txt"
        curl -s http://localhost/nginx_status >> "$benchmark_dir/web_benchmark.txt" 2>/dev/null
        
        echo "  ✅ Web 服务器性能测试完成"
    else
        cat > "$benchmark_dir/web_benchmark.txt" << EOF
Web 服务器性能测试结果
==========================================

Nginx 服务状态: 未运行
跳过 Web 服务器性能测试
EOF
        echo "  ⚠️  Nginx 未运行，跳过 Web 服务器测试"
    fi
}

# 生成测试报告
benchmark_generate_report() {
    local benchmark_dir="$1"
    
    echo "生成测试报告..."
    
    cat > "$benchmark_dir/benchmark_report.md" << EOF
# SaltGoat 性能基准测试报告

**测试时间**: $(date)
**测试环境**: $(hostname)

## 测试概述

本报告包含了 SaltGoat 系统的全面性能基准测试结果。

## 测试结果

### 1. 系统信息
\`\`\`
$(cat "$benchmark_dir/system_info.txt")
\`\`\`

### 2. CPU 性能
\`\`\`
$(cat "$benchmark_dir/cpu_benchmark.txt")
\`\`\`

### 3. 内存性能
\`\`\`
$(cat "$benchmark_dir/memory_benchmark.txt")
\`\`\`

### 4. 磁盘 I/O 性能
\`\`\`
$(cat "$benchmark_dir/disk_benchmark.txt")
\`\`\`

### 5. 网络性能
\`\`\`
$(cat "$benchmark_dir/network_benchmark.txt")
\`\`\`

### 6. 数据库性能
\`\`\`
$(cat "$benchmark_dir/database_benchmark.txt")
\`\`\`

### 7. Web 服务器性能
\`\`\`
$(cat "$benchmark_dir/web_benchmark.txt")
\`\`\`

## 测试总结

本次性能基准测试涵盖了系统的各个方面。
测试结果可用于性能优化和系统调优的参考。

---
*报告由 SaltGoat 自动生成*
EOF
    
    echo "  ✅ 测试报告生成完成"
    echo ""
    echo "测试报告位置: $benchmark_dir/benchmark_report.md"
}