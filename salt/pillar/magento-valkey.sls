# SaltGoat Magento Valkey Pillar 样例
# 复制本文件为 `salt/pillar/magento-valkey.sls` 并根据实际站点调整。

{% set secrets = pillar.get('secrets', {}) %}
{% set site_secret = secrets.get('magento_valkey', {}) %}

# 基础信息
site_name: default
valkey_password: "{{ site_secret.get('password', 'ChangeMe123!') }}"

# 可选：指定固定的数据库编号（0-15/0-255 视配置而定）
# cache_db: 10
# page_db: 11
# session_db: 12

# Valkey 连接与缓存参数（遵循 optional.magento-valkey state 的默认结构）
valkey_config:
  server: "127.0.0.1"
  port: "6379"
  compress_data: "1"
  timeout: "2.5"
  compression_threshold: "2048"
  compression_library: "gzip"
  log_level: "1"
  max_concurrency: "6"
  break_after_frontend: "5"
  break_after_adminhtml: "30"
  first_lifetime: "600"
  bot_first_lifetime: "60"
  bot_lifetime: "7200"
  disable_locking: "0"
  min_lifetime: "60"
  max_lifetime: "2592000"
