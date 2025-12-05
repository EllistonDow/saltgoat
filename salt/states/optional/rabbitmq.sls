{# RabbitMQ manual install from upstream tarball to keep version 4.1.x #}
{# 默认 4.1.x，需要 Erlang/OTP 26+；如需 LTS 3.12，可在 pillar 中将 rabbitmq_version 调低。 #}
{% set rabbitmq_version = salt['pillar.get']('saltgoat:versions:rabbitmq', salt['pillar.get']('rabbitmq_version', '4.1.4')) %}
{% set rabbitmq_cookie = salt['pillar.get']('rabbitmq_cookie', 'RabbitCookie2024!') %}
{% set archive_name = 'rabbitmq-server-generic-unix-{}.tar.xz'.format(rabbitmq_version) %}
{% set archive_url = 'https://github.com/rabbitmq/rabbitmq-server/releases/download/v{}/{}'.format(rabbitmq_version, archive_name) %}
{% set install_dir = '/opt/rabbitmq_server-{}'.format(rabbitmq_version) %}
{% set current_link = '/opt/rabbitmq' %}

include:
  - core.otp

rabbitmq_version_guard:
  test.fail_without_changes:
    - name: RabbitMQ 版本 {{ rabbitmq_version }} 低于支持的最小版本 4.1.4
    - onlyif:
      - dpkg --compare-versions {{ rabbitmq_version }} lt 4.1.4

rabbitmq_user:
  user.present:
    - name: rabbitmq
    - system: true
    - shell: /bin/false
    - home: /var/lib/rabbitmq
    - createhome: true

rabbitmq_remove_old_link:
  file.absent:
    - name: {{ current_link }}

download_rabbitmq_archive:
  cmd.run:
    - name: curl -L {{ archive_url }} -o /tmp/{{ archive_name }}
    - creates: /tmp/{{ archive_name }}
    - require:
      - user: rabbitmq_user

extract_rabbitmq_archive:
  cmd.run:
    - name: tar -xf /tmp/{{ archive_name }} -C /opt
    - unless: test -d {{ install_dir }}
    - require:
      - cmd: download_rabbitmq_archive

rabbitmq_current_symlink:
  file.symlink:
    - name: {{ current_link }}
    - target: {{ install_dir }}
    - force: True
    - require:
      - cmd: extract_rabbitmq_archive

rabbitmq_cli_symlink_server:
  file.symlink:
    - name: /usr/local/bin/rabbitmq-server
    - target: {{ current_link }}/sbin/rabbitmq-server
    - force: True
    - require:
      - file: rabbitmq_current_symlink

rabbitmq_cli_symlink_ctl:
  file.symlink:
    - name: /usr/local/bin/rabbitmqctl
    - target: {{ current_link }}/sbin/rabbitmqctl
    - force: True
    - require:
      - file: rabbitmq_current_symlink

rabbitmq_cli_symlink_plugins:
  file.symlink:
    - name: /usr/local/bin/rabbitmq-plugins
    - target: {{ current_link }}/sbin/rabbitmq-plugins
    - force: True
    - require:
      - file: rabbitmq_current_symlink

rabbitmq_cli_symlink_diag:
  file.symlink:
    - name: /usr/local/bin/rabbitmq-diagnostics
    - target: {{ current_link }}/sbin/rabbitmq-diagnostics
    - force: True
    - require:
      - file: rabbitmq_current_symlink

rabbitmq_cli_symlink_env:
  file.symlink:
    - name: /usr/local/bin/rabbitmq-env
    - target: {{ current_link }}/sbin/rabbitmq-env
    - force: True
    - require:
      - file: rabbitmq_current_symlink

rabbitmq_config_dirs:
  file.directory:
    - names:
        - /etc/rabbitmq
        - /var/lib/rabbitmq
        - /var/log/rabbitmq
        - {{ current_link }}/var/lib/rabbitmq/mnesia
        - {{ current_link }}/var/log/rabbitmq
    - follow_symlinks: True
    - user: rabbitmq
    - group: rabbitmq
    - mode: 750
    - makedirs: True
    - require:
      - file: rabbitmq_current_symlink

rabbitmq_env_conf:
  file.managed:
    - name: {{ current_link }}/etc/rabbitmq/rabbitmq-env.conf
    - source: salt://optional/files/rabbitmq-env.conf
    - template: jinja
    - context:
        version: {{ rabbitmq_version }}
    - require:
      - file: rabbitmq_config_dirs

rabbitmq_node_cookie:
  file.managed:
    - name: /var/lib/rabbitmq/.erlang.cookie
    - contents: {{ rabbitmq_cookie }}
    - user: rabbitmq
    - group: rabbitmq
    - mode: 400
    - makedirs: True
    - require:
      - file: rabbitmq_config_dirs

rabbitmq_root_cookie:
  file.managed:
    - name: /root/.erlang.cookie
    - contents: {{ rabbitmq_cookie }}
    - user: root
    - group: root
    - mode: 400
    - require:
      - file: rabbitmq_node_cookie

rabbitmq_service_unit:
  file.managed:
    - name: /etc/systemd/system/rabbitmq.service
    - source: salt://optional/rabbitmq.service
    - require:
      - file: rabbitmq_env_conf

rabbitmq_daemon_reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: rabbitmq_service_unit

start_rabbitmq_service:
  service.running:
    - name: rabbitmq
    - enable: true
    - require:
      - cmd: rabbitmq_daemon_reload
      - file: rabbitmq_root_cookie

wait_for_rabbitmq:
  cmd.run:
    - name: sleep 10
    - require:
      - service: start_rabbitmq_service

enable_rabbitmq_management:
  cmd.run:
    - name: rabbitmq-plugins enable rabbitmq_management
    - require:
      - cmd: wait_for_rabbitmq

{% set rabbitmq_pass = salt['pillar.get']('auth:rabbitmq:password', pillar.get('rabbitmq_password', 'SaltGoat2024!')) %}

create_rabbitmq_admin:
  cmd.run:
    - name: |
        rabbitmqctl add_user admin {{ rabbitmq_pass }}
        rabbitmqctl set_user_tags admin administrator
        rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"
    - unless: rabbitmqctl list_users | grep -q '^admin\b'
    - require:
      - cmd: enable_rabbitmq_management

restart_rabbitmq_service:
  service.running:
    - name: rabbitmq
    - enable: true
    - reload: true
    - require:
      - cmd: create_rabbitmq_admin

configure_rabbitmq_firewall:
  cmd.run:
    - name: |
        ufw allow 5672
        ufw allow 15672
    - require:
      - service: restart_rabbitmq_service

test_rabbitmq_connection:
  cmd.run:
    - name: rabbitmqctl status
    - require:
      - service: restart_rabbitmq_service
