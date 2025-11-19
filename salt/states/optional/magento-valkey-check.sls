# Magento Valkey 配置检测（Salt 原生）
#
# 通过 Salt 状态验证指定 Magento 站点的 Valkey/Redis 配置是否正确：
# - env.php 是否存在且可读
# - 缓存与会话配置是否指向 Redis 后端
# - 主机/端口/数据库/前缀/密码是否完整
# - 指定数据库能否成功 PING
# - env.php 所有者/权限是否符合预期
#
# 需要通过 pillar 传入：
#   site_name        （必填）
#   site_path        （可选，默认 /var/www/<site_name>）
#   expected_owner   （可选，默认 www-data）
#   expected_group   （可选，默认 www-data）
#   expected_perms   （可选，留空则不校验具体权限）
#   valkey_conf      （可选，用于补充信息）

{% set site_name = pillar.get('site_name') %}
{% set site_path = pillar.get('site_path', '/var/www/{0}'.format(site_name) if site_name else None) %}
{% set expected_owner = pillar.get('expected_owner', 'www-data') %}
{% set expected_group = pillar.get('expected_group', 'www-data') %}
{% set expected_perms = pillar.get('expected_perms', '') %}
{% set valkey_conf = pillar.get('valkey_conf', '/etc/valkey/valkey.conf') %}

{% if not site_name %}
magento_valkey_check_missing_site_name:
  test.fail_without_changes:
    - comment: "pillar['site_name'] 未提供，无法执行 Magento Valkey 检测。"

{% elif not site_path %}
magento_valkey_check_missing_site_path:
  test.fail_without_changes:
    - comment: "无法推导站点路径，请在 pillar 中提供 site_path。"

{% else %}

{% set env_file = site_path ~ '/app/etc/env.php' %}
{% set site_exists = salt['file.directory_exists'](site_path) %}
{% set env_exists = salt['file.file_exists'](env_file) %}

{% if not site_exists %}
magento_valkey_check_site_missing:
  test.fail_without_changes:
    - comment: "站点目录 {{ site_path }} 不存在。"

{% elif not env_exists %}
magento_valkey_check_env_missing:
  test.fail_without_changes:
    - comment: "未找到 {{ env_file }}，请确认 Magento 已正确安装。"

{% else %}

magento_valkey_check_script_dir:
  file.directory:
    - name: /usr/local/lib/saltgoat
    - user: root
    - group: root
    - mode: 755

magento_valkey_check_script:
  file.managed:
    - name: /usr/local/lib/saltgoat/magento-valkey-check.php
    - source: salt://optional/magento-valkey-check/valkey_check.php.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - require:
      - file: magento_valkey_check_script_dir

magento_valkey_check:
  cmd.run:
    - name: php /usr/local/lib/saltgoat/magento-valkey-check.php
    - cwd: {{ site_path }}
    - env:
        SITE_NAME: {{ site_name }}
        VALKEY_CONF: {{ valkey_conf }}
{% if expected_owner %}
        EXPECTED_OWNER: {{ expected_owner }}
{% endif %}
{% if expected_group %}
        EXPECTED_GROUP: {{ expected_group }}
{% endif %}
{% if expected_perms %}
        EXPECTED_PERMS: {{ expected_perms }}
{% endif %}
    - require:
      - file: magento_valkey_check_script


{% endif %}
{% endif %}
