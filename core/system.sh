#!/bin/bash
# 系统管理模块
# core/system.sh

# 系统安装
system_install() {
    # 获取 SaltGoat 安装路径（从主脚本目录）
    local saltgoat_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    log_info "SaltGoat 路径: $saltgoat_path"
    
    # 创建系统级符号链接
    log_info "创建系统级符号链接..."
    sudo ln -sf "$saltgoat_path/saltgoat" /usr/local/bin/saltgoat
    sudo chmod +x /usr/local/bin/saltgoat
    
    # 配置 sudoers
    log_info "配置 sudoers..."
    echo "$USER ALL=(ALL) NOPASSWD: /usr/local/bin/saltgoat" | sudo tee /etc/sudoers.d/saltgoat > /dev/null
    sudo chmod 440 /etc/sudoers.d/saltgoat
    
    # 配置用户别名
    log_info "配置用户别名..."
    echo "alias saltgoat='/usr/local/bin/saltgoat'" >> ~/.bashrc
    
    log_success "SaltGoat 系统安装完成！"
    log_info "现在可以使用 'saltgoat' 命令（无需 sudo 和 ./）"
    log_info "请重新登录或运行 'source ~/.bashrc' 来应用别名"
}

# 系统卸载
system_uninstall() {
    log_info "卸载 SaltGoat 系统安装..."
    
    # 删除系统级符号链接
    sudo rm -f /usr/local/bin/saltgoat
    
    # 删除 sudoers 配置
    sudo rm -f /etc/sudoers.d/saltgoat
    
    # 删除用户别名
    sed -i '/alias saltgoat=/d' ~/.bashrc
    
    log_success "SaltGoat 系统卸载完成"
}

# 检测 SSH 端口
detect_ssh_port() {
    log_info "正在检测当前 SSH 端口..."
    
    # 尝试多种方法检测 SSH 端口
    local ssh_port=""
    
    # 方法1: 使用 ss 命令
    if command_exists ss; then
        ssh_port=$(sudo ss -tlnp | grep sshd | awk '{print $4}' | cut -d: -f2 | head -1)
    fi
    
    # 方法2: 使用 netstat 命令
    if [[ -z "$ssh_port" ]] && command_exists netstat; then
        ssh_port=$(sudo netstat -tlnp 2>/dev/null | grep sshd | awk '{print $4}' | cut -d: -f2 | head -1)
    fi
    
    # 方法3: 检查 SSH 配置文件
    if [[ -z "$ssh_port" ]] && file_exists /etc/ssh/sshd_config; then
        ssh_port=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}' | head -1)
    fi
    
    # 默认端口
    if [[ -z "$ssh_port" ]]; then
        ssh_port="22"
        log_warning "无法检测 SSH 端口，使用默认端口 22"
    fi
    
    log_success "检测到 SSH 端口: $ssh_port"
    
    # 检查 UFW 状态
    if command_exists ufw; then
        local ufw_status=$(sudo ufw status | head -1)
        log_info "UFW 状态: $ufw_status"
        
        # 检查端口是否已允许
        if sudo ufw status | grep -q "$ssh_port"; then
            log_success "端口 $ssh_port 已在 UFW 中允许"
        else
            log_warning "端口 $ssh_port 未在 UFW 中允许"
            log_info "建议运行: sudo ufw allow $ssh_port"
        fi
    else
        log_warning "UFW 未安装"
    fi
    
    return 0
}
