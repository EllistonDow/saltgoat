# Percona XtraBackup automation

{% set cfg = pillar.get('mysql_backup', {}) %}

{% if not cfg %}
mysql_backup_missing_cfg:
  test.succeed_without_changes:
    - comment: "未找到 pillar['mysql_backup'] 配置，MySQL 备份模块保持禁用状态。"
{% elif not cfg.get('enabled', True) %}
mysql_backup_disabled:
  test.succeed_without_changes:
    - comment: "MySQL 备份在 Pillar 中被禁用。"
{% else %}

{% set backup_dir = cfg.get('backup_dir', '/var/backups/mysql/xtrabackup') %}
{% set mysql_user = cfg.get('mysql_user', 'backup') %}
{% set mysql_password = cfg.get('mysql_password') %}
{% set mysql_host = cfg.get('mysql_host', 'localhost') %}
{% set mysql_port = cfg.get('mysql_port', 3306) %}
{% set extra_args = cfg.get('extra_args', '') %}
{% set retention_days = cfg.get('retention_days', 7) %}
{% set prepare_backup = cfg.get('prepare_backup', False) %}
{% set compress = cfg.get('compress', False) %}
{% set service_user = cfg.get('service_user', 'root') %}
{% set repo_owner_explicit = cfg.get('repo_owner') %}
{% if repo_owner_explicit %}
  {% set repo_owner = repo_owner_explicit %}
{% else %}
  {% set repo_owner = service_user %}
{% endif %}
{% if repo_owner == service_user and backup_dir.startswith('/home/') %}
  {% set path_parts = backup_dir.split('/') %}
  {% if path_parts|length > 2 %}
    {% set home_owner = path_parts[2] %}
    {% if home_owner %}
      {% set repo_owner = home_owner %}
    {% endif %}
  {% endif %}
{% endif %}
{% set repo_owner_info = salt['user.info'](repo_owner) %}
{% if not repo_owner_info %}
  {% set repo_owner = service_user %}
{% endif %}
{% set timer_calendar = cfg.get('timer', 'daily') %}
{% set timer_delay = cfg.get('randomized_delay', '15m') %}
{% set mysql_socket = cfg.get('socket', '/var/run/mysqld/mysqld.sock') %}
{% set mysql_root_user = cfg.get('connection_user', 'root') %}
{% set mysql_root_password = cfg.get('connection_password', pillar.get('mysql_password', '')) %}
{% set metadata_dir = '/etc/mysql/backup.d' %}

{% if not mysql_password %}
mysql_backup_missing_password:
  test.fail_without_changes:
    - comment: "未提供 mysql_backup:mysql_password，无法创建备份账户。"
{% elif not mysql_root_password %}
mysql_backup_missing_root_password:
  test.fail_without_changes:
    - comment: "未提供 mysql_backup:connection_password 或 pillar['mysql_password']，无法连接 MySQL。"
{% else %}

mysql_backup_repo_pkg:
  pkg.installed:
    - name: percona-release

mysql_backup_repo:
  cmd.run:
    - name: percona-release enable pxb-84-lts release
    - unless: percona-release show | grep -q 'pxb-84-lts'
    - require:
      - pkg: mysql_backup_repo_pkg

mysql_backup_pkg:
  pkg.installed:
    - name: percona-xtrabackup-84
    - require:
      - cmd: mysql_backup_repo
      - pkg: mysql_backup_pkg_cleanup

mysql_backup_pkg_cleanup:
  pkg.purged:
    - name: percona-xtrabackup-80
    - require:
      - cmd: mysql_backup_repo

{{ backup_dir }}:
  file.directory:
    - user: {{ repo_owner }}
    - group: {{ repo_owner }}
    - mode: 750
    - makedirs: True
    - require:
      - pkg: mysql_backup_pkg

{{ metadata_dir }}:
  file.directory:
    - user: root
    - group: root
    - mode: 750
    - makedirs: True
    - require:
      - pkg: mysql_backup_pkg

/etc/mysql/mysql-backup.env:
  file.managed:
    - mode: 0600
    - user: root
    - group: root
    - require:
      - pkg: mysql_backup_pkg
    - contents: |
        MYSQL_BACKUP_DIR="{{ backup_dir }}"
        MYSQL_BACKUP_USER="{{ mysql_user }}"
        MYSQL_BACKUP_PASSWORD="{{ mysql_password | replace('"', '\"') }}"
        MYSQL_BACKUP_HOST="{{ mysql_host }}"
        MYSQL_BACKUP_PORT="{{ mysql_port }}"
        MYSQL_BACKUP_SOCKET="{{ mysql_socket }}"
        MYSQL_BACKUP_EXTRA_ARGS="{{ extra_args | replace('"', '\"') }}"
        MYSQL_BACKUP_RETENTION_DAYS="{{ retention_days }}"
        MYSQL_BACKUP_PREPARE="{{ 1 if prepare_backup else 0 }}"
        MYSQL_BACKUP_COMPRESS="{{ 1 if compress else 0 }}"
        MYSQL_BACKUP_REPO_OWNER="{{ repo_owner }}"
        MYSQL_BACKUP_SERVICE_USER="{{ service_user }}"

