# Percona MySQL 8.4 安装和配置


# 添加 Percona 仓库
add_percona_repository:
  cmd.run:
    - name: |
        wget https://repo.percona.com/apt/percona-release_latest.$(lsb_release -sc)_all.deb
        dpkg -i percona-release_latest.$(lsb_release -sc)_all.deb
        apt update
    - unless: test -f /etc/apt/sources.list.d/percona-original-release.list

# 安装 Percona MySQL 8.4
install_percona_mysql:
  pkg.installed:
    - name: percona-server-server
    - require:
      - cmd: add_percona_repository

# 安装 MySQL 客户端
install_mysql_client:
  pkg.installed:
    - name: percona-server-client
    - require:
      - pkg: install_percona_mysql

# 启动 MySQL 服务
start_mysql:
  service.running:
    - name: mysql
    - enable: true
    - require:
      - pkg: install_percona_mysql

# 等待 MySQL 启动
wait_for_mysql:
  cmd.run:
    - name: sleep 10
    - require:
      - service: start_mysql

# 设置 MySQL Root 密码
set_mysql_root_password:
  cmd.run:
    - name: |
        mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'SaltGoat2024!';"
        mysql -e "FLUSH PRIVILEGES;"
    - require:
      - cmd: wait_for_mysql

# 配置 MySQL
configure_mysql:
  file.managed:
    - name: /etc/mysql/mysql.conf.d/lemp.cnf
    - source: salt://core/mysql.cnf
    - require:
      - pkg: install_percona_mysql

# 重启 MySQL 服务
restart_mysql:
  service.running:
    - name: mysql
    - enable: true
    - reload: true
    - require:
      - file: configure_mysql

# 创建防火墙规则
configure_mysql_firewall:
  cmd.run:
    - name: ufw allow 3306
    - require:
      - service: restart_mysql
