# Varnish 7.6 安装和配置

# 安装 Varnish
install_varnish:
  pkg.installed:
    - name: varnish

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
    - name: /usr/local/nginx/conf/snippets/varnish.conf
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
