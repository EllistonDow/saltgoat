{% set cfg = salt['pillar.get']('docker:traefik', {}) or {} %}
{% set base_dir = cfg.get('base_dir', '/opt/saltgoat/docker/traefik') %}
{% set config_dir = base_dir + '/config' %}
{% set dynamic_dir = base_dir + '/dynamic' %}
{% set data_dir = base_dir + '/data' %}
{% set acme_enabled = cfg.get('acme', {}).get('enabled') %}
{% set acme_file = data_dir + '/' + cfg.get('acme', {}).get('storage', 'acme.json') %}

docker-traefik-base:
  file.directory:
    - name: {{ base_dir }}
    - user: root
    - group: root
    - mode: 750
    - makedirs: True

docker-traefik-config-dir:
  file.directory:
    - name: {{ config_dir }}
    - user: root
    - group: root
    - mode: 750
    - makedirs: True
    - require:
      - file: docker-traefik-base

docker-traefik-dynamic-dir:
  file.directory:
    - name: {{ dynamic_dir }}
    - user: root
    - group: root
    - mode: 750
    - makedirs: True
    - require:
      - file: docker-traefik-base

docker-traefik-data-dir:
  file.directory:
    - name: {{ data_dir }}
    - user: root
    - group: root
    - mode: 750
    - makedirs: True
    - require:
      - file: docker-traefik-base

{% if acme_enabled %}
docker-traefik-acme:
  file.managed:
    - name: {{ acme_file }}
    - user: root
    - group: root
    - mode: 600
    - makedirs: True
    - contents: "{}"
    - require:
      - file: docker-traefik-data-dir
{% endif %}

docker-traefik-static-config:
  file.managed:
    - name: {{ config_dir }}/traefik.yml
    - source: salt://optional/docker/traefik/traefik.yml.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 640
    - require:
      - file: docker-traefik-config-dir

docker-traefik-dynamic-readme:
  file.managed:
    - name: {{ dynamic_dir }}/README.txt
    - user: root
    - group: root
    - mode: 640
    - contents: |
        Place additional Traefik file provider definitions in this directory.
        Files must use .yml or .yaml extensions. SaltGoat CLI commands will
        render service-specific routers automatically when available.
    - require:
      - file: docker-traefik-dynamic-dir

docker-traefik-compose:
  file.managed:
    - name: {{ base_dir }}/docker-compose.yml
    - source: salt://optional/docker/traefik/docker-compose.yml.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 640
    - require:
      - file: docker-traefik-base

legacy-npm-compose-dir:
  file.absent:
    - name: /opt/saltgoat/docker/npm

legacy-proxy-conf-dir:
  file.absent:
    - name: /etc/nginx/conf.d/proxy

docker-traefik-up:
  cmd.run:
    - name: COMPOSE_PROJECT_NAME={{ cfg['project'] }} docker compose up -d
    - cwd: {{ base_dir }}
    - require:
      - file: docker-traefik-compose
      - file: docker-traefik-static-config
      - file: docker-traefik-dynamic-readme
{% if acme_enabled %}
      - file: docker-traefik-acme
{% endif %}
    - watch:
      - file: docker-traefik-compose
      - file: docker-traefik-static-config
      - file: docker-traefik-dynamic-readme
{% if acme_enabled %}
      - file: docker-traefik-acme
{% endif %}
