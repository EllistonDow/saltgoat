# Varnish 7.6 安装和配置

# 添加官方 Varnish 7.6 仓库
varnish_package_repo:
  pkgrepo.managed:
    - name: deb https://packagecloud.io/varnishcache/varnish76/ubuntu/ {{ grains['oscodename'] }} main
    - file: /etc/apt/sources.list.d/varnishcache_varnish76.list
    - key_url: https://packagecloud.io/varnishcache/varnish76/gpgkey
    - require_in:
        - pkg: install_varnish

# 安装 / 更新 Varnish（使用官方仓库，默认获取 7.6+）
install_varnish:
  pkg.latest:
    - name: varnish
    - refresh: true
    - require:
      - pkgrepo: varnish_package_repo

# 配置 Varnish
configure_varnish:
  file.managed:
    - name: /etc/varnish/default.vcl
    - source: salt://optional/varnish.vcl
    - require:
      - pkg: install_varnish

# 配置 Varnish 系统服务
configure_varnish_service:
  file.managed:
    - name: /etc/systemd/system/varnish.service
    - source: salt://optional/varnish.service
    - require:
      - file: configure_varnish

# 重新加载 systemd
reload_systemd:
  cmd.run:
    - name: systemctl daemon-reload
    - require:
      - file: configure_varnish_service

# 启动 Varnish 服务
start_varnish:
  service.running:
    - name: varnish
    - enable: true
    - require:
      - cmd: reload_systemd

# 创建防火墙规则
configure_varnish_firewall:
  cmd.run:
    - name: ufw allow 6081
    - require:
      - service: start_varnish

# 测试 Varnish 连接
test_varnish_connection:
  cmd.run:
    - name: varnishstat -1
    - require:
      - service: start_varnish

# 配置 Nginx 反向代理到 Varnish
configure_nginx_varnish:
  file.managed:
    - name: /etc/nginx/snippets/varnish.conf
    - contents: |
        upstream varnish {
            server 127.0.0.1:6081;
        }
        
        location / {
            proxy_pass http://varnish;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    - require:
      - service: start_varnish
