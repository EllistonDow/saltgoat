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
  cmd.run:
    - name: |
        # 检测Nginx配置文件路径
        NGINX_CONF=""
        if [ -f "/usr/local/nginx/conf/nginx.conf" ]; then
            NGINX_CONF="/usr/local/nginx/conf/nginx.conf"
        elif [ -f "/etc/nginx/nginx.conf" ]; then
            NGINX_CONF="/etc/nginx/nginx.conf"
        else
            echo "错误: 找不到Nginx配置文件"
            exit 1
        fi
        
        echo "使用Nginx配置文件: $NGINX_CONF"
        
        # 备份原配置文件
        sudo cp "$NGINX_CONF" "$NGINX_CONF.backup.$(date +%Y%m%d_%H%M%S)"
        
        # 修复错误的worker_connections位置（删除全局区域的错误配置）
        sudo sed -i '/^worker_connections 2048;$/d' "$NGINX_CONF"
        
        # 在events块内正确设置worker_connections
        sudo sed -i '/events {/,/}/ s/worker_connections [0-9]*;/worker_connections 2048;/' "$NGINX_CONF"
        
        # 优化其他配置（使用更灵活的匹配）
        sudo sed -i 's/client_max_body_size [0-9]*[Mm];/client_max_body_size 64M;/' "$NGINX_CONF"
        
        # 添加Magento优化配置（使用更安全的方法，避免重复）
        # 先删除可能存在的重复配置
        sudo sed -i '/gzip_disable "msie6";/d' "$NGINX_CONF"
        sudo sed -i '/gzip_buffers 16 8k;/d' "$NGINX_CONF"
        sudo sed -i '/gzip_http_version 1.1;/d' "$NGINX_CONF"
        
        # 在gzip_types行后添加优化配置（使用更安全的处理方式）
        if grep -q "gzip_types" "$NGINX_CONF"; then
            # 检查gzip_types是否已经完整（以分号结尾）
            if grep -A 10 "gzip_types" "$NGINX_CONF" | grep -q ";"; then
                # 如果gzip_types已经完整，在其后添加其他配置
                sudo sed -i '/gzip_types.*;/a\    gzip_disable "msie6";\n    gzip_buffers 16 8k;\n    gzip_http_version 1.1;' "$NGINX_CONF"
            else
                # 如果gzip_types不完整，先修复它
                sudo sed -i '/gzip_types$/,/image\/svg\+xml;/c\    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;' "$NGINX_CONF"
                sudo sed -i '/gzip_types.*;/a\    gzip_disable "msie6";\n    gzip_buffers 16 8k;\n    gzip_http_version 1.1;' "$NGINX_CONF"
            fi
        else
            # 如果没有gzip_types，在http块中添加
            sudo sed -i '/http {/a\    gzip on;\n    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;\n    gzip_disable "msie6";\n    gzip_buffers 16 8k;\n    gzip_http_version 1.1;' "$NGINX_CONF"
        fi
    - require:
      - cmd: detect_system_memory

# 测试 Nginx 配置
test_nginx_config:
  cmd.run:
    - name: |
        # 检测Nginx可执行文件路径
        NGINX_BIN=""
        if [ -f "/usr/local/nginx/sbin/nginx" ]; then
            NGINX_BIN="/usr/local/nginx/sbin/nginx"
        elif [ -f "/usr/sbin/nginx" ]; then
            NGINX_BIN="/usr/sbin/nginx"
        elif [ -f "/usr/bin/nginx" ]; then
            NGINX_BIN="/usr/bin/nginx"
        else
            echo "错误: 找不到Nginx可执行文件"
            exit 1
        fi
        
        echo "使用Nginx可执行文件: $NGINX_BIN"
        sudo "$NGINX_BIN" -t
    - require:
      - cmd: optimize_nginx_config

# 重新加载 Nginx
reload_nginx:
  service.running:
    - name: nginx
    - reload: true
    - require:
      - cmd: test_nginx_config

