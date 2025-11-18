# Fail2ban 安装和配置

# 确保 Fail2ban 已安装
fail2ban_package:
  pkg.installed:
    - name: fail2ban

# 确保配置目录存在
fail2ban_directories:
  file.directory:
    - names:
        - /etc/fail2ban/jail.d
        - /etc/fail2ban/filter.d
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
        - pkg: fail2ban_package

# 创建 LEMP 特定的 jail 配置
configure_fail2ban_lemp:
  file.managed:
    - name: /etc/fail2ban/jail.d/lemp.conf
    - contents: |
        [nginx-http-auth]
        enabled = true
        filter = nginx-http-auth
        port = http,https
        logpath = /var/log/nginx/error.log
        maxretry = 3
        bantime = 3600
        findtime = 600

        [nginx-limit-req]
        enabled = true
        filter = nginx-limit-req
        port = http,https
        logpath = /var/log/nginx/error.log
        maxretry = 10
        bantime = 3600
        findtime = 600

        [php-fpm]
        enabled = true
        filter = php-fpm
        port = http,https
        logpath = /var/log/php8.3-fpm.log
        maxretry = 3
        bantime = 3600
        findtime = 600

        [mysql]
        enabled = true
        filter = mysql
        port = 3306
        logpath = /var/log/mysql/error.log
        maxretry = 3
        bantime = 3600
        findtime = 600
    - require:
        - file: fail2ban_directories

# 创建自定义过滤器
create_fail2ban_filters:
  file.managed:
    - name: /etc/fail2ban/filter.d/nginx-limit-req.conf
    - contents: |
        [Definition]
        failregex = limiting requests, excess: .* by zone .*, client: <HOST>
        ignoreregex =
    - require:
        - file: fail2ban_directories

# 重启 Fail2ban 服务
restart_fail2ban:
  service.running:
    - name: fail2ban
    - enable: true
    - reload: true
    - require:
      - pkg: fail2ban_package
      - file: configure_fail2ban_lemp
      - file: create_fail2ban_filters

# 检查 Fail2ban 状态
check_fail2ban_status:
  cmd.run:
    - name: fail2ban-client status
    - require:
      - service: restart_fail2ban
