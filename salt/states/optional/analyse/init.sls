{# Matomo 安装默认配置，支持 Pillar 覆盖 #}
{%- macro shell_quote(value) -%}
{{ value | replace("'", "'\"'\"'") }}
{%- endmacro %}
{%- set matomo = salt['pillar.get']('matomo', {
    'install_dir': '/var/www/matomo',
    'domain': 'matomo.local',
    'php_fpm_socket': '/run/php/php8.3-fpm.sock',
    'owner': 'www-data',
    'group': 'www-data',
    'db': {
      'enabled': False,
      'provider': 'existing',
      'name': 'matomo',
      'user': 'matomo',
      'password': '',
      'host': 'localhost',
      'socket': '/var/run/mysqld/mysqld.sock'
    }
}) %}

{%- set install_dir = matomo.get('install_dir', '/var/www/matomo') %}
{%- set domain = matomo.get('domain', 'matomo.local') %}
{%- set php_socket = matomo.get('php_fpm_socket', '/run/php/php8.3-fpm.sock') %}
{%- set user = matomo.get('owner', 'www-data') %}
{%- set group = matomo.get('group', 'www-data') %}
{%- set db = matomo.get('db', {}) %}
{%- set db_enabled = db.get('enabled', False) %}
{%- set db_provider = db.get('provider', 'existing') %}
{%- set db_name = db.get('name', 'matomo') %}
{%- set db_user = db.get('user', 'matomo') %}
{%- set db_password = db.get('password', '') %}
{%- set db_host = db.get('host', 'localhost') %}
{%- set db_socket = db.get('socket', '/var/run/mysqld/mysqld.sock') %}
{%- set db_admin_user = db.get('admin_user', 'root') %}
{%- set default_admin_password = salt['pillar.get']('mysql_password', '') if db_provider == 'mariadb' else '' %}
{%- set db_admin_password = db.get('admin_password', default_admin_password) %}
{%- set mysql_cli = 'mysql' %}
{%- if db_admin_user %}
{%- set mysql_cli = mysql_cli + " -u '" + shell_quote(db_admin_user) + "'" %}
{%- endif %}
{%- if db_admin_password %}
{%- set mysql_cli = mysql_cli + " -p'" + shell_quote(db_admin_password) + "'" %}
{%- endif %}
{%- if db_socket %}
{%- set mysql_cli = mysql_cli + " --socket=" + db_socket %}
{%- else %}
{%- set mysql_cli = mysql_cli + " -h '" + shell_quote(db_host) + "'" %}
{%- endif %}
{%- set env_php = install_dir ~ '/config/config.ini.php' %}
{%- set archive_cron = install_dir ~ '/scripts/archive.php' %}

{%- set base_packages = [
  'nginx',
  'php8.3-fpm',
  'php8.3-cli',
  'php8.3-mysql',
  'php8.3-gd',
  'php8.3-curl',
  'php8.3-xml',
  'php8.3-zip',
  'php8.3-mbstring',
  'php8.3-intl',
  'php8.3-readline',
  'php8.3-bcmath',
  'php8.3-opcache',
  'unzip',
  'git',
  'python3-pymysql'
] %}

matomo-packages:
  pkg.installed:
    - pkgs: {{ base_packages }}

matomo-download-archive:
  cmd.run:
    - name: curl -fsSL https://builds.matomo.org/matomo-latest.zip -o /tmp/matomo-latest.zip
    - creates: /tmp/matomo-latest.zip
    - require:
      - pkg: matomo-packages

{% if db_enabled and db_provider == 'mariadb' %}
matomo-mariadb-packages:
  pkg.installed:
    - pkgs:
      - mariadb-server
      - mariadb-client
    - require:
      - pkg: matomo-packages
{% endif %}

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
    - source: /tmp/matomo-latest.zip
    - source_hash: False
    - archive_format: zip
    - enforce_toplevel: False
    - if_missing: {{ install_dir }}/matomo
    - user: {{ user }}
    - group: {{ group }}
    - require:
      - file: matomo-install-dir
      - pkg: matomo-packages
      - cmd: matomo-download-archive

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

{% if db_enabled %}
{% if db_provider == 'mariadb' %}
matomo-mysql-service:
  service.running:
    - name: mariadb
    - enable: True
    - require:
      - pkg: matomo-mariadb-packages
{% endif %}

matomo-db:
  mysql_database.present:
    - name: {{ db_name }}
    {% if db_socket %}
    - connection_unix_socket: {{ db_socket }}
    {% else %}
    - connection_host: {{ db_host }}
    {% endif %}
    {% if db_admin_user %}
    - connection_user: {{ db_admin_user }}
    {% endif %}
    {% if db_admin_password %}
    - connection_pass: {{ db_admin_password }}
    {% endif %}
    {% if db_provider == 'mariadb' %}
    - require:
      - service: matomo-mysql-service
    {% else %}
    - require:
      - pkg: matomo-packages
    {% endif %}

{%- set escaped_password = db_password.replace("'", "''") %}

matomo-db-user:
  cmd.run:
    - name: |
        {{ mysql_cli }} -e "CREATE USER IF NOT EXISTS '{{ db_user }}'@'{{ db_host }}' IDENTIFIED BY '{{ escaped_password }}';"
    - require:
      - mysql_database: matomo-db

matomo-db-grants:
  cmd.run:
    - name: |
        {{ mysql_cli }} -e "GRANT ALL PRIVILEGES ON {{ db_name }}.* TO '{{ db_user }}'@'{{ db_host }}'; FLUSH PRIVILEGES;"
    - require:
      - cmd: matomo-db-user
{% endif %}

matomo-cron:
  cron.present:
    - name: 'php {{ archive_cron }} --url="http://{{ domain }}/" > /dev/null 2>&1'
    - user: {{ user }}
    - minute: '*/30'
    - require:
      - archive: matomo-download

matomo-summary:
  test.show_notification:
    - text: |
        Matomo 安装已完成。
        访问 http://{{ domain }}/ 完成向导。
        数据目录: {{ install_dir }}
        PHP-FPM 套接字: {{ php_socket }}
        {% if db_enabled %}
        数据库: {{ db_name }} (provider={{ db_provider }})
        用户: {{ db_user }}@{{ db_host }}
        {% else %}
        未启用数据库自动配置。如需启用，请在 Pillar 中设置 matomo:db.enabled: true。
        {% endif %}
