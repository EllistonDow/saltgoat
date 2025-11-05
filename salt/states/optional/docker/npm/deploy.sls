{% set npm = salt['pillar.get']('docker:npm', {}) %}
{% if not npm %}
{% set npm = {} %}
{% endif %}
{% set base_dir = npm.get('base_dir', '/opt/saltgoat/docker/npm') %}
{% set data_dir = base_dir + '/data' %}
{% set db_dir = base_dir + '/db' %}
{% set compose_file = base_dir + '/docker-compose.yml' %}
{% set db_password = npm.get('db_password', salt['grains.get']('id', '') | replace('.', '') + 'NpM@123') %}

docker-npm-dirs:
  file.directory:
    - names:
        - {{ base_dir }}
        - {{ data_dir }}
        - {{ db_dir }}
    - user: root
    - group: root
    - mode: 750
    - makedirs: True

docker-npm-compose:
  file.managed:
    - name: {{ compose_file }}
    - source: salt://optional/docker/npm/docker-compose.yml.jinja
    - template: jinja
    - context:
        base_dir: {{ base_dir }}
        data_dir: {{ data_dir }}
        db_dir: {{ db_dir }}
        npm_image: {{ npm.get('image', 'jc21/nginx-proxy-manager:2.11.3') }}
        db_image: {{ npm.get('db_image', 'mariadb:10.11') }}
        http_port: {{ npm.get('http_port', 8080) }}
        https_port: {{ npm.get('https_port', 8443) }}
        admin_port: {{ npm.get('admin_port', 9181) }}
        db_password: {{ db_password }}
    - require:
      - file: docker-npm-dirs

docker-npm-compose-up:
  cmd.run:
    - name: docker compose up -d
    - cwd: {{ base_dir }}
    - env:
        COMPOSE_PROJECT_NAME: npm
    - require:
      - file: docker-npm-compose
