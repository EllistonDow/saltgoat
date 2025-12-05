# Webmin 安装和配置

# 下载并安装 Webmin
install_webmin:
  cmd.run:
    - name: |
        wget http://www.webmin.com/download/deb/webmin-current.deb -O /tmp/webmin.deb
        dpkg --install /tmp/webmin.deb || apt-get -f install -y
        rm -f /tmp/webmin.deb
    - creates: /usr/share/webmin

# 配置 Webmin（覆盖官方默认配置，包含 SSL 等加固选项）
configure_webmin:
  file.managed:
    - name: /etc/webmin/miniserv.conf
    - source: salt://optional/webmin.conf
    - require:
      - cmd: install_webmin

{# 从 Pillar 读取 Webmin 密码，默认回退 #}
{% set webmin_pass = salt['pillar.get']('auth:webmin:password', pillar.get('webmin_password', 'SaltGoat2024!')) %}

# 设置 Webmin 密码
set_webmin_password:
  cmd.run:
    - name: |
        echo "root:{{ webmin_pass }}" | chpasswd
        /usr/share/webmin/changepass.pl /etc/webmin root {{ webmin_pass }}
    - require:
      - file: configure_webmin

# 启动 Webmin 服务
start_webmin:
  service.running:
    - name: webmin
    - enable: true
    - require:
      - cmd: set_webmin_password

# 创建防火墙规则
configure_webmin_firewall:
  cmd.run:
    - name: ufw allow 10000
    - require:
      - service: start_webmin

# 测试 Webmin 连接
test_webmin_connection:
  cmd.run:
    - name: curl -ks https://localhost:10000/ | grep -qi "Webmin" && echo "Webmin is running"
    - require:
      - service: start_webmin