/usr/local/bin/saltgoat-mysql-backup:
  file.managed:
    - mode: 0750
    - user: {{ service_user }}
    - group: {{ service_user }}
    - require:
      - file: /etc/mysql/mysql-backup.env
    - source: salt://templates/mysql-backup.sh.jinja
    - template: jinja


/etc/systemd/system/saltgoat-mysql-backup.service:
  file.managed:
    - mode: 0644
    - user: root
    - group: root
    - contents: |
        [Unit]
        Description=SaltGoat MySQL Backup
        After=network-online.target mysql.service

        [Service]
        Type=oneshot
        User={{ service_user }}
        Group={{ service_user }}
        EnvironmentFile=/etc/mysql/mysql-backup.env
        ExecStart=/usr/local/bin/saltgoat-mysql-backup
        Nice=10
        IOSchedulingClass=2
        IOSchedulingPriority=7
        PrivateTmp=yes
        ProtectSystem=full
        ProtectHome=no
        ReadWritePaths={{ backup_dir }} /var/log

        [Install]
        WantedBy=multi-user.target
    - require:
      - file: /usr/local/bin/saltgoat-mysql-backup

/etc/systemd/system/saltgoat-mysql-backup.timer:
  file.managed:
    - mode: 0644
    - user: root
    - group: root
    - contents: |
        [Unit]
        Description=SaltGoat MySQL Backup Timer

        [Timer]
        OnCalendar={{ timer_calendar }}
        RandomizedDelaySec={{ timer_delay }}
        Persistent=true

        [Install]
        WantedBy=timers.target
    - require:
      - file: /etc/systemd/system/saltgoat-mysql-backup.service

mysql_backup_daemon_reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /etc/systemd/system/saltgoat-mysql-backup.service
      - file: /etc/systemd/system/saltgoat-mysql-backup.timer

saltgoat-mysql-backup.timer:
  service.running:
    - enable: True
    - require:
      - cmd: mysql_backup_daemon_reload

mysql_backup_metadata:
  file.managed:
    - name: {{ metadata_dir }}/mysql.env
    - mode: 0640
    - user: root
    - group: root
    - require:
      - file: {{ metadata_dir }}
    - contents: |
        SITE=mysql
        BACKUP_DIR={{ backup_dir }}
        ENV_FILE=/etc/mysql/mysql-backup.env
        SERVICE_NAME=saltgoat-mysql-backup.service
        TIMER_NAME=saltgoat-mysql-backup.timer
        UPDATED_AT={{ salt['cmd.run']('date -u +%Y-%m-%dT%H:%M:%SZ') }}

mysql_backup_user:
  cmd.run:
    - name: |
        MYSQL_PWD='{{ mysql_root_password }}' mysql -u{{ mysql_root_user }} -e "CREATE USER IF NOT EXISTS '{{ mysql_user }}'@'{{ mysql_host }}' IDENTIFIED BY '{{ mysql_password }}';"
    - unless: |
        MYSQL_PWD='{{ mysql_root_password }}' mysql -NBe "SELECT 1 FROM mysql.user WHERE user='{{ mysql_user }}' AND host='{{ mysql_host }}';" | grep -q 1
    - require:
      - pkg: mysql_backup_pkg

mysql_backup_grants:
  cmd.run:
    - name: |
        MYSQL_PWD='{{ mysql_root_password }}' mysql -u{{ mysql_root_user }} -e "GRANT SELECT, SHOW VIEW, EVENT, TRIGGER, RELOAD, PROCESS, LOCK TABLES, REPLICATION CLIENT, BACKUP_ADMIN ON *.* TO '{{ mysql_user }}'@'{{ mysql_host }}'; GRANT SELECT ON performance_schema.* TO '{{ mysql_user }}'@'{{ mysql_host }}'; FLUSH PRIVILEGES;"
    - unless: |
        MYSQL_PWD='{{ mysql_root_password }}' mysql -NBe "SHOW GRANTS FOR '{{ mysql_user }}'@'{{ mysql_host }}';" | grep -q 'SHOW VIEW'
    - require:
      - cmd: mysql_backup_user

{% endif %}
{% endif %}
