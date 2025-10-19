# Fail2ban 安装和配置
# Fail2ban 已经在 common/security.sls 中安装，这里只做额外配置

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

# 创建自定义过滤器
create_fail2ban_filters:
  file.managed:
    - name: /etc/fail2ban/filter.d/nginx-limit-req.conf
    - contents: |
        [Definition]
        failregex = limiting requests, excess: .* by zone .*, client: <HOST>
        ignoreregex =

# 重启 Fail2ban 服务
restart_fail2ban:
  service.running:
    - name: fail2ban
    - enable: true
    - reload: true
    - require:
      - file: configure_fail2ban_lemp
      - file: create_fail2ban_filters

# 检查 Fail2ban 状态
check_fail2ban_status:
  cmd.run:
    - name: fail2ban-client status
    - require:
      - service: restart_fail2ban