# 优化 PHP 配置
optimize_php_config:
  cmd.run:
    - name: |
        # 检测PHP版本和配置文件路径
        PHP_VERSION=""
        PHP_INI=""
        PHP_FPM_CONF=""
        
        # 检测PHP版本
        for version in 8.3 8.2 8.1 8.0 7.4; do
            if [ -f "/etc/php/$version/fpm/php.ini" ]; then
                PHP_VERSION="$version"
                PHP_INI="/etc/php/$version/fpm/php.ini"
                PHP_FPM_CONF="/etc/php/$version/fpm/php-fpm.conf"
                break
            fi
        done
        
        if [ -z "$PHP_VERSION" ]; then
            echo "错误: 找不到PHP-FPM配置文件"
            exit 1
        fi
        
        echo "使用PHP版本: $PHP_VERSION"
        echo "PHP配置文件: $PHP_INI"
        echo "PHP-FPM配置文件: $PHP_FPM_CONF"
        
        # 备份原配置文件
        sudo cp "$PHP_INI" "$PHP_INI.backup.$(date +%Y%m%d_%H%M%S)"
        
        # 创建日志目录并设置权限
        sudo mkdir -p /var/log
        sudo touch "/var/log/php$PHP_VERSION-fpm.log"
        sudo chown www-data:www-data "/var/log/php$PHP_VERSION-fpm.log"
        sudo chmod 666 "/var/log/php$PHP_VERSION-fpm.log"
        
        # 修复PHP-FPM配置文件中的error_log设置
        sudo sed -i "s|error_log = /var/log/php$PHP_VERSION-fpm.log|;error_log = /var/log/php$PHP_VERSION-fpm.log|" "$PHP_FPM_CONF"
        
        # 修复Pool配置冲突：移除Pool中的memory_limit设置，让php.ini生效
        POOL_CONF="/etc/php/$PHP_VERSION/fpm/pool.d/www.conf"
        if [[ -f "$POOL_CONF" ]]; then
            echo "修复Pool配置冲突: $POOL_CONF"
            sudo sed -i '/php_admin_value\[memory_limit\]/d' "$POOL_CONF"
            
            # 优化进程管理配置
            sudo sed -i 's/pm.max_children = [0-9]*/pm.max_children = 30/' "$POOL_CONF"
            sudo sed -i 's/pm.max_requests = [0-9]*/pm.max_requests = 500/' "$POOL_CONF"
            sudo sed -i 's/pm.min_spare_servers = [0-9]*/pm.min_spare_servers = 3/' "$POOL_CONF"
            sudo sed -i 's/pm.max_spare_servers = [0-9]*/pm.max_spare_servers = 20/' "$POOL_CONF"
        fi
        
        # 使用sed优化PHP配置（使用更灵活的匹配）
        sudo sed -i 's/memory_limit = [0-9]*[Mm]/memory_limit = 2G/' "$PHP_INI"
        sudo sed -i 's/max_execution_time = [0-9]*/max_execution_time = 300/' "$PHP_INI"
        sudo sed -i 's/max_input_vars = [0-9]*/max_input_vars = 3000/' "$PHP_INI"
        sudo sed -i 's/post_max_size = [0-9]*[Mm]/post_max_size = 64M/' "$PHP_INI"
        sudo sed -i 's/upload_max_filesize = [0-9]*[Mm]/upload_max_filesize = 64M/' "$PHP_INI"
        
        # 优化OPcache（使用更灵活的匹配）
        sudo sed -i 's/opcache.memory_consumption=[0-9]*/opcache.memory_consumption=512/' "$PHP_INI"
        sudo sed -i 's/opcache.max_accelerated_files=[0-9]*/opcache.max_accelerated_files=20000/' "$PHP_INI"
        sudo sed -i 's/opcache.validate_timestamps=[01]/opcache.validate_timestamps=0/' "$PHP_INI"
        sudo sed -i 's/opcache.revalidate_freq=[0-9]*/opcache.revalidate_freq=0/' "$PHP_INI"
        
        # 添加路径缓存优化
        sudo grep -q "realpath_cache_size" "$PHP_INI" || echo "realpath_cache_size = 4096K" | sudo tee -a "$PHP_INI"
        sudo grep -q "realpath_cache_ttl" "$PHP_INI" || echo "realpath_cache_ttl = 600" | sudo tee -a "$PHP_INI"
        
        # 设置错误日志路径
        sudo sed -i "s|;error_log = php_errors.log|error_log = /var/log/php$PHP_VERSION-fpm.log|" "$PHP_INI"
        
        # 优化CLI配置（CLI需要更多内存运行Magento命令）
        CLI_INI="/etc/php/$PHP_VERSION/cli/php.ini"
        if [[ -f "$CLI_INI" ]]; then
            echo "优化CLI配置: $CLI_INI"
            sudo sed -i 's/memory_limit = [0-9]*[Mm]/memory_limit = 2G/' "$CLI_INI"
            sudo sed -i 's/max_execution_time = [0-9]*/max_execution_time = 300/' "$CLI_INI"
            sudo sed -i 's/max_input_vars = [0-9]*/max_input_vars = 3000/' "$CLI_INI"
            sudo sed -i 's/post_max_size = [0-9]*[Mm]/post_max_size = 64M/' "$CLI_INI"
            sudo sed -i 's/upload_max_filesize = [0-9]*[Mm]/upload_max_filesize = 64M/' "$CLI_INI"
            
            # 优化CLI的OPcache（修复注释问题）
            sudo sed -i 's/;opcache.memory_consumption=[0-9]*/opcache.memory_consumption=512/' "$CLI_INI"
            sudo sed -i 's/;opcache.max_accelerated_files=[0-9]*/opcache.max_accelerated_files=20000/' "$CLI_INI"
            sudo sed -i 's/;opcache.validate_timestamps=[01]/opcache.validate_timestamps=0/' "$CLI_INI"
            sudo sed -i 's/;opcache.revalidate_freq=[0-9]*/opcache.revalidate_freq=0/' "$CLI_INI"
            
            # 添加CLI路径缓存优化
            sudo grep -q "realpath_cache_size" "$CLI_INI" || echo "realpath_cache_size = 4096K" | sudo tee -a "$CLI_INI"
            sudo sed -i 's/realpath_cache_ttl = [0-9]*/realpath_cache_ttl = 600/' "$CLI_INI"
        fi
        
        # 修复XML模块重复加载问题
        echo "修复XML模块重复加载问题..."
        sudo rm -f "/etc/php/$PHP_VERSION/fpm/conf.d/20-xml.ini"
        sudo rm -f "/etc/php/$PHP_VERSION/cli/conf.d/20-xml.ini"
    - require:
      - cmd: detect_system_memory

