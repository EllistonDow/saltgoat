{# Matomo 安装默认配置，支持 Pillar 覆盖 #}
{%- set matomo = salt['pillar.get']('matomo', {
    'install_dir': '/var/www/matomo',
    'domain': 'matomo.local',
    'php_fpm_socket': '/run/php/php8.3-fpm.sock',
    'owner': 'www-data',
    'group': 'www-data'
}) %}

{%- set install_dir = matomo.get('install_dir', '/var/www/matomo') %}
{%- set domain = matomo.get('domain', 'matomo.local') %}
{%- set php_socket = matomo.get('php_fpm_socket', '/run/php/php8.3-fpm.sock') %}
{%- set user = matomo.get('owner', 'www-data') %}
{%- set group = matomo.get('group', 'www-data') %}
{%- set env_php = install_dir ~ '/config/config.ini.php' %}
{%- set archive_cron = install_dir ~ '/scripts/archive.php' %}

matomo-packages:
  pkg.installed:
    - pkgs:
      - nginx
      - mariadb-server
      - mariadb-client
      - php8.3-fpm
      - php8.3-cli
      - php8.3-mysql
      - php8.3-gd
      - php8.3-curl
      - php8.3-xml
      - php8.3-zip
      - php8.3-mbstring
      - php8.3-intl
      - php8.3-readline
      - php8.3-bcmath
      - php8.3-opcache
      - unzip
      - git

matomo-user:
  user.present:
    - name: {{ user }}
    - gid: {{ group }}
    - system: True
    - require:
      - pkg: matomo-packages

matomo-group:
  group.present:
    - name: {{ group }}
    - system: True
    - require:
      - pkg: matomo-packages

matomo-install-dir:
  file.directory:
    - name: {{ install_dir }}
    - user: {{ user }}
    - group: {{ group }}
    - mode: 755
    - require:
      - user: matomo-user
      - group: matomo-group

matomo-download:
  archive.extracted:
    - name: {{ install_dir }}
    - source: https://builds.matomo.org/matomo-latest.zip
    - source_hash: https://builds.matomo.org/matomo-latest.zip.sha512
    - archive_format: zip
    - user: {{ user }}
    - group: {{ group }}
    - require:
      - file: matomo-install-dir
      - pkg: matomo-packages
    - if_missing: {{ install_dir }}/matomo

matomo-permissions:
  file.directory:
    - name: {{ install_dir }}
    - user: {{ user }}
    - group: {{ group }}
    - mode: 755
    - recurse:
      - user
      - group
    - require:
      - archive: matomo-download

matomo-nginx-config:
  file.managed:
    - name: /etc/nginx/sites-available/matomo
    - source: salt://optional/analyse/files/matomo-nginx.conf.jinja
    - template: jinja
    - context:
        server_name: {{ domain }}
        install_dir: {{ install_dir }}
        php_socket: {{ php_socket }}
    - require:
      - pkg: matomo-packages

matomo-nginx-enable:
  file.symlink:
    - name: /etc/nginx/sites-enabled/matomo
    - target: /etc/nginx/sites-available/matomo
    - require:
      - file: matomo-nginx-config

matomo-nginx-reload:
  service.running:
    - name: nginx
    - enable: True
    - reload: True
    - watch:
      - file: matomo-nginx-config
      - file: matomo-nginx-enable

matomo-cron:
  cron.present:
    - identifier: MATOMO_ARCHIVE
    - user: {{ user }}
    - minute: '*/30'
    - cmd: 'php {{ archive_cron }} --url="http://{{ domain }}/" > /dev/null 2>&1'
    - require:
      - archive: matomo-download

matomo-summary:
  test.show_notification:
    - text: |
        Matomo 安装已完成。
        访问 http://{{ domain }}/ 完成向导。
        数据目录: {{ install_dir }}
        PHP-FPM 套接字: {{ php_socket }}
