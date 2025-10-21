#!/bin/bash
# 网络速度测试模块 - 使用开源speedtest
# services/speedtest.sh

# 网络速度测试
speedtest() {
    log_highlight "SaltGoat 网络速度测试..."
    
    echo "网络速度测试"
    echo "=========================================="
    
    # 检查是否安装了speedtest-cli
    if ! command -v speedtest-cli >/dev/null 2>&1; then
        log_info "安装 speedtest-cli..."
        if command -v apt >/dev/null 2>&1; then
            sudo apt update >/dev/null 2>&1
            sudo apt install -y speedtest-cli >/dev/null 2>&1
        elif command -v pip3 >/dev/null 2>&1; then
            pip3 install --break-system-packages speedtest-cli >/dev/null 2>&1
        elif command -v pip >/dev/null 2>&1; then
            pip install --break-system-packages speedtest-cli >/dev/null 2>&1
        else
            log_error "无法安装 speedtest-cli"
            log_info "请手动安装: sudo apt install speedtest-cli"
            exit 1
        fi
    fi
    
    # 创建测试结果目录
    local speedtest_dir="/tmp/saltgoat_speedtest_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$speedtest_dir"
    
    # 执行速度测试
    speedtest_detailed "$speedtest_dir"
    
    # 生成测试报告
    speedtest_generate_report "$speedtest_dir"
    
    log_success "网络速度测试完成！"
    log_info "测试结果保存在: $speedtest_dir"
}

# 详细速度测试
speedtest_detailed() {
    local speedtest_dir="$1"
    
    echo "执行网络速度测试..."
    
    # 基本速度测试
    echo "基本速度测试:"
    echo "----------------------------------------"
    speedtest-cli --simple > "$speedtest_dir/basic_speedtest.txt" 2>&1
    cat "$speedtest_dir/basic_speedtest.txt"
    
    echo ""
    echo "详细速度测试:"
    echo "----------------------------------------"
    speedtest-cli --json > "$speedtest_dir/detailed_speedtest.json" 2>&1
    
    # 解析JSON结果
    if [[ -f "$speedtest_dir/detailed_speedtest.json" ]]; then
        local download_speed=$(python3 -c "
import json
try:
    with open('$speedtest_dir/detailed_speedtest.json', 'r') as f:
        data = json.load(f)
    print(f\"{data['download'] / 1000000:.2f} Mbps\")
except:
    print('解析失败')
" 2>/dev/null)
        
        local upload_speed=$(python3 -c "
import json
try:
    with open('$speedtest_dir/detailed_speedtest.json', 'r') as f:
        data = json.load(f)
    print(f\"{data['upload'] / 1000000:.2f} Mbps\")
except:
    print('解析失败')
" 2>/dev/null)
        
        local ping=$(python3 -c "
import json
try:
    with open('$speedtest_dir/detailed_speedtest.json', 'r') as f:
        data = json.load(f)
    print(f\"{data['ping']:.2f} ms\")
except:
    print('解析失败')
" 2>/dev/null)
        
        echo "下载速度: $download_speed"
        echo "上传速度: $upload_speed"
        echo "延迟: $ping"
    fi
    
    # 服务器信息测试
    echo ""
    echo "测试服务器信息:"
    echo "----------------------------------------"
    speedtest-cli --list > "$speedtest_dir/server_list.txt" 2>&1
    head -10 "$speedtest_dir/server_list.txt"
    
    # 指定服务器测试（选择最近的服务器）
    echo ""
    echo "指定服务器测试:"
    echo "----------------------------------------"
    local nearest_server=$(speedtest-cli --list | head -5 | tail -1 | awk '{print $1}')
    if [[ -n "$nearest_server" ]]; then
        speedtest-cli --server "$nearest_server" --simple > "$speedtest_dir/server_specific.txt" 2>&1
        cat "$speedtest_dir/server_specific.txt"
    fi
    
    echo "  ✅ 网络速度测试完成"
}

# 生成测试报告
speedtest_generate_report() {
    local speedtest_dir="$1"
    
    echo "生成测试报告..."
    
    cat > "$speedtest_dir/speedtest_report.md" << EOF
# SaltGoat 网络速度测试报告

**测试时间**: $(date)
**测试环境**: $(hostname)

## 测试概述

本报告包含了 SaltGoat 系统的网络速度测试结果，使用开源 speedtest-cli 工具。

## 测试结果

### 1. 基本速度测试
\`\`\`
$(cat "$speedtest_dir/basic_speedtest.txt")
\`\`\`

### 2. 详细速度测试
\`\`\`
$(cat "$speedtest_dir/detailed_speedtest.json")
\`\`\`

### 3. 可用服务器列表
\`\`\`
$(head -20 "$speedtest_dir/server_list.txt")
\`\`\`

### 4. 指定服务器测试
\`\`\`
$(cat "$speedtest_dir/server_specific.txt")
\`\`\`

## 测试总结

本次网络速度测试使用开源 speedtest-cli 工具完成。
测试结果可用于网络性能评估和优化参考。

---
*报告由 SaltGoat 自动生成*
EOF
    
    echo "  ✅ 测试报告生成完成"
    echo ""
    echo "测试报告位置: $speedtest_dir/speedtest_report.md"
}

# 快速速度测试
speedtest_quick() {
    log_highlight "SaltGoat 快速网络速度测试..."
    
    echo "快速网络速度测试"
    echo "=========================================="
    
    # 检查是否安装了speedtest-cli
    if ! command -v speedtest-cli >/dev/null 2>&1; then
        log_error "speedtest-cli 未安装"
        log_info "请先运行: saltgoat speedtest"
        exit 1
    fi
    
    # 执行快速测试
    echo "执行快速测试..."
    speedtest-cli --simple
    
    log_success "快速网络速度测试完成！"
}

# 服务器选择测试
speedtest_server() {
    local server_id="$1"
    
    if [[ -z "$server_id" ]]; then
        log_error "用法: saltgoat speedtest server <server_id>"
        log_info "示例: saltgoat speedtest server 1234"
        log_info "使用 'saltgoat speedtest list' 查看可用服务器"
        exit 1
    fi
    
    log_highlight "SaltGoat 指定服务器网络速度测试..."
    
    echo "指定服务器测试: $server_id"
    echo "=========================================="
    
    # 检查是否安装了speedtest-cli
    if ! command -v speedtest-cli >/dev/null 2>&1; then
        log_error "speedtest-cli 未安装"
        log_info "请先运行: saltgoat speedtest"
        exit 1
    fi
    
    # 执行指定服务器测试
    echo "执行指定服务器测试..."
    speedtest-cli --server "$server_id" --simple
    
    log_success "指定服务器网络速度测试完成！"
}

# 列出可用服务器
speedtest_list() {
    log_highlight "SaltGoat 可用服务器列表..."
    
    echo "可用测试服务器"
    echo "=========================================="
    
    # 检查是否安装了speedtest-cli
    if ! command -v speedtest-cli >/dev/null 2>&1; then
        log_error "speedtest-cli 未安装"
        log_info "请先运行: saltgoat speedtest"
        exit 1
    fi
    
    # 列出服务器
    echo "获取服务器列表..."
    speedtest-cli --list | head -20
    
    echo ""
    echo "使用指定服务器测试:"
    echo "  saltgoat speedtest server <server_id>"
    
    log_success "服务器列表获取完成！"
}
