{% set instances = salt['pillar.get']('mastodon:instances', {}) or {} %}
{% set target_site = salt['pillar.get']('mastodon_site') %}
{% set docker_traefik = salt['pillar.get']('docker:traefik', {}) or {} %}
{% set traefik_http_port = docker_traefik.get('http_port', 18080) %}
{% set traefik_https_port = docker_traefik.get('https_port', 18443) %}
include:
  - optional.docker

{% if target_site and target_site not in instances %}
mastodon-missing-{{ target_site }}:
  test.fail_without_changes:
    - name: "Mastodon instance '{{ target_site }}' not defined in pillar mastodon:instances"
{% endif %}

{% for name, cfg in instances.items() %}
{% if target_site and target_site != name %}
{%   continue %}
{% endif %}
{% set domain = (cfg.get('domain', '') or '').strip() %}
{% set base_dir = cfg.get('base_dir', '/opt/saltgoat/docker/mastodon-' ~ name) %}
{% set image = cfg.get('image', 'ghcr.io/mastodon/mastodon:v4.3.0') %}
{% set streaming_image = cfg.get('streaming_image', 'ghcr.io/mastodon/mastodon-streaming:v4.3.0') %}
{% set admin = cfg.get('admin', {}) %}
{% set postgres = cfg.get('postgres', {}) %}
{% set postgres_image = postgres.get('image', 'postgres:15') %}
{% set postgres_db = postgres.get('db', 'mastodon_' ~ name) %}
{% set postgres_user = postgres.get('user', 'mastodon') %}
{% set postgres_password = postgres.get('password', 'ChangeMePostgres') %}
{% set redis = cfg.get('redis', {}) %}
{% set redis_image = redis.get('image', 'redis:7') %}
{% set smtp = cfg.get('smtp', {}) %}
{% set storage = cfg.get('storage', {}) %}
{% set uploads_dir = storage.get('uploads_dir', base_dir + '/uploads') %}
{% set assets_dir = storage.get('assets_dir', base_dir + '/public-assets') %}
{% set packs_dir = storage.get('packs_dir', base_dir + '/public-packs') %}
{% set backups_dir = storage.get('backups_dir', base_dir + '/backups') %}
{% set traefik_cfg = cfg.get('traefik', {}) or {} %}
{% set router_name = traefik_cfg.get('router', 'mastodon-' + name) %}
{% set entrypoints = traefik_cfg.get('entrypoints', ['web', 'websecure']) %}
{% if entrypoints is string %}
  {% set entrypoints = [entrypoints] %}
{% endif %}
{% set tls_cfg = traefik_cfg.get('tls', {}) if traefik_cfg else {} %}
{% set traefik_tls_enabled = tls_cfg.get('enabled', False) %}
{% set traefik_certresolver = tls_cfg.get('resolver', 'saltgoat') %}
{% set extra_labels = traefik_cfg.get('extra_labels', []) %}
{% if extra_labels is string %}
  {% set extra_labels = [extra_labels] %}
{% endif %}
{% set aliases = traefik_cfg.get('aliases', []) %}
{% if aliases is string %}
  {% set aliases = [aliases] %}
{% endif %}
{% set host_rule = [] %}
{% if domain %}
  {% do host_rule.append('Host(`' ~ domain ~ '`)') %}
{% endif %}
{% for alias in aliases %}
  {% if alias %}
    {% do host_rule.append('Host(`' ~ alias ~ '`)') %}
  {% endif %}
{% endfor %}
{% set traefik_rule = ' || '.join(host_rule) %}
{% set uploads_tmp_dir = base_dir + '/tmp' %}
{% set config_dir = base_dir + '/config' %}
{% set shared_dir = base_dir + '/shared' %}
{% set postgres_dir = base_dir + '/postgres' %}
{% set redis_dir = base_dir + '/redis' %}
{% set secrets_path = base_dir + '/.secrets.env' %}
{% set env_path = base_dir + '/.env.production' %}
{% set compose_path = base_dir + '/docker-compose.yml' %}
{% set project_name = 'mastodon-' ~ name %}

mastodon-{{ name }}-directories:
  file.directory:
    - names:
        - {{ base_dir }}
        - {{ uploads_dir }}
        - {{ assets_dir }}
        - {{ packs_dir }}
        - {{ backups_dir }}
        - {{ uploads_tmp_dir }}
        - {{ config_dir }}
        - {{ shared_dir }}
        - {{ postgres_dir }}
        - {{ redis_dir }}
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

mastodon-{{ name }}-writable-directories:
  file.directory:
    - names:
        - {{ uploads_dir }}
        - {{ uploads_tmp_dir }}
        - {{ assets_dir }}
        - {{ packs_dir }}
    - user: 991
    - group: 991
    - mode: 775
    - makedirs: True
    - recurse:
        - user
        - group
    - require:
      - file: mastodon-{{ name }}-directories

