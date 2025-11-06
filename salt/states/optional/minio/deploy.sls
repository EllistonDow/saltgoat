{% set cfg = salt['pillar.get']('minio', {}) %}
{% set base_dir = cfg.get('base_dir', '/opt/saltgoat/docker/minio') %}
{% set data_dir = cfg.get('data_dir', '/var/lib/minio/data') %}
{% set bind_host = cfg.get('bind_host', '127.0.0.1') %}
{% set api_port = cfg.get('api_port', 9000) %}
{% set console_port = cfg.get('console_port', 9001) %}
{% set root_creds = cfg.get('root_credentials', {}) %}
{% set extra_env = cfg.get('extra_env', {}) %}
{% set image = cfg.get('image', 'quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z') %}
{% set health = cfg.get('health', {}) %}
{% set docker_traefik = salt['pillar.get']('docker:traefik', {}) or {} %}
{% set traefik_http_port = docker_traefik.get('http_port', 18080) %}
{% set traefik_cfg = cfg.get('traefik', {}) or {} %}
{% set traefik_api_cfg = traefik_cfg.get('api', {}) or {} %}
{% set traefik_console_cfg = traefik_cfg.get('console', {}) or {} %}
{% set api_domain = (traefik_api_cfg.get('domain', cfg.get('domain', '')) or '').strip() %}
{% set api_aliases = traefik_api_cfg.get('aliases', cfg.get('domain_aliases', [])) %}
{% if api_aliases is string %}
  {% set api_aliases = [api_aliases] %}
{% endif %}
{% set console_domain = (traefik_console_cfg.get('domain', cfg.get('console_domain', '')) or '').strip() %}
{% set console_aliases = traefik_console_cfg.get('aliases', cfg.get('console_domain_aliases', [])) %}
{% if console_aliases is string %}
  {% set console_aliases = [console_aliases] %}
{% endif %}
{% set api_entrypoints = traefik_api_cfg.get('entrypoints', ['web']) %}
{% if api_entrypoints is string %}
  {% set api_entrypoints = [api_entrypoints] %}
{% endif %}
{% set console_entrypoints = traefik_console_cfg.get('entrypoints', ['web']) %}
{% if console_entrypoints is string %}
  {% set console_entrypoints = [console_entrypoints] %}
{% endif %}
{% set api_router = traefik_api_cfg.get('router', (api_domain.replace('.', '-') if api_domain else 'minio-api')) %}
{% set console_router = traefik_console_cfg.get('router', (console_domain.replace('.', '-') if console_domain else 'minio-console')) %}
{% set api_tls_enabled = traefik_api_cfg.get('tls', {}).get('enabled', False) %}
{% set console_tls_enabled = traefik_console_cfg.get('tls', {}).get('enabled', False) %}
{% set api_cert_resolver = traefik_api_cfg.get('tls', {}).get('resolver', 'saltgoat') %}
{% set console_cert_resolver = traefik_console_cfg.get('tls', {}).get('resolver', 'saltgoat') %}
{% set api_extra_labels = traefik_api_cfg.get('extra_labels', []) %}
{% if api_extra_labels is string %}
  {% set api_extra_labels = [api_extra_labels] %}
{% endif %}
{% set console_extra_labels = traefik_console_cfg.get('extra_labels', []) %}
{% if console_extra_labels is string %}
  {% set console_extra_labels = [console_extra_labels] %}
{% endif %}
{% set api_hosts = [] %}
{% if api_domain %}
  {% do api_hosts.append(api_domain) %}
{% endif %}
{% for host in api_aliases %}
  {% if host %}
    {% do api_hosts.append(host) %}
  {% endif %}
{% endfor %}
{% set api_rule = ' || '.join(['Host(`{}`)'.format(h) for h in api_hosts]) %}
{% set console_hosts = [] %}
{% if console_domain %}
  {% do console_hosts.append(console_domain) %}
{% endif %}
{% for host in console_aliases %}
  {% if host %}
    {% do console_hosts.append(host) %}
  {% endif %}
{% endfor %}
{% set console_rule = ' || '.join(['Host(`{}`)'.format(h) for h in console_hosts]) %}
{% set api_proxy_conf = '/etc/nginx/sites-available/minio-api' %}
{% set api_proxy_link = '/etc/nginx/sites-enabled/minio-api' %}
{% set console_proxy_conf = '/etc/nginx/sites-available/minio-console' %}
{% set console_proxy_link = '/etc/nginx/sites-enabled/minio-console' %}
{% set legacy_api_conf = '/etc/nginx/sites-available/traefik-minio-api.conf' %}
{% set legacy_api_link = '/etc/nginx/sites-enabled/traefik-minio-api.conf' %}
{% set legacy_console_conf = '/etc/nginx/sites-available/traefik-minio-console.conf' %}
{% set legacy_console_link = '/etc/nginx/sites-enabled/traefik-minio-console.conf' %}
{% set api_nginx_site = salt['pillar.get']('nginx:sites:minio-api', {}) or {} %}
{% set console_nginx_site = salt['pillar.get']('nginx:sites:minio-console', {}) or {} %}

