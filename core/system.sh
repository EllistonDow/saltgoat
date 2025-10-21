#!/bin/bash
# 系统管理模块
# core/system.sh

# 重新加载环境变量
reload_environment() {
    log_info "重新加载环境变量..."
    
    # 检查 .env 文件是否存在
    if [[ ! -f ".env" ]]; then
        log_error ".env 文件不存在"
        log_info "请先复制 env.example 为 .env 并配置"
        return 1
    fi
    
    # 加载环境变量
    log_info "加载 .env 文件..."
    set -a  # 自动导出变量
    source .env
    set +a  # 停止自动导出
    
    # 显示当前邮件配置
    log_info "当前邮件配置:"
    log_info "  SMTP_HOST: ${SMTP_HOST:-未设置}"
    log_info "  SMTP_USER: ${SMTP_USER:-未设置}"
    log_info "  SMTP_FROM_EMAIL: ${SMTP_FROM_EMAIL:-未设置}"
    
    # 更新Postfix配置
    if [[ -n "$SMTP_HOST" ]] && [[ -n "$SMTP_USER" ]] && [[ -n "$SMTP_PASSWORD" ]]; then
        log_info "更新Postfix配置..."
        
        # 设置Postfix配置
        sudo postconf -e "relayhost = $SMTP_HOST"
        sudo postconf -e "myorigin = $SMTP_FROM_EMAIL"
        sudo postconf -e "myhostname = localhost"
        sudo postconf -e "mydomain = localhost"
        
        # 更新SASL密码文件
        sudo tee /etc/postfix/sasl_passwd > /dev/null <<EOF
[$SMTP_HOST] $SMTP_USER:$SMTP_PASSWORD
EOF
        
        # 生成密码数据库
        sudo postmap /etc/postfix/sasl_passwd
        sudo chmod 600 /etc/postfix/sasl_passwd
        
        # 重新加载Postfix
        sudo systemctl reload postfix
        
        log_success "Postfix配置已更新"
        log_info "现在可以使用: echo '测试邮件' | mail -s '测试' your-email@domain.com"
    else
        log_warning "邮件配置不完整，跳过Postfix更新"
    fi
}

# 系统安装
system_install() {
    # 获取 SaltGoat 安装路径（从主脚本目录）
    local saltgoat_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    log_info "SaltGoat 路径: $saltgoat_path"

    # 识别实际需要授权的用户（避免在 sudo 下写入 root）
    local install_user="$SUDO_USER"
    if [[ -z "$install_user" ]]; then
        install_user="$(logname 2>/dev/null || whoami)"
    fi
    log_info "授权用户: $install_user"

    # 创建系统级符号链接
    log_info "创建系统级符号链接..."
    sudo ln -sf "$saltgoat_path/saltgoat" /usr/local/bin/saltgoat
    sudo chmod +x /usr/local/bin/saltgoat

    # 确保 /usr/local/bin 在该用户 PATH 中
    if ! grep -q "/usr/local/bin" "/home/$install_user/.bashrc" 2>/dev/null; then
        echo "export PATH=\"/usr/local/bin:\$PATH\"" | sudo tee -a "/home/$install_user/.bashrc" >/dev/null
    fi

    # 配置 sudoers（幂等 & 语法校验）
    log_info "配置 sudoers..."
    local sudoers_tmp="/tmp/saltgoat_sudoers_$$"
    printf "Cmnd_Alias SALTGOAT_CMDS = /usr/local/bin/saltgoat\n%s ALL=(ALL) NOPASSWD: SALTGOAT_CMDS\n" "$install_user" > "$sudoers_tmp"
    if sudo visudo -cf "$sudoers_tmp" >/dev/null 2>&1; then
        echo "Sudoers 语法检查通过"
        # 仅当内容不存在时写入
        if ! sudo grep -q "SALTGOAT_CMDS" /etc/sudoers.d/saltgoat 2>/dev/null; then
            sudo install -m 440 -o root -g root "$sudoers_tmp" /etc/sudoers.d/saltgoat
        else
            # 覆盖到确保最新（仍保持 440 权限）
            sudo cp "$sudoers_tmp" /etc/sudoers.d/saltgoat
            sudo chmod 440 /etc/sudoers.d/saltgoat
        fi
    else
        log_error "sudoers 语法校验失败，未写入授权文件"
        rm -f "$sudoers_tmp"
        return 1
    fi
    rm -f "$sudoers_tmp"

    # 配置用户别名（避免重复添加）
    log_info "配置用户别名..."
    if ! grep -q "alias saltgoat='\/usr\/local\/bin\/saltgoat'" "/home/$install_user/.bashrc" 2>/dev/null; then
        echo "alias saltgoat='/usr/local/bin/saltgoat'" | sudo tee -a "/home/$install_user/.bashrc" >/dev/null
    fi

    log_success "SaltGoat 系统安装完成！"
    log_info "现在可以使用 'saltgoat' 命令（无需 sudo 和 ./）"
    log_info "请重新登录或执行 'source /home/$install_user/.bashrc' 应用环境"
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
