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
      - {{ settings.modules_enabled_dir }}
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

{% if not settings.get('default_site', True) %}
nginx_default_site_cleanup_enabled:
  file.absent:
    - name: {{ settings.sites_enabled_dir }}/default
    - watch_in:
      - cmd: nginx_configtest

nginx_default_site_cleanup_available:
  file.absent:
    - name: {{ settings.sites_available_dir }}/default
    - watch_in:
      - cmd: nginx_configtest

nginx_default_conf_cleanup:
  file.absent:
    - name: {{ settings.conf_d_dir }}/default.conf
    - watch_in:
      - cmd: nginx_configtest
{% endif %}

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

{% set magento_sites = [] %}
{% for name, site in settings.sites.items() %}
{% set site_serialized = salt['slsutil.serialize']('json', site) %}
{% if site.get('magento') %}
{% set _ = magento_sites.append(name) %}
{% endif %}
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

{% if magento_sites %}
nginx_magento_fastcgi_upstream:
  file.managed:
    - name: {{ settings.conf_d_dir }}/fastcgi_backend.conf
    - user: root
    - group: root
    - mode: 644
    - require:
      - file: nginx_directories
    - contents: |
        upstream fastcgi_backend {
            server unix:/run/php/php8.3-fpm.sock;
        }
    - watch_in:
      - cmd: nginx_configtest
{% else %}
nginx_magento_fastcgi_upstream_cleanup:
  file.absent:
    - name: {{ settings.conf_d_dir }}/fastcgi_backend.conf
    - require:
      - file: nginx_directories
    - watch_in:
      - cmd: nginx_configtest
{% endif %}

{% set csp_cfg = settings.get('csp', {}) %}
{% if csp_cfg.get('enabled', False) and csp_cfg.get('policy') %}
nginx_csp_config:
  file.managed:
    - name: {{ settings.conf_d_dir }}/csp.conf
    - user: root
    - group: root
    - mode: 644
    - contents: |
        add_header Content-Security-Policy "{{ csp_cfg.get('policy') }}" always;
    - require:
      - file: nginx_directories
    - watch_in:
      - cmd: nginx_configtest
{% else %}
nginx_csp_config_cleanup:
  file.absent:
    - name: {{ settings.conf_d_dir }}/csp.conf
    - require:
      - file: nginx_directories
    - watch_in:
      - cmd: nginx_configtest
{% endif %}

{% set modsec_cfg = settings.get('modsecurity', {}) %}
{% set modsec_module_path = modsec_cfg.get('module_path', '/usr/lib/nginx/modules/ngx_http_modsecurity_module.so') %}
{% if modsec_cfg.get('enabled', False) and modsec_cfg.get('level', 0) %}
{% set user_defined_packages = 'packages' in modsec_cfg %}
{% set modsec_packages = modsec_cfg.get('packages', []) %}
{% if not user_defined_packages and not modsec_module_path and salt['grains.get']('os_family', '') == 'Debian' %}
{% if 'libnginx-mod-http-modsecurity' not in modsec_packages %}
{% set modsec_packages = modsec_packages + ['libnginx-mod-http-modsecurity'] %}
{% endif %}
{% endif %}
{% set modsec_has_packages = modsec_packages | length > 0 %}
{% if modsec_has_packages %}
nginx_modsecurity_packages:
  pkg.installed:
    - names:
{% for pkg in modsec_packages %}
      - {{ pkg }}
{% endfor %}
{% endif %}

{% if settings.get('modules_enabled_dir') %}
nginx_modsecurity_module_loader_cleanup:
  file.absent:
    - name: {{ settings.modules_enabled_dir }}/60-modsecurity.conf
    - watch_in:
      - cmd: nginx_configtest
{% endif %}

{% if modsec_module_path and settings.get('modules_enabled_dir') %}
nginx_modsecurity_module_loader:
  file.managed:
    - name: {{ settings.modules_enabled_dir }}/60-modsecurity.conf
    - user: root
    - group: root
    - mode: 644
    - contents: |
        load_module {{ modsec_module_path }};
    - require:
      - file: nginx_directories
      - file: nginx_modsecurity_module_loader_cleanup
{% if modsec_has_packages %}
      - pkg: nginx_modsecurity_packages
{% endif %}
    - watch_in:
      - cmd: nginx_configtest
{% endif %}

nginx_modsecurity_rules:
  file.managed:
    - name: /etc/nginx/modsecurity.conf
    - source: salt://services/nginx/files/modsecurity.conf.jinja
    - template: jinja
    - context:
        level: {{ modsec_cfg.get('level', 5) }}
        admin_path: {{ modsec_cfg.get('admin_path', '/admin_tattoo')|yaml_dquote }}
    - require:
      - file: nginx_directories
{% if modsec_has_packages %}
      - pkg: nginx_modsecurity_packages
{% endif %}
    - watch_in:
      - cmd: nginx_configtest

nginx_modsecurity_include:
  file.managed:
    - name: {{ settings.conf_d_dir }}/modsecurity.conf
    - user: root
    - group: root
    - mode: 644
    - contents: |
        modsecurity on;
        modsecurity_rules_file /etc/nginx/modsecurity.conf;
    - require:
      - file: nginx_modsecurity_rules
    - watch_in:
      - cmd: nginx_configtest
{% else %}
nginx_modsecurity_rules_cleanup:
  file.absent:
    - name: /etc/nginx/modsecurity.conf
    - watch_in:
      - cmd: nginx_configtest

nginx_modsecurity_include_cleanup:
  file.absent:
    - name: {{ settings.conf_d_dir }}/modsecurity.conf
    - watch_in:
      - cmd: nginx_configtest
{% if settings.get('modules_enabled_dir') %}
{% if modsec_module_path %}
nginx_modsecurity_module_loader_cleanup:
  file.absent:
    - name: {{ settings.modules_enabled_dir }}/60-modsecurity.conf
    - watch_in:
      - cmd: nginx_configtest
{% endif %}
{% endif %}
{% endif %}

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
