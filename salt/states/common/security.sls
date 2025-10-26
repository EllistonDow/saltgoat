# 安全配置


# 安装 fail2ban
install_fail2ban:
  pkg.installed:
    - name: fail2ban

# 配置 fail2ban
configure_fail2ban:
  file.managed:
    - name: /etc/fail2ban/jail.local
    - contents: |
        [DEFAULT]
        bantime = 3600
        findtime = 600
        maxretry = 3
        
        [sshd]
        enabled = true
        port = ssh
        filter = sshd
        logpath = /var/log/auth.log
        maxretry = 3
    - require:
      - pkg: install_fail2ban

# 启动 fail2ban 服务
start_fail2ban:
  service.running:
    - name: fail2ban
    - enable: true
    - require:
      - file: configure_fail2ban

# 配置 SSH 安全
configure_ssh_security:
  file.managed:
    - name: /etc/ssh/sshd_config.d/lemp.conf
    - contents: |
        Port 22
        PermitRootLogin no
        PasswordAuthentication no
        PubkeyAuthentication yes
        X11Forwarding no
        UsePAM yes
        ClientAliveInterval 300
        ClientAliveCountMax 2
    - require:
      - pkg: install_fail2ban

# 重启 SSH 服务
restart_ssh:
  service.running:
    - name: ssh
    - enable: true
    - reload: true
    - require:
      - file: configure_ssh_security

# 安装 ModSecurity 依赖（由 core.nginx 根据 Pillar 决定是否启用）
install_modsecurity:
  pkg.installed:
    - names:
      - libmodsecurity3t64
      - libapache2-mod-security2
      - modsecurity-crs
