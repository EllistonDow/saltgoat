{% set cfg = salt['pillar.get']('uptime_kuma', {}) or {} %}
{% set base_dir = cfg.get('base_dir', '/opt/saltgoat/docker/uptime-kuma') %}
{% set data_dir = cfg.get('data_dir', base_dir + '/data') %}
{% set bind_host = cfg.get('bind_host', '127.0.0.1') %}
{% set http_port = cfg.get('http_port', 3001) %}
{% set image = cfg.get('image', 'louislam/uptime-kuma:1') %}
{% set environment = cfg.get('environment', {}) if cfg.get('environment') else {} %}
{% set traefik_cfg = cfg.get('traefik', {}) if cfg.get('traefik') else {} %}
{% set domain = (traefik_cfg.get('domain', '') or '').strip() %}
{% set aliases = traefik_cfg.get('aliases', []) %}
{% if aliases is string %}
  {% set aliases = [ aliases ] %}
{% endif %}
{% set entrypoints = traefik_cfg.get('entrypoints', ['web']) %}
{% if entrypoints is string %}
  {% set entrypoints = [ entrypoints ] %}
{% endif %}
{% set traefik_router = traefik_cfg.get('router', (domain.replace('.', '-') if domain else 'uptime-kuma')) %}
{% set traefik_tls_cfg = traefik_cfg.get('tls', {}) if traefik_cfg.get('tls') else {} %}
{% set traefik_tls_enabled = traefik_tls_cfg.get('enabled', False) %}
{% set traefik_cert_resolver = traefik_tls_cfg.get('resolver', 'saltgoat') %}
{% set traefik_extra_labels = traefik_cfg.get('extra_labels', []) %}
{% if traefik_extra_labels is string %}
  {% set traefik_extra_labels = [ traefik_extra_labels ] %}
{% endif %}
{% set host_ns = namespace(rule='') %}
{% if domain %}
  {% set host_ns.rule = 'Host(`' ~ domain ~ '`)' %}
{% endif %}
{% for host in aliases %}
  {% if host %}
    {% if host_ns.rule %}
      {% set host_ns.rule = host_ns.rule + ' || ' %}
    {% endif %}
    {% set host_ns.rule = host_ns.rule + 'Host(`' ~ host ~ '`)' %}
  {% endif %}
{% endfor %}
{% set traefik_rule = host_ns.rule %}
{% set docker_traefik = salt['pillar.get']('docker:traefik', {}) or {} %}
{% set traefik_http_port = docker_traefik.get('http_port', 18080) %}
{% set site_name = 'uptime-kuma' %}
{% set nginx_proxy_conf = '/etc/nginx/sites-available/' + site_name %}
{% set nginx_proxy_link = '/etc/nginx/sites-enabled/' + site_name %}
{% set legacy_proxy_conf = '/etc/nginx/sites-available/traefik-uptime-kuma.conf' %}
{% set legacy_proxy_link = '/etc/nginx/sites-enabled/traefik-uptime-kuma.conf' %}
{% set nginx_site_cfg = salt['pillar.get']('nginx:sites:' + site_name, {}) or {} %}
{% set webroot_path = nginx_site_cfg.get('root', '/var/www/' + site_name) %}
{% set compose_path = base_dir + '/docker-compose.yml' %}

legacy-uptime-service:
  service.dead:
    - name: uptime-kuma
    - enable: False
    - onlyif: test -f /etc/systemd/system/uptime-kuma.service

legacy-uptime-unit:
  file.absent:
    - name: /etc/systemd/system/uptime-kuma.service
    - require:
      - service: legacy-uptime-service

legacy-uptime-dir:
  file.absent:
    - name: /opt/uptime-kuma
    - require:
      - service: legacy-uptime-service

legacy-daemon-reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: legacy-uptime-unit

uptime-kuma-base-dir:
  file.directory:
    - name: {{ base_dir }}
    - user: root
    - group: root
    - mode: 750
    - makedirs: True

uptime-kuma-data-dir:
  file.directory:
    - name: {{ data_dir }}
    - user: root
    - group: root
    - mode: 750
    - makedirs: True
    - require:
      - file: uptime-kuma-base-dir

uptime-kuma-compose:
  file.managed:
    - name: {{ compose_path }}
    - source: salt://templates/uptime-kuma/docker-compose.yml.jinja
    - template: jinja
    - context:
        image: {{ image }}
        bind_host: {{ bind_host }}
        http_port: {{ http_port }}
        data_dir: {{ data_dir }}
        environment: {{ environment }}
        traefik_router: {{ traefik_router }}
        traefik_rule: {{ traefik_rule }}
        traefik_entrypoints: {{ entrypoints }}
        traefik_tls_enabled: {{ traefik_tls_enabled }}
        traefik_cert_resolver: {{ traefik_cert_resolver }}
        traefik_extra_labels: {{ traefik_extra_labels }}
    - user: root
    - group: root
    - mode: 640
    - require:
      - file: uptime-kuma-base-dir

uptime-kuma-up:
  cmd.run:
    - name: COMPOSE_PROJECT_NAME=uptime-kuma docker compose up -d
    - cwd: {{ base_dir }}
    - require:
      - file: uptime-kuma-compose
      - file: uptime-kuma-data-dir
    - watch:
      - file: uptime-kuma-compose

{% if domain and not traefik_tls_enabled %}
uptime-kuma-proxy-conf:
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

uptime-kuma-proxy-link:
  file.symlink:
    - name: {{ nginx_proxy_link }}
    - target: {{ nginx_proxy_conf }}
    - force: True
    - require:
      - file: uptime-kuma-proxy-conf

uptime-kuma-nginx-reload:
  service.running:
    - name: nginx
    - enable: True
    - reload: True
    - watch:
      - file: uptime-kuma-proxy-conf
      - file: uptime-kuma-proxy-link
{% else %}
uptime-kuma-proxy-conf:
  file.absent:
    - name: {{ nginx_proxy_conf }}

uptime-kuma-proxy-link:
  file.absent:
    - name: {{ nginx_proxy_link }}
{% endif %}

uptime-kuma-legacy-proxy-conf:
  file.absent:
    - name: {{ legacy_proxy_conf }}

uptime-kuma-legacy-proxy-link:
  file.absent:
    - name: {{ legacy_proxy_link }}
