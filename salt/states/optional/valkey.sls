{% set valkey_version = salt['pillar.get']('saltgoat:versions:valkey', '8.0.5') %}
{% set valkey_tar = '{}.tar.gz'.format(valkey_version) %}
# Valkey {{ valkey_version }} 安装和配置

# 安装编译依赖
install_build_dependencies:
  pkg.installed:
    - names:
      - build-essential
      - git
      - wget
      - curl
      - pkg-config
      - libssl-dev
      - libhiredis-dev
      - libjemalloc-dev

# 下载 Valkey 源码
download_valkey_source:
  cmd.run:
    - name: |
        cd /tmp
        wget https://github.com/valkey-io/valkey/archive/refs/tags/{{ valkey_version }}.tar.gz -O {{ valkey_tar }}
        tar -xzf {{ valkey_tar }}
        mv valkey-{{ valkey_version }} valkey
    - cwd: /tmp
    - unless: test -d /tmp/valkey

# 编译安装 Valkey
compile_valkey:
  cmd.run:
    - name: |
        cd /tmp/valkey
        make -j$(nproc)
        make install
    - require:
      - pkg: install_build_dependencies
      - cmd: download_valkey_source
    - unless: command -v valkey-server &> /dev/null

# 创建 valkey 用户
create_valkey_user:
  user.present:
    - name: valkey
    - system: true
    - shell: /bin/false
    - home: /var/lib/valkey
    - require:
      - cmd: compile_valkey

# 创建 Valkey 配置目录
create_valkey_dirs:
  file.directory:
    - names:
      - /etc/valkey
      - /var/lib/valkey
      - /var/log/valkey
      - /var/run/valkey
    - user: valkey
    - group: valkey
    - mode: 755
    - makedirs: true
    - require:
      - user: create_valkey_user

{# 从 Pillar 读取 Valkey 密码，默认回退 #}
{% set valkey_pass = pillar.get('valkey_password', 'SaltGoat2024!') %}

# 配置 Valkey（可选，使用命令行参数）
configure_valkey:
  file.managed:
    - name: /etc/valkey/valkey.conf
    - contents: |
        # Valkey {{ valkey_version }} 基本配置
        # 主要配置通过命令行参数设置
        bind 127.0.0.1
        port 6379
        daemonize no
        supervised systemd
        pidfile /var/run/valkey/valkey.pid
        loglevel notice
        logfile /var/log/valkey/valkey.log
        databases 100
        save 900 1
        save 300 10
        save 60 10000
        stop-writes-on-bgsave-error yes
        rdbcompression yes
        rdbchecksum yes
        dbfilename dump.rdb
        dir /var/lib/valkey
        requirepass {{ valkey_pass }}
        maxmemory 256mb
        maxmemory-policy allkeys-lru
    - user: valkey
    - group: valkey
    - mode: 644
    - require:
      - file: create_valkey_dirs

# 创建 Valkey systemd 服务
create_valkey_service:
  file.managed:
    - name: /etc/systemd/system/valkey.service
    - contents: |
        [Unit]
        Description=Valkey In-Memory Data Store
        After=network.target

        [Service]
        Type=simple
        ExecStart=/usr/local/bin/valkey-server --port 6379 --requirepass {{ valkey_pass }} --databases 100 --daemonize no --pidfile /var/run/valkey/valkey.pid --logfile /var/log/valkey/valkey.log --dir /var/lib/valkey --maxmemory 256mb --maxmemory-policy allkeys-lru
        ExecStop=/usr/local/bin/valkey-cli -a {{ valkey_pass }} shutdown
        TimeoutStopSec=0
        User=valkey
        Group=valkey
        RuntimeDirectory=valkey
        RuntimeDirectoryMode=0755
        UMask=007
        PrivateTmp=yes
        LimitNOFILE=65535
        PrivateDevices=yes
        ProtectHome=yes
        ReadOnlyDirectories=/
        ReadWriteDirectories=-/var/lib/valkey
        ReadWriteDirectories=-/var/log/valkey
        ReadWriteDirectories=-/var/run/valkey
        ReadWriteDirectories=-/tmp

        [Install]
        WantedBy=multi-user.target
    - require:
      - file: create_valkey_dirs

# 重新加载 systemd
reload_systemd:
  cmd.run:
    - name: systemctl daemon-reload
    - require:
      - file: create_valkey_service

# 启动 Valkey 服务
start_valkey:
  service.running:
    - name: valkey
    - enable: true
    - require:
      - cmd: reload_systemd

# 配置防火墙
configure_valkey_firewall:
  cmd.run:
    - name: ufw allow 6379
    - require:
      - service: start_valkey

# 测试 Valkey 连接
test_valkey_connection:
  cmd.run:
    - name: |
        valkey-cli -a {{ valkey_pass }} ping
    - require:
      - service: start_valkey
