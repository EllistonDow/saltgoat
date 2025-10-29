#!/bin/bash
# 系统管理模块
# core/system.sh

# 重新加载环境变量
reload_environment() {
    log_info "重新加载邮件相关配置（来自 Pillar）..."

    local default_account profile smtp_host smtp_port smtp_user smtp_password smtp_from_email smtp_from_name
    default_account=$(get_local_pillar_value "email.default")
    profile=$(get_local_pillar_value "mail.postfix.profile")
    if [[ -z "$profile" ]]; then
        profile="$default_account"
    fi

    if [[ -z "$profile" ]]; then
        log_warning "未检测到 email.default 或 mail.postfix.profile，跳过 Postfix 更新"
        return 1
    fi

    smtp_host=$(get_local_pillar_value "email.accounts.${profile}.host")
    smtp_port=$(get_local_pillar_value "email.accounts.${profile}.port")
    smtp_user=$(get_local_pillar_value "email.accounts.${profile}.user")
    smtp_password=$(get_local_pillar_value "email.accounts.${profile}.password")
    smtp_from_email=$(get_local_pillar_value "email.accounts.${profile}.from_email")
    smtp_from_name=$(get_local_pillar_value "email.accounts.${profile}.from_name")

    log_info "当前激活的邮件账号: ${profile}"
    log_info "  host: ${smtp_host:-未设置}"
    log_info "  port: ${smtp_port:-未设置}"
    log_info "  user: ${smtp_user:-未设置}"
    log_info "  from_email: ${smtp_from_email:-未设置}"
    log_info "  from_name: ${smtp_from_name:-未设置}"

    if [[ -n "$smtp_host" && -n "$smtp_user" && -n "$smtp_password" ]]; then
        local relay_host myorigin_value
        if [[ -n "$smtp_port" ]]; then
            relay_host="[$smtp_host]:$smtp_port"
        else
            relay_host="[$smtp_host]"
        fi

        if [[ -n "$smtp_from_email" && "$smtp_from_email" == *"@"* ]]; then
            myorigin_value="${smtp_from_email##*@}"
        else
            myorigin_value="$smtp_from_email"
        fi

        log_info "更新 Postfix 配置..."


        if command_exists postconf; then
            sudo postconf -e "relayhost = $relay_host"
            if [[ -n "$myorigin_value" ]]; then
                sudo postconf -e "myorigin = $myorigin_value"
            fi
        else
            log_warning "postconf 命令不存在，可能未安装 Postfix，已跳过 relay 配置写入"
        fi

        if [[ -d /etc/postfix ]]; then
            sudo mkdir -p /etc/postfix
        fi

        sudo tee /etc/postfix/sasl_passwd > /dev/null <<EOF
$relay_host $smtp_user:$smtp_password
EOF
        if command_exists postmap; then
            sudo postmap /etc/postfix/sasl_passwd
        else
            log_warning "postmap 命令不存在，无法生成 sasl_passwd.db"
        fi
        sudo chmod 600 /etc/postfix/sasl_passwd

        local postfix_enabled
        postfix_enabled=$(get_local_pillar_value "mail.postfix.enabled")
        if [[ "$postfix_enabled" =~ ^([Tt]rue|1|[Yy]es|on)$ ]]; then
            if command_exists systemctl && systemctl list-unit-files | grep -q '^postfix\.service'; then
                sudo systemctl reload postfix
                log_success "Postfix 配置已更新并重新加载"
            else
                log_warning "检测到 mail.postfix.enabled=True 但系统未安装 postfix 服务"
            fi
        else
            log_warning "mail.postfix.enabled 为 False，仅更新了凭据文件，未重新加载 Postfix"
        fi
    else
        log_warning "Pillar 中未配置完整的 SMTP 信息（host/user/password），跳过 Postfix 更新"
    fi
}

# 系统安装
system_install() {
    # 获取 SaltGoat 安装路径（从主脚本目录）
    local saltgoat_path
    saltgoat_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
        local ufw_status
        ufw_status=$(sudo ufw status | head -1)
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