# 测试 PHP 配置
test_php_config:
  cmd.run:
    - name: |
        # 检测PHP-FPM可执行文件路径
        PHP_FPM_BIN=""
        for version in 8.3 8.2 8.1 8.0 7.4; do
            if [ -f "/usr/sbin/php-fpm$version" ]; then
                PHP_FPM_BIN="/usr/sbin/php-fpm$version"
                break
            elif [ -f "/usr/bin/php-fpm$version" ]; then
                PHP_FPM_BIN="/usr/bin/php-fpm$version"
                break
            fi
        done
        
        if [ -z "$PHP_FPM_BIN" ]; then
            echo "错误: 找不到PHP-FPM可执行文件"
            exit 1
        fi
        
        echo "使用PHP-FPM可执行文件: $PHP_FPM_BIN"
        "$PHP_FPM_BIN" -t
    - require:
      - cmd: optimize_php_config

# 重新加载 PHP-FPM
reload_php_fpm:
  cmd.run:
    - name: |
        # 检测PHP-FPM服务名称
        PHP_FPM_SERVICE=""
        for version in 8.3 8.2 8.1 8.0 7.4; do
            if systemctl list-unit-files | grep -q "php$version-fpm.service"; then
                PHP_FPM_SERVICE="php$version-fpm"
                break
            fi
        done
        
        if [ -z "$PHP_FPM_SERVICE" ]; then
            echo "错误: 找不到PHP-FPM服务"
            exit 1
        fi
        
        echo "使用PHP-FPM服务: $PHP_FPM_SERVICE"
        sudo systemctl restart "$PHP_FPM_SERVICE"
    - require:
      - cmd: test_php_config

