# Percona MySQL 8.4 安装和配置


# 预置：让本地 salt 能读取项目 pillar，并启用 mysql 执行模块

configure_pillar_roots:
  file.managed:
    - name: /etc/salt/minion.d/saltgoat-pillar.conf
    - makedirs: True
    - contents: |
        pillar_roots:
          base:
            - {{ grains['saltgoat_project_dir'] }}/salt/pillar

install_mysql_python_lib:
  pkg.installed:
    - name: python3-pymysql

configure_mysql_module:
  file.managed:
    - name: /etc/salt/minion.d/mysql.conf
    - makedirs: True
    - contents: |
        mysql:
          user: root
          unix_socket: /var/run/mysqld/mysqld.sock
    - require:
      - pkg: install_mysql_python_lib

refresh_modules:
  module.run:
    - name: saltutil.sync_modules
    - require:
      - file: configure_mysql_module

# 添加 Percona 仓库
add_percona_repository:
  cmd.run:
    - name: |
        wget https://repo.percona.com/apt/percona-release_latest.$(lsb_release -sc)_all.deb
        sudo dpkg -i percona-release_latest.$(lsb_release -sc)_all.deb
        sudo apt update
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

{# 从 Pillar 读取 root 密码，默认回退 #}
{% set root_pass = pillar.get('mysql_password', 'SaltGoat2024!') %}

# 设置 MySQL Root 密码（使用 Salt 原生 mysql 模块）
set_mysql_root_password:
  module.run:
    - name: mysql.query
    - database: mysql
    - query: |
        ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '{{ root_pass }}';
        FLUSH PRIVILEGES;
    - require:
      - cmd: wait_for_mysql
      - module: refresh_modules

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
