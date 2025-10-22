# PHP 8.3 安装和配置


# 添加 PHP 仓库
add_php_repository:
  cmd.run:
    - name: |
        add-apt-repository ppa:ondrej/php -y
        apt update
    - unless: apt-cache policy php8.3 | grep -q ondrej

# 安装 PHP 8.3
install_php:
  pkg.installed:
    - name: php8.3
    - require:
      - cmd: add_php_repository

# 安装 PHP-FPM
install_php_fpm:
  pkg.installed:
    - name: php8.3-fpm
    - require:
      - pkg: install_php

# 安装 PHP 扩展
install_php_extensions:
  pkg.installed:
    - names:
      - php8.3-bcmath
      - php8.3-curl
      - php8.3-gd
      - php8.3-intl
      - php8.3-mbstring
      - php8.3-mysql
      - php8.3-opcache
      - php8.3-soap
      - php8.3-xml
      - php8.3-xsl
      - php8.3-zip
    - require:
      - pkg: install_php

# 配置 PHP
configure_php:
  file.managed:
    - name: /etc/php/8.3/fpm/php.ini
    - source: salt://core/php.ini
    - require:
      - pkg: install_php_fpm

# 配置 PHP-FPM
configure_php_fpm:
  file.managed:
    - name: /etc/php/8.3/fpm/pool.d/www.conf
    - source: salt://core/php-fpm.conf
    - require:
      - pkg: install_php_fpm

# 启动 PHP-FPM 服务
start_php_fpm:
  service.running:
    - name: php8.3-fpm
    - enable: true
    - require:
      - file: configure_php
      - file: configure_php_fpm

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
            fastcgi_pass unix:/run/php/php8.3-fpm.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        }
    - require:
      - service: start_php_fpm
      - file: create_nginx_snippets_dir