# 优化 MySQL 配置
optimize_mysql_config:
  cmd.run:
    - name: |
        # 备份原配置文件
        sudo cp /etc/mysql/mysql.conf.d/lemp.cnf /etc/mysql/mysql.conf.d/lemp.cnf.backup.$(date +%Y%m%d_%H%M%S)
        
        # 使用sed优化MySQL配置
        sudo sed -i 's/innodb_buffer_pool_size = 128M/innodb_buffer_pool_size = 16G/' /etc/mysql/mysql.conf.d/lemp.cnf
        sudo sed -i 's/max_connections = 200/max_connections = 500/' /etc/mysql/mysql.conf.d/lemp.cnf
        # innodb_log_file_size 在 Percona 8.4+ 中已移除，使用 innodb_redo_log_capacity
        # sudo sed -i 's/innodb_log_file_size = 256M/innodb_log_file_size = 256M/' /etc/mysql/mysql.conf.d/lemp.cnf
        
        # 添加Magento优化配置
        echo "" | sudo tee -a /etc/mysql/mysql.conf.d/lemp.cnf
        echo "# Magento优化配置" | sudo tee -a /etc/mysql/mysql.conf.d/lemp.cnf
        echo "innodb_buffer_pool_instances = 8" | sudo tee -a /etc/mysql/mysql.conf.d/lemp.cnf
        echo "innodb_log_buffer_size = 16M" | sudo tee -a /etc/mysql/mysql.conf.d/lemp.cnf
        echo "innodb_flush_log_at_trx_commit = 2" | sudo tee -a /etc/mysql/mysql.conf.d/lemp.cnf
        echo "innodb_thread_concurrency = 16" | sudo tee -a /etc/mysql/mysql.conf.d/lemp.cnf
        # query_cache 在 Percona 8.4+ 中已移除
        # echo "query_cache_size = 128M" | sudo tee -a /etc/mysql/mysql.conf.d/lemp.cnf
        # echo "query_cache_type = 1" | sudo tee -a /etc/mysql/mysql.conf.d/lemp.cnf
        echo "tmp_table_size = 64M" | sudo tee -a /etc/mysql/mysql.conf.d/lemp.cnf
        echo "max_heap_table_size = 64M" | sudo tee -a /etc/mysql/mysql.conf.d/lemp.cnf
    - require:
      - cmd: detect_system_memory

# 重启 MySQL
restart_mysql:
  service.running:
    - name: mysql
    - restart: true
    - require:
      - cmd: optimize_mysql_config

# 优化 Valkey 配置
optimize_valkey_config:
  cmd.run:
    - name: |
        # 备份原配置文件
        sudo cp /etc/valkey/valkey.conf /etc/valkey/valkey.conf.backup.$(date +%Y%m%d_%H%M%S)
        
        # 使用sed优化Valkey配置
        sudo sed -i 's/maxmemory 256mb/maxmemory 1gb/' /etc/valkey/valkey.conf
        sudo sed -i 's/maxmemory-policy allkeys-lru/maxmemory-policy allkeys-lru/' /etc/valkey/valkey.conf
        
        # 添加Magento优化配置
        echo "" | sudo tee -a /etc/valkey/valkey.conf
        echo "# Magento优化配置" | sudo tee -a /etc/valkey/valkey.conf
        echo "timeout 300" | sudo tee -a /etc/valkey/valkey.conf
        echo "tcp-keepalive 60" | sudo tee -a /etc/valkey/valkey.conf
    - require:
      - cmd: detect_system_memory

