# phpMyAdmin 安装和配置（使用官方压缩包，避免触发 php8.4 依赖）

{% set php_version = salt['pillar.get']('saltgoat:versions:php', '8.3') %}
{% set php_pkg = 'php{}'.format(php_version) %}
{% set php_extensions = [
  php_pkg + '-mbstring',
  php_pkg + '-xml',
  php_pkg + '-mysql',
  php_pkg + '-zip',
  php_pkg + '-gd'
] %}
{% set phpmyadmin_version = salt['pillar.get']('saltgoat:versions:phpmyadmin', '5.2.1') %}
{% set phpmyadmin_archive = 'phpMyAdmin-{}-all-languages'.format(phpmyadmin_version) %}
{% set phpmyadmin_source = 'https://files.phpmyadmin.net/phpMyAdmin/{}/{}.tar.gz'.format(
  phpmyadmin_version,
  phpmyadmin_archive
) %}
{% set phpmyadmin_hash_map = {
  '5.2.1': '61c763f209817d1b5d96a4c0eab65b4e36bce744f78e73bef3bebd1c07481c46'
} %}
{% set phpmyadmin_hash = phpmyadmin_hash_map.get(phpmyadmin_version) %}
{% set phpmyadmin_cache_dir = '/var/cache/saltgoat/phpmyadmin' %}
{% set phpmyadmin_tarball = phpmyadmin_cache_dir + '/' + phpmyadmin_archive + '.tar.gz' %}

{% if not phpmyadmin_hash %}
phpmyadmin_hash_missing:
  test.fail_without_changes:
    - comment: "phpMyAdmin 版本 {{ phpmyadmin_version }} 缺少哈希，请更新 optional/phpmyadmin.sls 中的 phpmyadmin_hash_map"
{% else %}

# 确保不会重新安装发行版自带的 phpMyAdmin 或 php8.4 元包
remove_conflicting_php_packages:
  pkg.purged:
    - pkgs:
      - phpmyadmin
      - php-bz2
      - php-mysql
      - php-mcrypt
      - php8.4-cli
      - php8.4-common
      - php8.4-mysql
      - php8.4-readline
      - php8.4-opcache
      - php8.4-phpdbg
      - php8.4-bz2
      - php8.4-mcrypt
    - refresh: false

# 确保 CLI 默认使用锁定的 PHP 主版本
set_php_cli_alternative:
  cmd.run:
    - name: "update-alternatives --set php /usr/bin/php{{ php_version }}"
    - unless: "update-alternatives --query php | grep -q 'Value: /usr/bin/php{{ php_version }}'"
    - require:
      - pkg: remove_conflicting_php_packages

# phpMyAdmin 缓存目录
phpmyadmin_cache_dir:
  file.directory:
    - name: {{ phpmyadmin_cache_dir }}
    - user: root
    - group: root
    - mode: 0755
    - makedirs: True

# 下载 phpMyAdmin Tarball（带哈希校验）
download_phpmyadmin_tarball:
  cmd.run:
    - name: |
        set -euo pipefail
        tmp_file="$(mktemp {{ phpmyadmin_cache_dir }}/phpmyadmin.XXXXXX)"
        curl -fL "{{ phpmyadmin_source }}" -o "$tmp_file"
        echo "{{ phpmyadmin_hash }}  $tmp_file" | sha256sum -c -
        mv "$tmp_file" "{{ phpmyadmin_tarball }}"
    - unless: "test -f {{ phpmyadmin_tarball }} && echo '{{ phpmyadmin_hash }}  {{ phpmyadmin_tarball }}' | sha256sum -c - >/dev/null 2>&1"
    - require:
      - file: phpmyadmin_cache_dir

# 确认 phpMyAdmin 所需扩展存在
phpmyadmin_prereq_packages:
  pkg.installed:
    - pkgs:
{%- for pkg in php_extensions %}
      - {{ pkg }}
{%- endfor %}

    - refresh: false
    - require:
      - cmd: set_php_cli_alternative

# 安装 phpMyAdmin（提取官方 tarball）
deploy_phpmyadmin:
  archive.extracted:
    - name: /usr/share/phpmyadmin
    - source: {{ phpmyadmin_tarball }}
    - archive_format: tar
    - enforce_toplevel: False
    - options: '--strip-components=1'
    - user: root
    - group: root
    - mode: 0755
    - clean: True
    - require:
      - cmd: download_phpmyadmin_tarball
      - pkg: phpmyadmin_prereq_packages

