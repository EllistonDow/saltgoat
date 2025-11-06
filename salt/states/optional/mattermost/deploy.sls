{% set mm = salt['pillar.get']('mattermost', {}) or {} %}
{% set base_dir = mm.get('base_dir', '/opt/saltgoat/docker/mattermost') %}
{% set http_port = mm.get('http_port', 8065) %}
{% set compose_file = base_dir + '/docker-compose.yml' %}
{% set env_file = base_dir + '/.env' %}
{% set mm_image = mm.get('image', 'mattermost/mattermost-team-edition:latest') %}
{% set db = mm.get('db', {}) %}
{% set db_image = db.get('image', 'postgres:15') %}
{% set db_user = db.get('user', 'mattermost') %}
{% set db_password = db.get('password', 'MattermostDBPass!') %}
{% set db_name = db.get('name', 'mattermost') %}
{% set site_url = mm.get('site_url', 'http://localhost:8065') %}
{% set admin = mm.get('admin', {}) %}
{% set admin_username = admin.get('username', 'sysadmin') %}
{% set admin_password = admin.get('password', 'ChangeMeAdmin!') %}
{% set admin_email = admin.get('email', 'mattermost@example.com') %}
{% set smtp = mm.get('smtp', {}) %}
{% set smtp_host = smtp.get('host', '') %}
{% set smtp_enabled = True if smtp_host else False %}
{% set smtp_port = smtp.get('port', 587) %}
{% set smtp_username = smtp.get('username', '') %}
{% set smtp_password = smtp.get('password', '') %}
{% set smtp_from = smtp.get('from_email', admin_email) %}
{% set smtp_tls = 'true' if smtp.get('enable_tls', True) else 'false' %}
{% set smtp_auth = 'true' if smtp_username else 'false' %}
{% set file_store = mm.get('file_store', {}) %}
{% set file_driver = file_store.get('type', 'local') %}
{% set extra_env = mm.get('extra_env', {}) %}
{% set config_dir = base_dir + '/config' %}
{% set data_dir = base_dir + '/data' %}
{% set logs_dir = base_dir + '/logs' %}
{% set plugins_dir = base_dir + '/plugins' %}
{% set client_plugins_dir = base_dir + '/client-plugins' %}
{% set mm_uid = mm.get('uid', 2000) %}
{% set mm_gid = mm.get('gid', 2000) %}
{% set mm_user = mm.get('system_user', 'mattermost') %}
{% set mm_group = mm.get('system_group', mm_user) %}
{% set domain = (mm.get('domain', '') or '').strip() %}
{% set aliases = mm.get('aliases', []) %}
{% if aliases is string %}
  {% set aliases = [aliases] %}
{% endif %}
{% set traefik_cfg = mm.get('traefik', {}) %}
{% set router_name = traefik_cfg.get('router', domain.replace('.', '-') if domain else 'mattermost') %}
{% set entrypoints = traefik_cfg.get('entrypoints', ['web']) %}
{% if entrypoints is string %}
  {% set entrypoints = [entrypoints] %}
{% endif %}
{% set entrypoints_csv = ','.join(entrypoints) %}
{% set tls_cfg = traefik_cfg.get('tls', {}) if traefik_cfg else {} %}
{% set traefik_tls_enabled = tls_cfg.get('enabled', False) %}
{% set traefik_certresolver = tls_cfg.get('resolver', 'saltgoat') %}
{% set traefik_service_port = traefik_cfg.get('service_port', http_port) %}
{% set traefik_extra_labels = traefik_cfg.get('extra_labels', []) %}
{% set host_ns = namespace(rule='') %}
{% if domain %}
  {% if host_ns.rule %}
    {% set host_ns.rule = host_ns.rule + ' || ' %}
  {% endif %}
  {% set host_ns.rule = host_ns.rule + 'Host(`' ~ domain ~ '`)' %}
{% endif %}
{% for alias in aliases %}
  {% if alias %}
    {% if host_ns.rule %}
      {% set host_ns.rule = host_ns.rule + ' || ' %}
    {% endif %}
    {% set host_ns.rule = host_ns.rule + 'Host(`' ~ alias ~ '`)' %}
  {% endif %}
{% endfor %}
{% set traefik_rule = host_ns.rule %}
{% set docker_traefik = salt['pillar.get']('docker:traefik', {}) or {} %}
{% set traefik_http_port = docker_traefik.get('http_port', 18080) %}
{% set site_name = 'mattermost' %}
{% set nginx_proxy_conf = '/etc/nginx/sites-available/' + site_name %}
{% set nginx_proxy_link = '/etc/nginx/sites-enabled/' + site_name %}
{% set legacy_proxy_conf = '/etc/nginx/sites-available/traefik-mattermost.conf' %}
{% set legacy_proxy_link = '/etc/nginx/sites-enabled/traefik-mattermost.conf' %}
{% set nginx_site_cfg = salt['pillar.get']('nginx:sites:' + site_name, {}) or {} %}
{% set webroot_path = nginx_site_cfg.get('root', '/var/www/' + site_name) %}

