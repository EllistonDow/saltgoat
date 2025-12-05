{% set php_version = salt['pillar.get']('saltgoat:versions:php', '8.3') %}
{% set php_pkg = 'php{}'.format(php_version) %}
{% set php_fpm_pkg = php_pkg ~ '-fpm' %}
{% set php_etc_dir = '/etc/php/{}/fpm'.format(php_version) %}

# PHP 安装和配置（锁定主版本）

include:
  - core.php-fpm-pools


# 添加 PHP 仓库
add_php_repository:
  cmd.run:
    - name: |
        add-apt-repository ppa:ondrej/php -y
        apt update
    - unless: apt-cache policy {{ php_pkg }} | grep -q ondrej

# 安装 PHP
install_php:
  pkg.installed:
    - name: {{ php_pkg }}
    - require:
      - cmd: add_php_repository

# 安装 PHP-FPM
install_php_fpm:
  pkg.installed:
    - name: {{ php_fpm_pkg }}
    - require:
      - pkg: install_php

# 安装 PHP 扩展
install_php_extensions:
  pkg.installed:
    - names:
      - {{ php_pkg }}-bcmath
      - {{ php_pkg }}-curl
      - {{ php_pkg }}-gd
      - {{ php_pkg }}-intl
      - {{ php_pkg }}-mbstring
      - {{ php_pkg }}-mysql
      - {{ php_pkg }}-opcache
      - {{ php_pkg }}-soap
      - {{ php_pkg }}-xml
      - {{ php_pkg }}-xsl
      - {{ php_pkg }}-zip
    - require:
      - pkg: install_php

# 配置 PHP
configure_php:
  file.managed:
    - name: {{ php_etc_dir }}/php.ini
    - source: salt://core/php.ini
    - require:
      - pkg: install_php_fpm

# 配置 PHP CLI
configure_php_cli:
  file.managed:
    - name: /etc/php/{{ php_version }}/cli/php.ini
    - source: salt://core/php.ini
    - require:
      - pkg: install_php

# 配置 PHP Apache2 (防止 sessionclean 误读)
configure_php_apache2:
  file.managed:
    - name: /etc/php/{{ php_version }}/apache2/php.ini
    - source: salt://core/php.ini
    - onlyif: test -d /etc/php/{{ php_version }}/apache2
    - require:
      - pkg: install_php

# 配置 PHP-FPM
configure_php_fpm:
  file.managed:
    - name: {{ php_etc_dir }}/pool.d/www.conf
    - source: salt://core/php-fpm.conf
    - template: jinja
    - require:
      - pkg: install_php_fpm

php_fpm_override_dir:
  file.directory:
    - name: /etc/systemd/system/{{ php_fpm_pkg }}.service.d
    - user: root
    - group: root
    - mode: 0755

php_fpm_override_conf:
  file.managed:
    - name: /etc/systemd/system/{{ php_fpm_pkg }}.service.d/override.conf
    - user: root
    - group: root
    - mode: 0644
    - contents: |
        [Service]
        Restart=on-failure
        RestartSec=3s
        MemoryMax=24G
        LimitNOFILE=65536
    - require:
      - file: php_fpm_override_dir
    - watch_in:
      - service: start_php_fpm

php_fpm_override_reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: php_fpm_override_conf

# 启动 PHP-FPM 服务
start_php_fpm:
  service.running:
    - name: {{ php_fpm_pkg }}
    - enable: true
    - require:
      - file: configure_php
      - file: configure_php_fpm
      - file: php_fpm_override_conf
      - cmd: php_fpm_override_reload

# 创建 PHP 测试文件
create_php_test_file:
  file.managed:
    - name: /var/www/html/info.php
    - contents: |
        <?php
        phpinfo();
        ?>
    - user: www-data
    - group: www-data
    - mode: 644
    - require:
      - service: start_php_fpm

# 创建 nginx snippets 目录
create_nginx_snippets_dir:
  file.directory:
    - name: /etc/nginx/snippets
    - user: www-data
    - group: www-data
    - mode: 755
    - makedirs: true

# 配置 Nginx PHP 支持
configure_nginx_php:
  file.managed:
    - name: /etc/nginx/snippets/php.conf
    - contents: |
        location ~ \.php$ {
            include fastcgi_params;
            fastcgi_pass unix:/run/php/php{{ php_version }}-fpm.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        }
    - require:
      - service: start_php_fpm
      - file: create_nginx_snippets_dir
