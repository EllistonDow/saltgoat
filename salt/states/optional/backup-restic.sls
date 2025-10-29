# Restic 备份（可选模块）

{% set restic_cfg = pillar.get('backup', {}).get('restic', {}) %}

{% if not restic_cfg %}
backup_restic_missing_config:
  test.succeed_without_changes:
    - comment: "找不到 pillar['backup']['restic'] 配置，Restic 备份模块保持禁用状态。"
{% else %}
{% if not restic_cfg.get('enabled', True) %}
backup_restic_disabled:
  test.succeed_without_changes:
    - comment: "Restic 备份在 Pillar 中被禁用。"
{% else %}

{% set repo = restic_cfg.get('repo') %}
{% set password = restic_cfg.get('password') %}
{% set paths = restic_cfg.get('paths', []) %}
{% set excludes = restic_cfg.get('excludes', []) %}
{% set config_dir = restic_cfg.get('config_dir', '/etc/restic') %}
{% set cache_dir = restic_cfg.get('cache_dir', '/var/cache/restic') %}
{% set log_dir = restic_cfg.get('log_dir', '/var/log/restic') %}
{% set script_path = restic_cfg.get('script_path', '/usr/local/bin/saltgoat-restic-backup') %}
{% set env_file = restic_cfg.get('env_file', config_dir ~ '/restic.env') %}
{% set include_file = restic_cfg.get('include_file', config_dir ~ '/include.txt') %}
{% set exclude_file = restic_cfg.get('exclude_file', config_dir ~ '/exclude.txt') %}
{% set binary = restic_cfg.get('binary', '/usr/bin/restic') %}
{% set service_user = restic_cfg.get('service_user', 'root') %}
{% set repo_owner = restic_cfg.get('repo_owner', service_user) %}
{% set timer_calendar = restic_cfg.get('timer', 'daily') %}
{% set timer_random_delay = restic_cfg.get('randomized_delay', '10m') %}
{% set tags = restic_cfg.get('tags', []) %}
{% set extra_backup_args = restic_cfg.get('extra_backup_args', '') %}
{% set check_after_backup = restic_cfg.get('check_after_backup', False) %}
{% set retention = restic_cfg.get('retention', {}) %}
{% set repo_dir = repo if repo and repo.startswith('/') else None %}
{% set protect_home = 'yes' if not (repo_dir and repo_dir.startswith('/home/')) else 'no' %}

{% if not repo or not password %}
backup_restic_missing_repo_or_password:
  test.succeed_without_changes:
    - comment: "Restic 备份缺少 repo 或 password，跳过部署。"
{% elif not paths %}
backup_restic_missing_paths:
  test.succeed_without_changes:
    - comment: "Restic 备份未配置 paths，跳过部署。"
{% else %}

{% set aws_access_key = restic_cfg.get('aws_access_key_id') %}
{% set aws_secret_key = restic_cfg.get('aws_secret_access_key') %}
{% set aws_region = restic_cfg.get('aws_region') %}
{% set extra_env = restic_cfg.get('extra_env', {}) %}

{% set forget_args = [] %}
{% for key, flag in [('keep_last', '--keep-last'), ('keep_hourly', '--keep-hourly'), ('keep_daily', '--keep-daily'), ('keep_weekly', '--keep-weekly'), ('keep_monthly', '--keep-monthly'), ('keep_yearly', '--keep-yearly')] %}
  {% if retention.get(key) %}
    {% do forget_args.append(flag ~ ' ' ~ retention.get(key)) %}
  {% endif %}
{% endfor %}
{% if retention.get('prune', True) %}
  {% if forget_args %}
    {% do forget_args.append('--prune') %}
  {% endif %}
{% endif %}
{% set forget_args_str = ' '.join(forget_args) %}

restic_package:
  pkg.installed:
    - name: restic

restic_directories:
  file.directory:
    - names:
      - {{ config_dir }}
      - {{ cache_dir }}
      - {{ log_dir }}
    - mode: '0750'
    - user: {{ service_user }}
    - group: {{ service_user }}
    - require:
      - pkg: restic_package

restic_include_file:
  file.managed:
    - name: {{ include_file }}
    - mode: '0640'
    - user: {{ service_user }}
    - group: {{ service_user }}
    - contents: |
        {%- for path in paths %}
        {{ path }}
        {%- endfor %}
    - require:
      - file: restic_directories

