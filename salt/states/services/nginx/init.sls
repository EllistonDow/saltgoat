{# Nginx 安装与站点管理（Salt 原生） #}
{% from "services/nginx/map.jinja" import settings with context %}
{% set settings_serialized = salt['slsutil.serialize']('json', settings) %}

nginx_pkg:
  pkg.installed:
    - name: {{ settings.package }}

nginx_directories:
  file.directory:
    - names:
      - {{ settings.config_dir }}
      - {{ settings.conf_d_dir }}
      - {{ settings.sites_available_dir }}
      - {{ settings.sites_enabled_dir }}
      - {{ settings.log_dir }}
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - pkg: nginx_pkg

nginx_log_permissions:
  file.directory:
    - name: {{ settings.log_dir }}
    - user: {{ settings.user }}
    - group: {{ settings.group }}
    - mode: 750
    - require:
      - file: nginx_directories

nginx_systemd_unit_cleanup:
  file.absent:
    - name: /etc/systemd/system/nginx.service
    - onlyif: test -f /etc/systemd/system/nginx.service

nginx_daemon_reload:
  cmd.wait:
    - name: systemctl daemon-reload
    - watch:
      - file: nginx_systemd_unit_cleanup

disable_apache2_service:
  service.dead:
    - name: apache2
    - enable: False
    - onlyif: systemctl list-unit-files | grep -q '^apache2\.service'
    - failhard: False

nginx_main_config:
  file.managed:
    - name: {{ settings.config_dir }}/nginx.conf
    - source: salt://services/nginx/files/nginx.conf.jinja
    - template: jinja
    - context:
        settings: {{ settings_serialized }}
    - user: root
    - group: root
    - mode: 644
    - require:
      - file: nginx_directories
    - watch_in:
      - cmd: nginx_configtest

{% for name, site in settings.sites.items() %}
{% set site_serialized = salt['slsutil.serialize']('json', site) %}
{{ name }}_root_dir:
  file.directory:
    - name: {{ site.get('root', settings.default_site_root) }}
    - user: {{ site.get('user', settings.user) }}
    - group: {{ site.get('group', settings.group) }}
    - mode: {{ site.get('mode', '0755') }}
    - makedirs: True
    - require:
      - pkg: nginx_pkg

{{ name }}_config:
  file.managed:
    - name: {{ settings.sites_available_dir }}/{{ name }}
    - source: salt://services/nginx/files/site.conf.jinja
    - template: jinja
    - context:
        site_name: '{{ name }}'
        site: {{ site_serialized }}
        settings: {{ settings_serialized }}
    - user: root
    - group: root
    - mode: 644
    - require:
      - file: nginx_directories
    - watch_in:
      - cmd: nginx_configtest

{% if site.get('enabled', True) %}
{{ name }}_enabled:
  file.symlink:
    - name: {{ settings.sites_enabled_dir }}/{{ name }}
    - target: {{ settings.sites_available_dir }}/{{ name }}
    - require:
      - file: {{ name }}_config
    - watch_in:
      - cmd: nginx_configtest
{% else %}
{{ name }}_disabled:
  file.absent:
    - name: {{ settings.sites_enabled_dir }}/{{ name }}
    - watch_in:
      - cmd: nginx_configtest
{% endif %}
{% endfor %}

nginx_configtest:
  cmd.wait:
    - name: {{ settings.binary }} -t -c {{ settings.config_dir }}/nginx.conf
    - require:
      - pkg: nginx_pkg
      - file: nginx_main_config

nginx_service:
  service.running:
    - name: {{ settings.service }}
    - enable: True
    - require:
      - pkg: nginx_pkg
      - cmd: nginx_daemon_reload
      - service: disable_apache2_service
    - watch:
      - cmd: nginx_configtest