# 创建 phpMyAdmin 配置目录（根路径）
create_phpmyadmin_dir:
  file.directory:
    - name: /etc/phpmyadmin
    - user: root
    - group: root
    - mode: 755
    - require:
      - archive: deploy_phpmyadmin

# 配置 phpMyAdmin
configure_phpmyadmin:
  file.managed:
    - name: /etc/phpmyadmin/config.inc.php
    - source: salt://optional/phpmyadmin.conf
    - require:
      - file: create_phpmyadmin_dir

# 创建 phpMyAdmin 配置目录
create_phpmyadmin_config_dir:
  file.directory:
    - name: /etc/phpmyadmin/conf.d
    - user: root
    - group: root
    - mode: 755
    - require:
      - file: create_phpmyadmin_dir

# 配置 phpMyAdmin 安全设置
configure_phpmyadmin_security:
  file.managed:
    - name: /etc/phpmyadmin/conf.d/security.conf
    - contents: |
        <?php
        $cfg['blowfish_secret'] = '{{ salt['random.get_str'](32) }}';
        $cfg['ForceSSL'] = true;
        $cfg['CheckConfigurationPermissions'] = false;
        $cfg['TempDir'] = '/tmp';
        $cfg['UploadDir'] = '';
        $cfg['SaveDir'] = '';
        $cfg['MaxRows'] = 50;
        $cfg['ProtectBinary'] = 'blob';
        $cfg['DefaultCharset'] = 'utf8';
        $cfg['DefaultConnectionCollation'] = 'utf8_general_ci';
        $cfg['RecodingEngine'] = 'auto';
        $cfg['IconvExtraParams'] = '';
        $cfg['AvailableCharsets'] = array(
            'iso-8859-1', 'iso-8859-2', 'iso-8859-3', 'iso-8859-4',
            'iso-8859-5', 'iso-8859-6', 'iso-8859-7', 'iso-8859-8',
            'iso-8859-9', 'iso-8859-10', 'iso-8859-11', 'iso-8859-12',
            'iso-8859-13', 'iso-8859-14', 'iso-8859-15', 'utf-8',
            'big5', 'gb2312', 'gbk', 'gb18030', 'euc-jp', 'euc-kr',
            'euc-tw', 'koi8-r', 'koi8-u', 'tis-620', 'windows-1251',
            'windows-1252', 'windows-1257'
        );
        ?>
    - require:
      - file: create_phpmyadmin_config_dir

# 创建 Nginx phpMyAdmin 配置
configure_nginx_phpmyadmin:
  file.managed:
    - name: /etc/nginx/sites-available/phpmyadmin
    - contents: |
        server {
            listen 80;
            server_name {{ salt['pillar.get']('phpmyadmin:server_name', 'phpmyadmin.localhost') }};
            root /usr/share/phpmyadmin;
            index index.php;

            location / {
                try_files $uri $uri/ =404;
            }

            location ~ \.php$ {
                fastcgi_index index.php;
                fastcgi_pass unix:/run/php/php{{ php_version }}-fpm.sock;
                fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
                include fastcgi_params;
            }

            location ~ /\.ht {
                deny all;
            }
        }
    - require:
      - archive: deploy_phpmyadmin

# 启用 phpMyAdmin 站点
enable_phpmyadmin_site:
  file.symlink:
    - name: /etc/nginx/sites-enabled/phpmyadmin
    - target: /etc/nginx/sites-available/phpmyadmin
    - require:
      - file: configure_nginx_phpmyadmin

# 测试 Nginx 配置
test_nginx_phpmyadmin_config:
  cmd.run:
    - name: /usr/sbin/nginx -t -c /etc/nginx/nginx.conf
    - require:
      - file: enable_phpmyadmin_site

# 重启 Nginx
restart_nginx_phpmyadmin:
  service.running:
    - name: nginx
    - enable: true
    - reload: true
    - require:
      - cmd: test_nginx_phpmyadmin_config

# 设置 phpMyAdmin 权限
set_phpmyadmin_permissions:
  cmd.run:
    - name: |
        chown -R www-data:www-data /usr/share/phpmyadmin
        chmod -R 755 /usr/share/phpmyadmin
    - require:
      - archive: deploy_phpmyadmin

{% endif %}
