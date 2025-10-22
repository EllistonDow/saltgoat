# RabbitMQ 4.1.4 安装和配置

# 下载 RabbitMQ 4.1.4
download_rabbitmq:
  cmd.run:
    - name: |
        cd /tmp
        wget -O rabbitmq-server-generic-unix-4.1.4.tar.xz https://github.com/rabbitmq/rabbitmq-server/releases/download/v4.1.4/rabbitmq-server-generic-unix-4.1.4.tar.xz
        tar -xf rabbitmq-server-generic-unix-4.1.4.tar.xz
    - creates: /tmp/rabbitmq_server-4.1.4

# 安装 RabbitMQ 4.1.4
install_rabbitmq:
  cmd.run:
    - name: |
        sudo mv /tmp/rabbitmq_server-4.1.4 /opt/rabbitmq
        sudo ln -sf /opt/rabbitmq/sbin/rabbitmq-server /usr/local/bin/rabbitmq-server
        sudo ln -sf /opt/rabbitmq/sbin/rabbitmqctl /usr/local/bin/rabbitmqctl
        sudo ln -sf /opt/rabbitmq/sbin/rabbitmq-plugins /usr/local/bin/rabbitmq-plugins
        sudo ln -sf /opt/rabbitmq/sbin/rabbitmq-env /usr/local/bin/rabbitmq-env
    - require:
      - cmd: download_rabbitmq

# 创建 RabbitMQ 用户和目录
create_rabbitmq_user:
  user.present:
    - name: rabbitmq
    - system: true
    - shell: /bin/false
    - home: /var/lib/rabbitmq
    - createhome: true

create_rabbitmq_dirs:
  cmd.run:
    - name: |
        sudo mkdir -p /var/lib/rabbitmq /var/log/rabbitmq /etc/rabbitmq /opt/rabbitmq/var/lib/rabbitmq/mnesia
        sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq /var/log/rabbitmq /etc/rabbitmq /opt/rabbitmq/var
    - require:
      - user: create_rabbitmq_user

# 创建 RabbitMQ systemd 服务
create_rabbitmq_service:
  file.managed:
    - name: /etc/systemd/system/rabbitmq.service
    - source: salt://optional/rabbitmq.service
    - require:
      - cmd: create_rabbitmq_dirs

# 修复 Erlang cookie 问题
fix_erlang_cookie:
  cmd.run:
    - name: |
        sudo cp /var/lib/rabbitmq/.erlang.cookie /root/.erlang.cookie
        sudo chmod 400 /root/.erlang.cookie
    - require:
      - cmd: create_rabbitmq_dirs

# 启动 RabbitMQ 服务
start_rabbitmq:
  service.running:
    - name: rabbitmq
    - enable: true
    - reload: true
    - require:
      - file: create_rabbitmq_service
      - cmd: fix_erlang_cookie

# 等待 RabbitMQ 启动
wait_for_rabbitmq:
  cmd.run:
    - name: sleep 10
    - require:
      - service: start_rabbitmq

# 启用 RabbitMQ 管理插件
enable_rabbitmq_management:
  cmd.run:
    - name: rabbitmq-plugins enable rabbitmq_management
    - require:
      - cmd: wait_for_rabbitmq

{# 从 Pillar 读取 RabbitMQ 密码，默认回退 #}
{% set rabbitmq_pass = pillar.get('rabbitmq_password', 'SaltGoat2024!') %}

# 创建管理员用户
create_rabbitmq_admin:
  cmd.run:
    - name: |
        rabbitmqctl add_user admin {{ rabbitmq_pass }}
        rabbitmqctl set_user_tags admin administrator
        rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"
    - require:
      - cmd: enable_rabbitmq_management

# 重启 RabbitMQ 服务
restart_rabbitmq:
  service.running:
    - name: rabbitmq
    - enable: true
    - reload: true
    - require:
      - cmd: create_rabbitmq_admin

# 创建防火墙规则
configure_rabbitmq_firewall:
  cmd.run:
    - name: |
        ufw allow 5672
        ufw allow 15672
    - require:
      - service: restart_rabbitmq

# 测试 RabbitMQ 连接
test_rabbitmq_connection:
  cmd.run:
    - name: rabbitmqctl status
    - require:
      - service: restart_rabbitmq
