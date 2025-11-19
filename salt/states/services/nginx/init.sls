{# Nginx 安装与站点管理（Salt 原生） #}
{% from "services/nginx/map.jinja" import settings with context %}
{% set settings_serialized = salt['slsutil.serialize']('json', settings) %}
{% set generate_stub_ssl = settings.get('generate_stub_ssl', True) %}
{% set stub_cert = settings.get('stub_ssl_cert', '/etc/ssl/certs/saltgoat-selfsigned.pem') %}
{% set stub_key = settings.get('stub_ssl_key', '/etc/ssl/private/saltgoat-selfsigned.key') %}
{% set stub_subject = settings.get('stub_ssl_subject', '/CN=saltgoat.local') %}
{% set stub_cert_dir = stub_cert.rsplit('/', 1)[0] %}
{% set stub_key_dir = stub_key.rsplit('/', 1)[0] %}
{% set ssl_sites = [] %}
{% for name, site in settings.sites.items() %}
  {% set ssl_cfg = site.get('ssl', {}) or {} %}
  {% if ssl_cfg.get('enabled') and ssl_cfg.get('cert') and ssl_cfg.get('key') %}
    {% set _ = ssl_sites.append({'name': name, 'cert': ssl_cfg.get('cert'), 'key': ssl_cfg.get('key')}) %}
  {% endif %}
{% endfor %}

nginx_repo_prereq:
  pkg.installed:
    - names:
      - ca-certificates
      - curl

nginx_repo_mainline:
  pkgrepo.managed:
    - name: deb http://nginx.org/packages/mainline/ubuntu/ {{ grains['oscodename'] }} nginx
    - file: /etc/apt/sources.list.d/nginx.list
    - key_url: https://nginx.org/keys/nginx_signing.key
    - clean_file: True
    - dist: {{ grains['oscodename'] }}
    - refresh: True
    - require:
      - pkg: nginx_repo_prereq

nginx_pkg:
  pkg.latest:
    - name: {{ settings.package }}
    - require:
      - pkgrepo: nginx_repo_mainline

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

{% if generate_stub_ssl and ssl_sites %}
saltgoat_stub_ssl_cert_dir:
  file.directory:
    - name: {{ stub_cert_dir }}
    - makedirs: True
    - mode: 755
    - user: root
    - group: root

saltgoat_stub_ssl_key_dir:
  file.directory:
    - name: {{ stub_key_dir }}
    - makedirs: True
    - mode: 750
    - user: root
    - group: root

saltgoat_stub_ssl_cert:
  cmd.run:
    - name: openssl req -x509 -nodes -newkey rsa:2048 -subj '{{ stub_subject }}' -keyout {{ stub_key }} -out {{ stub_cert }} -days 3650
    - creates: {{ stub_cert }}
    - require:
      - file: saltgoat_stub_ssl_cert_dir
      - file: saltgoat_stub_ssl_key_dir

{% for ssl_site in ssl_sites %}
{{ ssl_site.name }}_ssl_cert_dir:
  file.directory:
    - name: {{ ssl_site.cert.rsplit('/', 1)[0] }}
    - makedirs: True
    - mode: 755
    - user: root
    - group: root

{{ ssl_site.name }}_ssl_key_dir:
  file.directory:
    - name: {{ ssl_site.key.rsplit('/', 1)[0] }}
    - makedirs: True
    - mode: 750
    - user: root
    - group: root

{{ ssl_site.name }}_stub_ssl_cert_copy:
  cmd.run:
    - name: install -D -m 644 {{ stub_cert }} {{ ssl_site.cert }}
    - unless: test -f {{ ssl_site.cert }}
    - require:
      - cmd: saltgoat_stub_ssl_cert
      - file: {{ ssl_site.name }}_ssl_cert_dir

{{ ssl_site.name }}_stub_ssl_key_copy:
  cmd.run:
    - name: install -D -m 600 {{ stub_key }} {{ ssl_site.key }}
    - unless: test -f {{ ssl_site.key }}
    - require:
      - cmd: saltgoat_stub_ssl_cert
      - file: {{ ssl_site.name }}_ssl_key_dir
{% endfor %}
{% endif %}

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
{% set modsec_packages = [
  'libmodsecurity3t64',
  'libmodsecurity-dev',
  'build-essential',
  'pkg-config',
  'libpcre3-dev',
  'zlib1g-dev',
  'git',
  'cmake',
  'patchelf'
] + modsec_cfg.get('packages', []) %}
{% set modsec_has_packages = modsec_packages | length > 0 %}
{% if modsec_has_packages %}
nginx_modsecurity_packages:
  pkg.installed:
    - names:
{% for pkg in modsec_packages %}
      - {{ pkg }}
{% endfor %}
    - require:
      - pkg: nginx_pkg
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
      - cmd: nginx_modsecurity_module_build
{% if modsec_has_packages %}
      - pkg: nginx_modsecurity_packages
{% endif %}
    - watch_in:
      - cmd: nginx_configtest
{% endif %}

nginx_modsecurity_marker_dir:
  file.directory:
    - name: /var/lib/saltgoat/cache
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

nginx_modsecurity_module_build:
  cmd.run:
    - name: |
        set -euo pipefail
        mkdir -p /usr/local/src
        cd /usr/local/src
        nginx_version="$({{ settings.binary }} -v 2>&1 | sed -E 's/.*nginx\/([^ ]+).*/\1/')"
        if [ -z "$nginx_version" ]; then
          echo "无法获取 Nginx 版本" >&2
          exit 1
        fi
        src_tar="nginx-${nginx_version}.tar.gz"
        curl -fsSL -o "$src_tar" "https://nginx.org/download/${src_tar}"
        rm -rf "nginx-${nginx_version}"
        tar -xf "$src_tar"
        if [ ! -d pcre-8.45 ]; then
          curl -fsSL -o pcre-8.45.tar.gz https://ftp.pcre.org/pub/pcre/pcre-8.45.tar.gz || curl -fsSL -o pcre-8.45.tar.gz https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.gz/download
          tar -xf pcre-8.45.tar.gz
        fi
        if [ -d ModSecurity-nginx ]; then
          cd ModSecurity-nginx
          git fetch --depth=1 origin v1.0.3
          git checkout -q v1.0.3
          cd ..
        else
          git clone --depth=1 --branch v1.0.3 https://github.com/SpiderLabs/ModSecurity-nginx.git ModSecurity-nginx
        fi
        cd "nginx-${nginx_version}"
        ./configure --with-compat --add-dynamic-module=../ModSecurity-nginx --with-pcre=../pcre-8.45
        make modules
        install -d -m 755 "$(dirname {{ modsec_module_path }})"
        install -m 644 objs/ngx_http_modsecurity_module.so {{ modsec_module_path }}
        if command -v patchelf >/dev/null 2>&1; then
          patchelf --add-needed libpcre.so.3 {{ modsec_module_path }} || true
          patchelf --remove-needed libpcre2-8.so.0 {{ modsec_module_path }} || true
        fi
        echo "$nginx_version" > /var/lib/saltgoat/cache/nginx_modsecurity_module.version
    - unless: test -f {{ modsec_module_path }} && test -f /var/lib/saltgoat/cache/nginx_modsecurity_module.version && grep -qx "$( {{ settings.binary }} -v 2>&1 | sed -E 's/.*nginx\/([^ ]+).*/\1/' )" /var/lib/saltgoat/cache/nginx_modsecurity_module.version
    - require:
      - pkg: nginx_pkg
      - pkg: nginx_modsecurity_packages
      - file: nginx_modsecurity_marker_dir
    - watch_in:
      - cmd: nginx_configtest

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
