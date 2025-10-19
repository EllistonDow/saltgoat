# 基础包管理

# 安装基础开发包
install_development_packages:
  pkg.installed:
    - names:
      - build-essential
      - python3-dev
      - python3-pip
      - libssl-dev
      - libffi-dev
      - libxml2-dev
      - libxslt1-dev
      - zlib1g-dev
      - libjpeg-dev
      - libpng-dev
      - libfreetype-dev
      - libmcrypt-dev
      - libreadline-dev
      - libzip-dev

# 安装防火墙
install_ufw:
  pkg.installed:
    - name: ufw

# 检测当前 SSH 端口
detect_ssh_port:
  cmd.run:
    - name: |
        # 检测当前 SSH 端口
        SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | cut -d: -f2 | head -1)
        if [ -z "$SSH_PORT" ]; then
          SSH_PORT=$(netstat -tlnp 2>/dev/null | grep sshd | awk '{print $4}' | cut -d: -f2 | head -1)
        fi
        if [ -z "$SSH_PORT" ]; then
          SSH_PORT=22
        fi
        echo "SSH_PORT=$SSH_PORT" > /tmp/ssh_port
        echo "检测到 SSH 端口: $SSH_PORT"
    - require:
      - pkg: install_ufw

# 配置防火墙
configure_firewall:
  cmd.run:
    - name: |
        # 读取检测到的 SSH 端口
        source /tmp/ssh_port
        echo "配置防火墙，SSH 端口: $SSH_PORT"
        
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing
        
        # 添加 SSH 端口（如果不在默认列表中）
        if [ "$SSH_PORT" != "22" ]; then
          echo "添加自定义 SSH 端口: $SSH_PORT"
          ufw allow $SSH_PORT
        fi
        
        # 添加默认端口
        ufw allow 22
        ufw allow 80
        ufw allow 443
        ufw allow 3306
        ufw allow 6379
        ufw allow 5672
        ufw allow 15672
        ufw allow 10000
        
        # 启用防火墙
        ufw --force enable
        
        echo "防火墙配置完成，SSH 端口 $SSH_PORT 已允许"
    - require:
      - cmd: detect_ssh_port

# 安装日志轮转
install_logrotate:
  pkg.installed:
    - name: logrotate

# 配置系统日志（使用默认配置）
configure_system_logging:
  cmd.run:
    - name: echo "# LEMP stack logrotate configuration" > /etc/logrotate.d/lemp
    - require:
      - pkg: install_logrotate
