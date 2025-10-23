# Nginx 1.29.1 + ModSecurity 源码编译安装

# 安装编译依赖
install_build_dependencies:
  pkg.installed:
    - names:
      - build-essential
      - libpcre3-dev
      - libpcre2-dev
      - libssl-dev
      - libtool
      - autoconf
      - automake
      - flex
      - bison
      - curl
      - libcurl4-openssl-dev
      - libxml2-dev
      - libyajl-dev
      - doxygen
      - zlib1g-dev
      - pkg-config
      - liblmdb-dev
      - libmaxminddb-dev
      - libgeoip-dev
      - git

# 下载并编译 ModSecurity
compile_modsecurity:
  cmd.run:
    - name: |
        cd /usr/src
        if [ ! -d "ModSecurity" ]; then
          git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity
        fi
        cd ModSecurity
        git submodule update --init --recursive
        ./build.sh
        ./configure --prefix=/usr/local/modsecurity
        make -j$(nproc)
        make install
    - require:
      - pkg: install_build_dependencies
    - unless: test -f /usr/local/modsecurity/lib/libmodsecurity.so

# 下载 Nginx 1.29.1 源码
download_nginx_source:
  cmd.run:
    - name: |
        cd /usr/src
        if [ ! -d "nginx-1.29.1" ]; then
          wget http://nginx.org/download/nginx-1.29.1.tar.gz
          tar -zxvf nginx-1.29.1.tar.gz
        fi
    - require:
      - pkg: install_build_dependencies

# 下载 ModSecurity-Nginx 模块
download_modsecurity_nginx_module:
  cmd.run:
    - name: |
        cd /usr/src
        if [ ! -d "ModSecurity-nginx" ]; then
          git clone https://github.com/owasp-modsecurity/ModSecurity-nginx.git
        fi
    - require:
      - cmd: download_nginx_source

# 编译安装 Nginx 1.29.1 + ModSecurity
compile_nginx:
  cmd.run:
    - name: |
        cd /usr/src/nginx-1.29.1
        ./configure --prefix=/etc/nginx \
            --with-http_ssl_module \
            --with-http_realip_module \
            --with-http_addition_module \
            --with-http_sub_module \
            --with-http_dav_module \
            --with-http_flv_module \
            --with-http_mp4_module \
            --with-http_gunzip_module \
            --with-http_gzip_static_module \
            --with-http_random_index_module \
            --with-http_secure_link_module \
            --with-http_stub_status_module \
            --with-http_auth_request_module \
            --with-threads \
            --with-stream \
            --with-stream_ssl_module \
            --with-stream_ssl_preread_module \
            --with-stream_realip_module \
            --with-stream_geoip_module \
            --with-stream_geoip_module=dynamic \
            --with-http_slice_module \
            --with-file-aio \
            --with-http_v2_module \
            --add-module=../ModSecurity-nginx
        make -j$(nproc)
        make install
    - require:
      - cmd: compile_modsecurity
      - cmd: download_modsecurity_nginx_module
    - unless: test -f /etc/nginx/sbin/nginx

# 创建 ModSecurity 配置文件
create_modsecurity_config:
  file.managed:
    - name: /etc/nginx/conf/modsecurity.conf
    - contents: |
        # ModSecurity 基础配置
        SecRuleEngine On
        SecRequestBodyAccess On
        SecResponseBodyAccess On
        SecResponseBodyMimeType text/plain text/html text/xml
        SecResponseBodyLimit 524288
        SecTmpDir /tmp/
        SecDataDir /tmp/
        SecUploadDir /tmp/
        SecUploadKeepFiles Off
        SecCollectionTimeout 600
        SecDefaultAction "phase:1,log,auditlog,pass"
        SecDefaultAction "phase:2,log,auditlog,pass"
    - require:
      - cmd: compile_nginx

# 下载 OWASP Core Rule Set
download_owasp_crs:
  cmd.run:
    - name: |
        cd /etc/nginx/conf
        if [ ! -d "coreruleset" ]; then
          git clone https://github.com/coreruleset/coreruleset.git
        fi
        cd coreruleset
        cp crs-setup.conf.example crs-setup.conf
    - require:
      - cmd: compile_nginx

# 配置 Nginx
configure_nginx:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - source: salt://core/nginx.conf
    - require:
      - cmd: compile_nginx
      - file: create_modsecurity_config
      - cmd: download_owasp_crs

# 创建网站目录
create_web_directories:
  file.directory:
    - names:
      - /var/www/html
      - /var/www/html/public
      - /var/log/nginx
      - /etc/nginx/sites-available
      - /etc/nginx/sites-enabled
    - user: www-data
    - group: www-data
    - mode: 755
    - makedirs: true

# 创建默认网站配置
create_default_site:
  file.managed:
    - name: /etc/nginx/sites-available/default
    - source: salt://core/default-site.conf
    - require:
      - cmd: compile_nginx
      - file: create_web_directories

# 启用默认网站
enable_default_site:
  file.symlink:
    - name: /etc/nginx/sites-enabled/default
    - target: /etc/nginx/sites-available/default
    - require:
      - file: create_default_site

# 创建 Nginx 系统服务
create_nginx_service:
  file.managed:
    - name: /etc/systemd/system/nginx.service
    - contents: |
        [Unit]
        Description=The nginx HTTP and reverse proxy server
        After=network.target remote-fs.target nss-lookup.target

        [Service]
        Type=forking
        PIDFile=/etc/nginx/logs/nginx.pid
        ExecStartPre=/etc/nginx/sbin/nginx -t -c /etc/nginx/nginx.conf
        ExecStart=/etc/nginx/sbin/nginx
        ExecReload=/bin/kill -s HUP $MAINPID
        KillSignal=SIGQUIT
        TimeoutStopSec=5
        KillMode=process
        PrivateTmp=true

        [Install]
        WantedBy=multi-user.target
    - require:
      - cmd: compile_nginx

# 重新加载 systemd
reload_systemd:
  cmd.run:
    - name: systemctl daemon-reload
    - require:
      - file: create_nginx_service

# 创建 Nginx 命令符号链接
create_nginx_symlink:
  file.symlink:
    - name: /usr/sbin/nginx
    - target: /etc/nginx/sbin/nginx
    - require:
      - cmd: compile_nginx

# 创建 Nginx 配置文件路径符号链接（确保 nginx -t 命令正常工作）
create_nginx_conf_symlink:
  file.symlink:
    - name: /etc/nginx/conf/nginx.conf
    - target: /etc/nginx/nginx.conf
    - require:
      - file: configure_nginx

# 测试 Nginx 配置
test_nginx_config:
  cmd.run:
    - name: nginx -t
    - require:
      - file: configure_nginx
      - file: enable_default_site
      - file: create_nginx_conf_symlink

# 启动 Nginx 服务
start_nginx:
  service.running:
    - name: nginx
    - enable: true
    - require:
      - cmd: test_nginx_config
      - cmd: reload_systemd

# 创建防火墙规则
configure_nginx_firewall:
  cmd.run:
    - name: |
        ufw allow 80/tcp
        ufw allow 443/tcp
    - require:
      - service: start_nginx