include:
  - optional.docker

mattermost-group:
  group.present:
    - name: {{ mm_group }}
    - gid: {{ mm_gid }}
    - system: True

mattermost-user:
  user.present:
    - name: {{ mm_user }}
    - uid: {{ mm_uid }}
    - gid: {{ mm_gid }}
    - home: {{ base_dir }}
    - shell: /usr/sbin/nologin
    - system: True
    - require:
      - group: mattermost-group

mattermost-directories:
  file.directory:
    - names:
        - {{ base_dir }}
        - {{ config_dir }}
        - {{ data_dir }}
        - {{ logs_dir }}
        - {{ plugins_dir }}
        - {{ client_plugins_dir }}
    - user: {{ mm_user }}
    - group: {{ mm_group }}
    - mode: 750
    - makedirs: True
    - require:
      - user: mattermost-user

mattermost-env:
  file.managed:
    - name: {{ env_file }}
    - source: salt://templates/mattermost/env.jinja
    - template: jinja
    - context:
        db_user: {{ db_user }}
        db_password: {{ db_password }}
        db_name: {{ db_name }}
        site_url: {{ site_url }}
        admin_username: {{ admin_username }}
        admin_password: {{ admin_password }}
        admin_email: {{ admin_email }}
        smtp_enabled: {{ smtp_enabled }}
        smtp_host: {{ smtp_host }}
        smtp_port: {{ smtp_port }}
        smtp_username: {{ smtp_username }}
        smtp_password: {{ smtp_password }}
        smtp_from: {{ smtp_from }}
        smtp_tls: {{ smtp_tls }}
        smtp_auth: {{ smtp_auth }}
        file_driver: {{ file_driver }}
        extra_env: {{ extra_env }}
    - mode: 640
    - user: root
    - group: root
    - require:
      - file: mattermost-directories

mattermost-compose:
  file.managed:
    - name: {{ compose_file }}
    - source: salt://templates/mattermost/docker-compose.yml.jinja
    - template: jinja
    - context:
        base_dir: {{ base_dir }}
        http_port: {{ http_port }}
        mm_image: {{ mm_image }}
        db_image: {{ db_image }}
        db_user: {{ db_user }}
        db_password: {{ db_password }}
        db_name: {{ db_name }}
        config_dir: {{ config_dir }}
        data_dir: {{ data_dir }}
        logs_dir: {{ logs_dir }}
        plugins_dir: {{ plugins_dir }}
        client_plugins_dir: {{ client_plugins_dir }}
        traefik:
          domain: {{ domain }}
          aliases: {{ aliases }}
          router: {{ router_name }}
          entrypoints: {{ entrypoints }}
          rule: {{ traefik_rule }}
          tls_enabled: {{ traefik_tls_enabled }}
          cert_resolver: {{ traefik_certresolver }}
          service_port: {{ traefik_service_port }}
          extra_labels: {{ traefik_extra_labels }}
    - mode: 640
    - require:
      - file: mattermost-directories

mattermost-up:
  cmd.run:
    - name: docker compose up -d
    - cwd: {{ base_dir }}
    - env:
        COMPOSE_PROJECT_NAME: mattermost
    - require:
      - file: mattermost-compose
      - file: mattermost-env

{% if not traefik_tls_enabled and domain %}
mattermost-traefik-proxy-conf:
  file.managed:
    - name: {{ nginx_proxy_conf }}
    - source: salt://templates/nginx/traefik-proxy.conf.jinja
    - template: jinja
    - context:
        primary_domain: {{ domain }}
        aliases: {{ aliases }}
        upstream_port: {{ traefik_http_port }}
        webroot: {{ webroot_path }}
        ssl: {{ nginx_site_cfg.get('ssl', {}) }}
    - user: root
    - group: root
    - mode: 640

mattermost-traefik-proxy-link:
  file.symlink:
    - name: {{ nginx_proxy_link }}
    - target: {{ nginx_proxy_conf }}
    - force: True
    - require:
      - file: mattermost-traefik-proxy-conf

mattermost-nginx-reload:
  service.running:
    - name: nginx
    - enable: True
    - reload: True
    - watch:
      - file: mattermost-traefik-proxy-conf
      - file: mattermost-traefik-proxy-link
{% else %}
mattermost-traefik-proxy-conf:
  file.absent:
    - name: {{ nginx_proxy_conf }}

mattermost-traefik-proxy-link:
  file.absent:
    - name: {{ nginx_proxy_link }}
{% endif %}

mattermost-legacy-proxy-conf:
  file.absent:
    - name: {{ legacy_proxy_conf }}

mattermost-legacy-proxy-link:
  file.absent:
    - name: {{ legacy_proxy_link }}
