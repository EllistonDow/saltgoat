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

# 配置防火墙
configure_firewall:
  cmd.run:
    - name: |
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow 22
        ufw allow 80
        ufw allow 443
        ufw allow 3306
        ufw allow 6379
        ufw allow 5672
        ufw allow 15672
        ufw allow 10000
        ufw --force enable
    - require:
      - pkg: install_ufw

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