# 重启 Valkey
restart_valkey:
  service.running:
    - name: valkey
    - restart: true
    - require:
      - cmd: optimize_valkey_config

# 优化 OpenSearch 配置
optimize_opensearch_config:
  cmd.run:
    - name: |
        # 备份原配置文件
        sudo cp /etc/opensearch/opensearch.yml /etc/opensearch/opensearch.yml.backup.$(date +%Y%m%d_%H%M%S)
        
        # 添加Magento优化配置
        echo "" | sudo tee -a /etc/opensearch/opensearch.yml
        echo "# Magento优化配置" | sudo tee -a /etc/opensearch/opensearch.yml
        echo "indices.memory.index_buffer_size: 20%" | sudo tee -a /etc/opensearch/opensearch.yml
        echo "indices.queries.cache.size: 10%" | sudo tee -a /etc/opensearch/opensearch.yml
        echo "indices.fielddata.cache.size: 20%" | sudo tee -a /etc/opensearch/opensearch.yml
        echo "thread_pool.write.queue_size: 1000" | sudo tee -a /etc/opensearch/opensearch.yml
        echo "thread_pool.search.queue_size: 1000" | sudo tee -a /etc/opensearch/opensearch.yml
    - require:
      - cmd: detect_system_memory

# 重启 OpenSearch
restart_opensearch:
  service.running:
    - name: opensearch
    - restart: true
    - require:
      - cmd: optimize_opensearch_config

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

