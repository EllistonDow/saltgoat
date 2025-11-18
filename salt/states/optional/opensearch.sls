{# OpenSearch 固定版本，默认 2.19.4，可通过 pillar saltgoat:versions:opensearch 覆盖 #}
{% set opensearch_version = salt['pillar.get']('saltgoat:versions:opensearch', '2.19.4') %}

# 添加 OpenSearch 仓库
add_opensearch_repository:
  cmd.run:
    - name: |
        curl -fsSL https://artifacts.opensearch.org/publickeys/opensearch.pgp | gpg --dearmor -o /usr/share/keyrings/opensearch-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring.gpg] https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/apt stable main" > /etc/apt/sources.list.d/opensearch.list
    - unless: test -f /usr/share/keyrings/opensearch-keyring.gpg

# 更新包列表
update_package_list:
  cmd.run:
    - name: apt update
    - require:
      - cmd: add_opensearch_repository

# 安装 Java (OpenSearch 依赖)
install_java:
  pkg.installed:
    - name: openjdk-11-jdk

# 安装 OpenSearch
install_opensearch:
  pkg.installed:
    - name: opensearch
    - version: {{ opensearch_version }}
    - require:
      - cmd: update_package_list
      - pkg: install_java

# 配置 OpenSearch
configure_opensearch:
  file.managed:
    - name: /etc/opensearch/opensearch.yml
    - source: salt://optional/opensearch.yml
    - require:
      - pkg: install_opensearch

# 配置 JVM 设置
configure_opensearch_jvm:
  file.managed:
    - name: /etc/opensearch/jvm.options
    - source: salt://optional/opensearch-jvm.options
    - require:
      - pkg: install_opensearch

# 设置 OpenSearch 权限
set_opensearch_permissions:
  cmd.run:
    - name: |
        chown -R opensearch:opensearch /etc/opensearch
        chown -R opensearch:opensearch /var/lib/opensearch
        chown -R opensearch:opensearch /var/log/opensearch
    - require:
      - file: configure_opensearch
      - file: configure_opensearch_jvm

# 启动 OpenSearch 服务
start_opensearch:
  service.running:
    - name: opensearch
    - enable: true
    - require:
      - cmd: set_opensearch_permissions

# 创建防火墙规则
configure_opensearch_firewall:
  cmd.run:
    - name: ufw allow 9200
    - require:
      - service: start_opensearch

# 等待 OpenSearch 启动
wait_for_opensearch:
  cmd.run:
    - name: sleep 30
    - require:
      - service: start_opensearch

# 测试 OpenSearch 连接
test_opensearch_connection:
  cmd.run:
    - name: curl -X GET "localhost:9200/"
    - require:
      - cmd: wait_for_opensearch
