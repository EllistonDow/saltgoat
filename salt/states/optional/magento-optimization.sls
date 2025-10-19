# SaltGoat Magento 2.4.8 优化 Salt States
# 基于官方推荐配置的 Magento 环境优化

# 检测系统内存并设置变量
detect_system_memory:
  cmd.run:
    - name: |
        TOTAL_MEMORY_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        TOTAL_MEMORY_GB=$((TOTAL_MEMORY_KB / 1024 / 1024))
        
        # 根据内存大小确定配置级别
        if [ $TOTAL_MEMORY_GB -ge 256 ]; then
          echo "enterprise" > /tmp/memory_level
        elif [ $TOTAL_MEMORY_GB -ge 128 ]; then
          echo "high" > /tmp/memory_level
        elif [ $TOTAL_MEMORY_GB -ge 48 ]; then
          echo "medium" > /tmp/memory_level
        elif [ $TOTAL_MEMORY_GB -ge 16 ]; then
          echo "standard" > /tmp/memory_level
        else
          echo "low" > /tmp/memory_level
        fi
        
        echo "$TOTAL_MEMORY_GB" > /tmp/total_memory_gb
        touch /tmp/memory_detected
    - creates: /tmp/memory_detected

# 优化 Nginx 配置
optimize_nginx_config:
  file.managed:
    - name: /usr/local/nginx/conf/nginx.conf
    - source: salt://optional/nginx-magento.conf
    - backup: minion
    - require:
      - cmd: detect_system_memory

# 测试 Nginx 配置
test_nginx_config:
  cmd.run:
    - name: /usr/local/nginx/sbin/nginx -t
    - require:
      - file: optimize_nginx_config

# 重新加载 Nginx
reload_nginx:
  service.running:
    - name: nginx
    - reload: true
    - require:
      - cmd: test_nginx_config

# 优化 PHP 配置
optimize_php_config:
  file.managed:
    - name: /etc/php/8.3/fpm/php.ini
    - source: salt://optional/php-magento.ini
    - backup: minion
    - require:
      - cmd: detect_system_memory

# 测试 PHP 配置
test_php_config:
  cmd.run:
    - name: php-fpm8.3 -t
    - require:
      - file: optimize_php_config

# 重新加载 PHP-FPM
reload_php_fpm:
  service.running:
    - name: php8.3-fpm
    - reload: true
    - require:
      - cmd: test_php_config

# 优化 MySQL 配置
optimize_mysql_config:
  file.managed:
    - name: /etc/mysql/mysql.conf.d/lemp.cnf
    - source: salt://optional/mysql-magento.cnf
    - backup: minion
    - require:
      - cmd: detect_system_memory

# 重启 MySQL
restart_mysql:
  service.running:
    - name: mysql
    - restart: true
    - require:
      - file: optimize_mysql_config

# 优化 Valkey 配置
optimize_valkey_config:
  file.managed:
    - name: /etc/valkey/valkey.conf
    - source: salt://optional/valkey-magento.conf
    - backup: minion
    - require:
      - cmd: detect_system_memory

# 重启 Valkey
restart_valkey:
  service.running:
    - name: valkey
    - restart: true
    - require:
      - file: optimize_valkey_config

# 优化 OpenSearch 配置
optimize_opensearch_config:
  file.managed:
    - name: /etc/opensearch/opensearch.yml
    - source: salt://optional/opensearch-magento.yml
    - backup: minion
    - require:
      - cmd: detect_system_memory

# 重启 OpenSearch
restart_opensearch:
  service.running:
    - name: opensearch
    - restart: true
    - require:
      - file: optimize_opensearch_config

# 优化 RabbitMQ 配置
optimize_rabbitmq_config:
  file.managed:
    - name: /etc/rabbitmq/rabbitmq.conf
    - source: salt://optional/rabbitmq-magento.conf
    - backup: minion
    - require:
      - cmd: detect_system_memory

# 重启 RabbitMQ
restart_rabbitmq:
  service.running:
    - name: rabbitmq
    - restart: true
    - require:
      - file: optimize_rabbitmq_config

# 安装内存监控脚本
install_memory_monitor:
  file.managed:
    - name: /usr/local/bin/saltgoat-memory-monitor
    - source: salt://optional/memory-monitor.sh
    - mode: 755
    - require:
      - cmd: detect_system_memory

# 创建内存监控日志目录
create_monitor_log_dir:
  file.directory:
    - name: /var/log/saltgoat
    - mode: 755
    - require:
      - file: install_memory_monitor