# 完成优化并显示优化报告
magento_optimization_complete:
  cmd.run:
    - name: |
        echo "=========================================="
        echo "    Magento 2.4.8 优化配置完成"
        echo "=========================================="
        echo ""
        echo "系统信息:"
        echo "  内存级别: $(cat /tmp/memory_level 2>/dev/null || echo 'unknown')"
        echo "  总内存: $(cat /tmp/total_memory_gb 2>/dev/null || echo 'unknown') GB"
        echo ""
        echo "优化内容详情:"
        echo "----------------------------------------"
        echo ""
        echo "1. Nginx 优化:"
        echo "  - worker_connections: 2048 (提升并发处理能力)"
        echo "  - client_max_body_size: 64M (适合Magento文件上传)"
        echo "  - gzip_disable: msie6 (禁用IE6压缩)"
        echo "  - gzip_buffers: 16 8k (优化压缩缓冲区)"
        echo "  - gzip_http_version: 1.1 (启用HTTP/1.1压缩)"
        echo ""
        echo "2. PHP-FPM 优化:"
        echo "  - memory_limit: 2G (提升内存限制)"
        echo "  - max_execution_time: 300s (延长执行时间)"
        echo "  - max_input_vars: 3000 (增加输入变量限制)"
        echo "  - post_max_size: 64M (提升POST数据大小)"
        echo "  - upload_max_filesize: 64M (提升文件上传大小)"
        echo "  - opcache.memory_consumption: 512M (增加OPcache内存)"
        echo "  - opcache.max_accelerated_files: 20000 (增加缓存文件数)"
        echo "  - opcache.validate_timestamps: 0 (禁用时间戳验证)"
        echo "  - opcache.revalidate_freq: 0 (禁用重新验证)"
        echo "  - realpath_cache_size: 4096K (路径缓存优化)"
        echo "  - realpath_cache_ttl: 600 (路径缓存TTL)"
        echo "  - Pool配置冲突已修复 (移除Pool中的memory_limit覆盖)"
        echo "  - XML模块重复加载已修复"
        echo ""
        echo "3. PHP-FPM Pool 优化:"
        echo "  - pm.max_children: 30 (优化进程数)"
        echo "  - pm.max_requests: 500 (更频繁的进程回收)"
        echo "  - pm.min_spare_servers: 3 (最小空闲进程)"
        echo "  - pm.max_spare_servers: 20 (最大空闲进程)"
        echo ""
        echo "4. PHP-CLI 优化:"
        echo "  - memory_limit: 2G (CLI运行Magento命令的推荐内存限制)"
        echo "  - max_execution_time: 300s (延长执行时间)"
        echo "  - max_input_vars: 3000 (增加输入变量限制)"
        echo "  - post_max_size: 64M (提升POST数据大小)"
        echo "  - upload_max_filesize: 64M (提升文件上传大小)"
        echo "  - opcache.memory_consumption: 512M (增加OPcache内存)"
        echo "  - opcache.max_accelerated_files: 20000 (增加缓存文件数)"
        echo "  - opcache.validate_timestamps: 0 (禁用时间戳验证)"
        echo "  - opcache.revalidate_freq: 0 (禁用重新验证)"
        echo "  - realpath_cache_size: 4096K (路径缓存优化)"
        echo "  - realpath_cache_ttl: 600 (路径缓存TTL)"
        echo ""
        echo "5. MySQL 优化:"
        echo "  - innodb_buffer_pool_size: 16G (InnoDB缓冲池)"
        echo "  - innodb_buffer_pool_instances: 8 (缓冲池实例数)"
        echo "  - innodb_log_buffer_size: 16M (日志缓冲区)"
        echo "  - innodb_flush_log_at_trx_commit: 2 (日志刷新策略)"
        echo "  - innodb_thread_concurrency: 16 (线程并发数)"
        echo "  - max_connections: 500 (最大连接数)"
        echo "  - tmp_table_size: 64M (临时表大小)"
        echo "  - max_heap_table_size: 64M (堆表最大大小)"
        echo ""
        echo "5. Valkey 优化:"
        echo "  - maxmemory: 1gb (最大内存限制)"
        echo "  - maxmemory-policy: allkeys-lru (内存淘汰策略)"
        echo "  - timeout: 300 (连接超时时间)"
        echo "  - tcp-keepalive: 60 (TCP保活时间)"
        echo ""
        echo "6. OpenSearch 优化:"
        echo "  - indices.memory.index_buffer_size: 20% (索引缓冲区)"
        echo "  - indices.queries.cache.size: 10% (查询缓存)"
        echo "  - indices.fielddata.cache.size: 20% (字段数据缓存)"
        echo "  - thread_pool.write.queue_size: 1000 (写入队列大小)"
        echo "  - thread_pool.search.queue_size: 1000 (搜索队列大小)"
        echo ""
        echo "7. RabbitMQ 优化:"
        echo "  - 使用Magento专用配置文件"
        echo ""
        echo "优化建议:"
        echo "----------------------------------------"
        echo "1. 重启所有服务以确保配置生效:"
        echo "   sudo systemctl restart nginx"
        echo "   sudo systemctl restart php8.3-fpm"
        echo "   sudo systemctl restart mysql"
        echo "   sudo systemctl restart valkey"
        echo "   sudo systemctl restart opensearch"
        echo "   sudo systemctl restart rabbitmq"
        echo ""
        echo "2. 使用 SaltGoat 监控功能检查服务状态:"
        echo "   saltgoat monitor services"
        echo "   saltgoat monitor system"
        echo ""
        echo "3. 定期使用 SaltGoat 性能监控:"
        echo "   saltgoat performance cpu"
        echo "   saltgoat performance memory"
        echo "   saltgoat performance disk"
        echo ""
        echo "=========================================="
        echo "Magento 2.4.8 优化配置完成！"
        echo "=========================================="
    - require:
      - cmd: optimize_nginx_config
      - cmd: optimize_php_config
      - cmd: optimize_mysql_config
      - cmd: optimize_valkey_config
      - cmd: optimize_opensearch_config
      - file: optimize_rabbitmq_config