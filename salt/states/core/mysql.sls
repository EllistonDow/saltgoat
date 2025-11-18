# Percona MySQL 8.4 安装和配置


# 预置变量
{% set root_pass = pillar.get('mysql_password', 'SaltGoat2024!') %}

# 清理旧的 Percona 8.0 仓库
remove_percona_ps80_repo:
  file.absent:
    - name: /etc/apt/sources.list.d/percona-ps-80-release.list

# 添加/启用 Percona Server 8.4 LTS 与 XtraBackup 8.4 仓库
add_percona_repository:
  cmd.run:
    - name: |
        wget -q https://repo.percona.com/apt/percona-release_latest.generic_all.deb -O /tmp/percona-release.deb
        sudo dpkg -i /tmp/percona-release.deb
        sudo percona-release enable-only ps-84-lts release
        sudo percona-release enable pxb-84-lts release
        sudo percona-release enable tools release
        sudo apt update
    - unless: test -f /etc/apt/sources.list.d/percona-ps-84-lts-release.list && test -f /etc/apt/sources.list.d/percona-pxb-84-lts-release.list

# 设置默认固定版本（可通过 pillar 覆盖）
{% set percona_server_version = salt['pillar.get']('saltgoat:versions:percona_server', salt['pillar.get']('percona_server_version', '8.4.6-6-1.noble')) %}
{% set xtrabackup_version = salt['pillar.get']('saltgoat:versions:xtrabackup', salt['pillar.get']('xtrabackup_version', '8.4.0-4-1.noble')) %}

# 安装 Percona MySQL 8.4（锁定版本）
install_percona_mysql:
  pkg.installed:
    - name: percona-server-server
    - version: {{ percona_server_version }}
    - require:
      - cmd: add_percona_repository
      - file: remove_percona_ps80_repo

# 安装 MySQL 客户端（锁定同版本）
install_mysql_client:
  pkg.installed:
    - name: percona-server-client
    - version: {{ percona_server_version }}
    - require:
      - pkg: install_percona_mysql

# 安装 XtraBackup 8.4（锁定版本）
install_xtrabackup:
  pkg.installed:
    - name: percona-xtrabackup-84
    - version: {{ xtrabackup_version }}
    - require:
      - cmd: add_percona_repository

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

# 配置 root MySQL 客户端凭证
mysql_root_client_config:
  file.managed:
    - name: /root/.my.cnf
    - user: root
    - group: root
    - mode: 600
    - contents: |
        [client]
        user=root
        password={{ root_pass }}
        socket=/var/run/mysqld/mysqld.sock

# 设置 MySQL Root 密码（通过 mysql CLI 执行，确保 idempotent）
set_mysql_root_password:
  cmd.run:
    - name: |
        mysql --protocol=socket --socket=/var/run/mysqld/mysqld.sock -uroot <<'SQL'
        ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '{{ root_pass }}';
        FLUSH PRIVILEGES;
        SQL
    - unless: |
        mysql --defaults-extra-file=/root/.my.cnf -NBe "SELECT plugin FROM mysql.user WHERE user='root' AND host='localhost';" | grep -q caching_sha2_password
    - require:
      - cmd: wait_for_mysql
      - file: mysql_root_client_config

# 配置 MySQL 环境变量
configure_mysql_defaults:
  file.managed:
    - name: /etc/default/mysql
    - contents: |
        # defaults file for percona server
        STARTTIMEOUT=120
        STOPTIMEOUT=600
        
        # MySQL daemon options
        MYSQLD_OPTS="--defaults-file=/etc/mysql/my.cnf"
    - require:
      - pkg: install_percona_mysql

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
      - file: configure_mysql_defaults

# 创建防火墙规则
configure_mysql_firewall:
  cmd.run:
    - name: sudo ufw allow 3306
    - require:
      - service: restart_mysql