include:
  - optional.docker.compose

minio-dirs:
  file.directory:
    - names:
        - {{ base_dir }}
        - {{ data_dir }}
    - user: root
    - group: root
    - mode: 750
    - makedirs: True

{{ base_dir }}/docker-compose.yml:
  file.managed:
    - source: salt://templates/minio/docker-compose.yml.jinja
    - template: jinja
    - context:
        image: {{ image }}
        bind_host: {{ bind_host }}
        api_port: {{ api_port }}
        console_port: {{ console_port }}
        data_dir: {{ data_dir }}
        root_user: {{ root_creds.get('access_key', 'minioadmin') }}
        root_password: {{ root_creds.get('secret_key', 'minioadmin') }}
        extra_env: {{ extra_env }}
        traefik_api:
          rule: {{ api_rule }}
          router: {{ api_router }}
          entrypoints: {{ api_entrypoints }}
          tls_enabled: {{ api_tls_enabled }}
          cert_resolver: {{ api_cert_resolver }}
          service_name: {{ api_router }}-svc
          extra_labels: {{ api_extra_labels }}
        traefik_console:
          rule: {{ console_rule }}
          router: {{ console_router }}
          entrypoints: {{ console_entrypoints }}
          tls_enabled: {{ console_tls_enabled }}
          cert_resolver: {{ console_cert_resolver }}
          service_name: {{ console_router }}-svc
          extra_labels: {{ console_extra_labels }}
    - require:
      - file: minio-dirs

minio-up:
  cmd.run:
    - name: docker compose up -d
    - cwd: {{ base_dir }}
    - env:
        COMPOSE_PROJECT_NAME: minio
    - require:
      - file: {{ base_dir }}/docker-compose.yml

minio-health-note:
  test.show_notification:
    - text: |
        MinIO will listen on {{ bind_host }}:{{ api_port }} (API) and {{ bind_host }}:{{ console_port }} (Console).
        Configure your reverse proxy (e.g. Traefik or host Nginx) accordingly. Health endpoint: {{ health.get('scheme', 'http') }}://{{ health.get('host', bind_host) }}:{{ health.get('port', api_port) }}{{ health.get('endpoint', '/minio/health/live') }}

{% set proxy_watch = [] %}
{% if api_domain and not api_tls_enabled %}
minio-api-proxy-conf:
  file.managed:
    - name: {{ api_proxy_conf }}
    - source: salt://templates/nginx/traefik-proxy.conf.jinja
    - template: jinja
    - context:
        primary_domain: {{ api_domain }}
        aliases: {{ api_aliases }}
        upstream_port: {{ traefik_http_port }}
        webroot: '/var/www/letsencrypt'
        ssl: {{ api_nginx_site.get('ssl', {}) }}
    - user: root
    - group: root
    - mode: 640

minio-api-proxy-link:
  file.symlink:
    - name: {{ api_proxy_link }}
    - target: {{ api_proxy_conf }}
    - force: True
    - require:
      - file: minio-api-proxy-conf
{%   set proxy_watch = proxy_watch + ['minio-api-proxy-conf', 'minio-api-proxy-link'] %}
{% else %}
minio-api-proxy-conf:
  file.absent:
    - name: {{ api_proxy_conf }}

minio-api-proxy-link:
  file.absent:
    - name: {{ api_proxy_link }}
{% endif %}

{% if console_domain and not console_tls_enabled %}
minio-console-proxy-conf:
  file.managed:
    - name: {{ console_proxy_conf }}
    - source: salt://templates/nginx/traefik-proxy.conf.jinja
    - template: jinja
    - context:
        primary_domain: {{ console_domain }}
        aliases: {{ console_aliases }}
        upstream_port: {{ traefik_http_port }}
        webroot: '/var/www/letsencrypt'
        ssl: {{ console_nginx_site.get('ssl', {}) }}
    - user: root
    - group: root
    - mode: 640

minio-console-proxy-link:
  file.symlink:
    - name: {{ console_proxy_link }}
    - target: {{ console_proxy_conf }}
    - force: True
    - require:
      - file: minio-console-proxy-conf
{%   set proxy_watch = proxy_watch + ['minio-console-proxy-conf', 'minio-console-proxy-link'] %}
{% else %}
minio-console-proxy-conf:
  file.absent:
    - name: {{ console_proxy_conf }}

minio-console-proxy-link:
  file.absent:
    - name: {{ console_proxy_link }}
{% endif %}

{% if proxy_watch %}
minio-nginx-reload:
  service.running:
    - name: nginx
    - enable: True
    - reload: True
    - watch:
{%   for item in proxy_watch %}
      - file: {{ item }}
{%   endfor %}
{% endif %}

minio-legacy-proxy-clean:
  test.nop: []

{% if True %}
minio-legacy-api-conf:
  file.absent:
    - name: {{ legacy_api_conf }}

minio-legacy-api-link:
  file.absent:
    - name: {{ legacy_api_link }}

minio-legacy-console-conf:
  file.absent:
    - name: {{ legacy_console_conf }}

minio-legacy-console-link:
  file.absent:
    - name: {{ legacy_console_link }}
{% endif %}