mastodon-{{ name }}-redis-dir:
  file.directory:
    - name: {{ redis_dir }}
    - mode: 777
    - makedirs: True
    - require:
      - file: mastodon-{{ name }}-directories

mastodon-{{ name }}-env:
  file.managed:
    - name: {{ env_path }}
    - source: salt://templates/mastodon/env.production.jinja
    - template: jinja
    - context:
        site: "{{ name }}"
        domain: "{{ domain }}"
        image: "{{ image }}"
        streaming_image: "{{ streaming_image }}"
        admin: {{ admin }}
        postgres: {{ postgres }}
        redis: {{ redis }}
        smtp: {{ smtp }}
        storage:
          uploads_dir: "{{ uploads_dir }}"
        sidekiq_queues: {{ cfg.get('sidekiq_queues', ['default', 'push', 'ingress', 'mailers']) }}
        extra_env: {{ cfg.get('extra_env', {}) }}
    - mode: 640
    - user: root
    - group: root
    - require:
      - file: mastodon-{{ name }}-directories

mastodon-{{ name }}-secrets:
  cmd.script:
    - source: salt://templates/mastodon/generate-secrets.sh.jinja
    - template: jinja
    - context:
        secrets_path: "{{ secrets_path }}"
    - onlyif: test ! -f {{ secrets_path }}
    - require:
      - file: mastodon-{{ name }}-directories

mastodon-{{ name }}-secrets-perms:
  file.managed:
    - name: {{ secrets_path }}
    - user: root
    - group: root
    - mode: 600
    - replace: False
    - require:
      - cmd: mastodon-{{ name }}-secrets

mastodon-{{ name }}-compose:
  file.managed:
    - name: {{ compose_path }}
    - source: salt://templates/mastodon/docker-compose.yml.jinja
    - template: jinja
    - context:
        site: "{{ name }}"
        image: "{{ image }}"
        streaming_image: "{{ streaming_image }}"
        postgres_image: "{{ postgres_image }}"
        postgres_db: "{{ postgres_db }}"
        postgres_user: "{{ postgres_user }}"
        postgres_password: "{{ postgres_password }}"
        redis_image: "{{ redis_image }}"
        base_dir: "{{ base_dir }}"
        uploads_dir: "{{ uploads_dir }}"
        assets_dir: "{{ assets_dir }}"
        packs_dir: "{{ packs_dir }}"
        backups_dir: "{{ backups_dir }}"
        router_name: "{{ router_name }}"
        project_name: "{{ project_name }}"
        traefik_rule: "{{ traefik_rule }}"
        traefik_entrypoints: {{ entrypoints }}
        traefik_tls_enabled: {{ traefik_tls_enabled }}
        traefik_certresolver: "{{ traefik_certresolver }}"
        traefik_extra_labels: {{ extra_labels }}
    - mode: 640
    - user: root
    - group: root
    - require:
      - file: mastodon-{{ name }}-directories

mastodon-{{ name }}-compose-up:
  cmd.run:
    - name: COMPOSE_PROJECT_NAME={{ project_name }} docker compose up -d
    - cwd: {{ base_dir }}
    - env:
        COMPOSE_PROJECT_NAME: {{ project_name }}
    - require:
      - file: mastodon-{{ name }}-compose
      - file: mastodon-{{ name }}-env
      - cmd: mastodon-{{ name }}-secrets
      - file: mastodon-{{ name }}-secrets-perms
      - file: mastodon-{{ name }}-redis-dir
      - file: mastodon-{{ name }}-writable-directories

{% if domain and not traefik_tls_enabled %}
mastodon-{{ name }}-webroot:
  file.directory:
    - name: /var/www/mastodon-{{ name }}
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

mastodon-{{ name }}-nginx-conf:
  file.managed:
    - name: /etc/nginx/sites-available/mastodon-{{ name }}
    - source: salt://templates/nginx/traefik-proxy.conf.jinja
    - template: jinja
    - context:
        primary_domain: {{ domain }}
        aliases: {{ aliases }}
        upstream_port: {{ traefik_http_port }}
        webroot: '/var/www/mastodon-{{ name }}'
        ssl: {{ salt['pillar.get']('nginx:sites:mastodon-' ~ name ~ ':ssl', {}) }}
    - user: root
    - group: root
    - mode: 640
    - require:
      - file: mastodon-{{ name }}-webroot

mastodon-{{ name }}-nginx-link:
  file.symlink:
    - name: /etc/nginx/sites-enabled/mastodon-{{ name }}
    - target: /etc/nginx/sites-available/mastodon-{{ name }}
    - force: True
    - require:
      - file: mastodon-{{ name }}-nginx-conf
{% endif %}

{% if domain and not traefik_tls_enabled %}
mastodon-{{ name }}-nginx-reload:
  service.running:
    - name: nginx
    - enable: True
    - reload: True
    - watch:
      - file: mastodon-{{ name }}-nginx-conf
      - file: mastodon-{{ name }}-nginx-link
{% endif %}

{% endfor %}