restic_exclude_file:
  file.managed:
    - name: {{ exclude_file }}
    - mode: '0640'
    - user: {{ service_user }}
    - group: {{ service_user }}
    - contents: |
        {%- for pattern in excludes %}
        {{ pattern }}
        {%- endfor %}
    - require:
      - file: restic_directories

restic_env_file:
  file.managed:
    - name: {{ env_file }}
    - mode: '0600'
    - user: {{ service_user }}
    - group: {{ service_user }}
    - contents: |
        RESTIC_REPOSITORY="{{ repo }}"
        RESTIC_PASSWORD="{{ password }}"
        RESTIC_CACHE_DIR="{{ cache_dir }}"
        RESTIC_BIN="{{ binary }}"
        RESTIC_INCLUDE_FILE="{{ include_file }}"
        RESTIC_EXCLUDE_FILE="{{ exclude_file }}"
        RESTIC_LOG_DIR="{{ log_dir }}"
        RESTIC_TAGS="{{ tags|join(',') }}"
        RESTIC_BACKUP_ARGS="{{ extra_backup_args }}"
        RESTIC_CHECK_AFTER_BACKUP="{{ 1 if check_after_backup else 0 }}"
        RESTIC_FORGET_ARGS="{{ forget_args_str }}"
        RESTIC_REPO_OWNER="{{ repo_owner }}"
        {%- if aws_access_key %}
        AWS_ACCESS_KEY_ID="{{ aws_access_key }}"
        AWS_SECRET_ACCESS_KEY="{{ aws_secret_key }}"
        {%- endif %}
        {%- if aws_region %}
        AWS_DEFAULT_REGION="{{ aws_region }}"
        {%- endif %}
        {%- for key, value in extra_env.items() %}
        {{ key }}="{{ value }}"
        {%- endfor %}
    - require:
      - file: restic_directories

{{ script_path }}:
  file.managed:
    - mode: '0755'
    - user: root
    - group: root
    - source: salt://templates/restic-backup.sh.jinja
    - template: jinja
    - context:
        env_file: {{ env_file | tojson }}
        include_file: {{ include_file | tojson }}
        exclude_file: {{ exclude_file | tojson }}
        log_dir: {{ log_dir | tojson }}
    - require:
      - pkg: restic_package
      - file: restic_env_file

/etc/systemd/system/saltgoat-restic-backup.service:
  file.managed:
    - mode: '0644'
    - user: root
    - group: root
    - contents: |
        [Unit]
        Description=SaltGoat Restic Backup
        After=network-online.target

        [Service]
        Type=oneshot
        User={{ service_user }}
        Group={{ service_user }}
        EnvironmentFile={{ env_file }}
        ExecStart={{ script_path }}
        Nice=10
        IOSchedulingClass=2
        IOSchedulingPriority=7
        PrivateTmp=yes
        ProtectSystem=full
        ProtectHome={{ protect_home }}
        ReadWritePaths={{ log_dir }} {{ cache_dir }} {{ config_dir }}{% if repo_dir %} {{ repo_dir }}{% endif %}{% for path in paths %} {{ path }}{% endfor %}

        [Install]
        WantedBy=multi-user.target
    - require:
      - file: restic_env_file
      - file: {{ script_path }}

/etc/systemd/system/saltgoat-restic-backup.timer:
  file.managed:
    - mode: '0644'
    - user: root
    - group: root
    - contents: |
        [Unit]
        Description=SaltGoat Restic Backup Timer

        [Timer]
        OnCalendar={{ timer_calendar }}
        RandomizedDelaySec={{ timer_random_delay }}
        Persistent=true

        [Install]
        WantedBy=timers.target
    - require:
      - file: /etc/systemd/system/saltgoat-restic-backup.service

restic_systemd_reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /etc/systemd/system/saltgoat-restic-backup.service
      - file: /etc/systemd/system/saltgoat-restic-backup.timer

restic_timer_enabled:
  service.enabled:
    - name: saltgoat-restic-backup.timer
    - require:
      - cmd: restic_systemd_reload

restic_timer_running:
  service.running:
    - name: saltgoat-restic-backup.timer
    - enable: True
    - require:
      - service: restic_timer_enabled

{% endif %}
{% endif %}
{% endif %}
