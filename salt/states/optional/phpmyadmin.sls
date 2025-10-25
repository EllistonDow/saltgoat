# phpMyAdmin 安装和配置


# 安装 phpMyAdmin
install_phpmyadmin:
  pkg.installed:
    - name: phpmyadmin

# 配置 phpMyAdmin
configure_phpmyadmin:
  file.managed:
    - name: /etc/phpmyadmin/config.inc.php
    - source: salt://optional/phpmyadmin.conf
    - require:
      - pkg: install_phpmyadmin

# 创建 phpMyAdmin 配置目录
create_phpmyadmin_config_dir:
  file.directory:
    - name: /etc/phpmyadmin/conf.d
    - user: root
    - group: root
    - mode: 755
    - require:
      - pkg: install_phpmyadmin

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
            server_name _;
            root /usr/share/phpmyadmin;
            index index.php;

            location / {
                try_files $uri $uri/ =404;
            }

            location ~ \.php$ {
                fastcgi_index index.php;
                fastcgi_pass unix:/run/php/php8.3-fpm.sock;
                fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
                include fastcgi_params;
            }

            location ~ /\.ht {
                deny all;
            }
        }
    - require:
      - pkg: install_phpmyadmin

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
      - pkg: install_phpmyadmin
