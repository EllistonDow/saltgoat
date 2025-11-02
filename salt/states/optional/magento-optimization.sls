{% set optimize_pillar = pillar.get('magento_optimize', {}) %}
{% set requested_profile = optimize_pillar.get('profile', 'auto') %}
{% set site_hint = optimize_pillar.get('site_hint', '') %}
{% set detection_status = optimize_pillar.get('detection_status', 'unknown') %}
{% set env_path = optimize_pillar.get('env_path', '') %}
{% set site_root = optimize_pillar.get('site_root', '') %}
{% set overrides = optimize_pillar.get('overrides', {}) or {} %}
{% set dedicated_sites = optimize_pillar.get('sites', {}) or {} %}
{% set has_dedicated_pools = dedicated_sites | length > 0 %}
{% set mem_total_mb = salt['grains.get']('mem_total', 0) %}
{% set mem_total_gb = (mem_total_mb / 1024) | int %}

{% if mem_total_gb >= 256 %}
  {% set auto_profile = 'enterprise' %}
{% elif mem_total_gb >= 128 %}
  {% set auto_profile = 'high' %}
{% elif mem_total_gb >= 48 %}
  {% set auto_profile = 'medium' %}
{% elif mem_total_gb >= 16 %}
  {% set auto_profile = 'standard' %}
{% else %}
  {% set auto_profile = 'low' %}
{% endif %}

{% if requested_profile == 'auto' %}
  {% set effective_profile = auto_profile %}
{% else %}
  {% set effective_profile = requested_profile %}
{% endif %}

{% set profile_defaults = {
  'low': {
    'nginx': {'worker_connections': 1024, 'client_max_body_size': '32M'},
    'php': {
      'memory_limit': '1024M', 'max_execution_time': 300, 'max_input_vars': 2000,
      'post_max_size': '64M', 'upload_max_filesize': '64M',
      'opcache_memory_consumption': 256, 'opcache_max_accelerated_files': 10000,
      'opcache_validate_timestamps': 0, 'opcache_revalidate_freq': 0,
      'realpath_cache_size': '2048K', 'realpath_cache_ttl': 600
    },
    'php_cli': {},
    'php_pool': {'max_children': 20, 'max_requests': 300, 'min_spare': 2, 'max_spare': 10},
    'mysql': {
      'innodb_buffer_pool_size': '2G', 'innodb_buffer_pool_instances': 2,
      'innodb_log_buffer_size': '8M', 'innodb_flush_log_at_trx_commit': 2,
      'innodb_thread_concurrency': 8, 'max_connections': 200,
      'tmp_table_size': '32M', 'max_heap_table_size': '32M'
    },
    'valkey': {'maxmemory': '512mb', 'maxmemory_policy': 'allkeys-lru', 'timeout': 300, 'tcp_keepalive': 60},
    'opensearch': {
      'index_buffer_size': '10%', 'queries_cache_size': '5%', 'fielddata_cache_size': '10%',
      'thread_pool_write_queue_size': 500, 'thread_pool_search_queue_size': 500
    }
  },
  'standard': {
    'nginx': {'worker_connections': 2048, 'client_max_body_size': '64M'},
    'php': {
      'memory_limit': '2048M', 'max_execution_time': 300, 'max_input_vars': 3000,
      'post_max_size': '64M', 'upload_max_filesize': '64M',
      'opcache_memory_consumption': 512, 'opcache_max_accelerated_files': 20000,
      'opcache_validate_timestamps': 0, 'opcache_revalidate_freq': 0,
      'realpath_cache_size': '4096K', 'realpath_cache_ttl': 600
    },
    'php_cli': {},
    'php_pool': {'max_children': 30, 'max_requests': 500, 'min_spare': 3, 'max_spare': 20},
    'mysql': {
      'innodb_buffer_pool_size': '8G', 'innodb_buffer_pool_instances': 4,
      'innodb_log_buffer_size': '16M', 'innodb_flush_log_at_trx_commit': 2,
      'innodb_thread_concurrency': 12, 'max_connections': 400,
      'tmp_table_size': '64M', 'max_heap_table_size': '64M'
    },
    'valkey': {'maxmemory': '1gb', 'maxmemory_policy': 'allkeys-lru', 'timeout': 300, 'tcp_keepalive': 60},
    'opensearch': {
      'index_buffer_size': '20%', 'queries_cache_size': '10%', 'fielddata_cache_size': '20%',
      'thread_pool_write_queue_size': 1000, 'thread_pool_search_queue_size': 1000
    }
  },
  'medium': {
    'nginx': {'worker_connections': 4096, 'client_max_body_size': '96M'},
    'php': {
      'memory_limit': '3072M', 'max_execution_time': 300, 'max_input_vars': 4000,
      'post_max_size': '96M', 'upload_max_filesize': '96M',
      'opcache_memory_consumption': 768, 'opcache_max_accelerated_files': 30000,
      'opcache_validate_timestamps': 0, 'opcache_revalidate_freq': 0,
      'realpath_cache_size': '5120K', 'realpath_cache_ttl': 720
    },
    'php_cli': {},
    'php_pool': {'max_children': 50, 'max_requests': 600, 'min_spare': 5, 'max_spare': 30},
    'mysql': {
      'innodb_buffer_pool_size': '16G', 'innodb_buffer_pool_instances': 8,
      'innodb_log_buffer_size': '32M', 'innodb_flush_log_at_trx_commit': 2,
      'innodb_thread_concurrency': 16, 'max_connections': 500,
      'tmp_table_size': '96M', 'max_heap_table_size': '96M'
    },
    'valkey': {'maxmemory': '2gb', 'maxmemory_policy': 'allkeys-lru', 'timeout': 300, 'tcp_keepalive': 60},
    'opensearch': {
      'index_buffer_size': '25%', 'queries_cache_size': '12%', 'fielddata_cache_size': '25%',
      'thread_pool_write_queue_size': 1500, 'thread_pool_search_queue_size': 1500
    }
  },
  'high': {
    'nginx': {'worker_connections': 8192, 'client_max_body_size': '128M'},
    'php': {
      'memory_limit': '4096M', 'max_execution_time': 300, 'max_input_vars': 5000,
      'post_max_size': '128M', 'upload_max_filesize': '128M',
      'opcache_memory_consumption': 1024, 'opcache_max_accelerated_files': 40000,
      'opcache_validate_timestamps': 0, 'opcache_revalidate_freq': 0,
      'realpath_cache_size': '6144K', 'realpath_cache_ttl': 900
    },
    'php_cli': {},
    'php_pool': {'max_children': 80, 'max_requests': 800, 'min_spare': 10, 'max_spare': 40},
    'mysql': {
      'innodb_buffer_pool_size': '32G', 'innodb_buffer_pool_instances': 12,
      'innodb_log_buffer_size': '64M', 'innodb_flush_log_at_trx_commit': 2,
      'innodb_thread_concurrency': 24, 'max_connections': 600,
      'tmp_table_size': '128M', 'max_heap_table_size': '128M'
    },
    'valkey': {'maxmemory': '4gb', 'maxmemory_policy': 'allkeys-lru', 'timeout': 300, 'tcp_keepalive': 60},
    'opensearch': {
      'index_buffer_size': '30%', 'queries_cache_size': '15%', 'fielddata_cache_size': '30%',
      'thread_pool_write_queue_size': 2000, 'thread_pool_search_queue_size': 2000
    }
  },
  'enterprise': {
    'nginx': {'worker_connections': 16384, 'client_max_body_size': '160M'},
    'php': {
      'memory_limit': '6144M', 'max_execution_time': 300, 'max_input_vars': 6000,
      'post_max_size': '160M', 'upload_max_filesize': '160M',
      'opcache_memory_consumption': 1536, 'opcache_max_accelerated_files': 60000,
      'opcache_validate_timestamps': 0, 'opcache_revalidate_freq': 0,
      'realpath_cache_size': '8192K', 'realpath_cache_ttl': 1200
    },
    'php_cli': {},
    'php_pool': {'max_children': 120, 'max_requests': 1000, 'min_spare': 12, 'max_spare': 60},
    'mysql': {
      'innodb_buffer_pool_size': '64G', 'innodb_buffer_pool_instances': 16,
      'innodb_log_buffer_size': '128M', 'innodb_flush_log_at_trx_commit': 2,
      'innodb_thread_concurrency': 32, 'max_connections': 800,
      'tmp_table_size': '160M', 'max_heap_table_size': '160M'
    },
    'valkey': {'maxmemory': '6gb', 'maxmemory_policy': 'allkeys-lru', 'timeout': 300, 'tcp_keepalive': 60},
    'opensearch': {
      'index_buffer_size': '35%', 'queries_cache_size': '18%', 'fielddata_cache_size': '35%',
      'thread_pool_write_queue_size': 2500, 'thread_pool_search_queue_size': 2500
    }
  }
} %}

{% set profile_config = salt['slsutil.merge'](
    profile_defaults.get(effective_profile, profile_defaults['standard']),
    overrides,
    strategy='recurse',
    merge_lists=False
) %}
{% set nginx_config = profile_config.get('nginx', {}) %}
{% set php_config = profile_config.get('php', {}) %}
{% set php_cli_config = profile_config.get('php_cli', {}) %}
{% set php_pool_config = profile_config.get('php_pool', {}) %}
{% set mysql_config = profile_config.get('mysql', {}) %}
{% set valkey_config = profile_config.get('valkey', {}) %}
{% set opensearch_config = profile_config.get('opensearch', {}) %}
{% set report_path = '/var/lib/saltgoat/reports/magento-optimize-summary.txt' %}
{% set meta = {
  'requested_profile': requested_profile,
  'effective_profile': effective_profile,
  'auto_profile': auto_profile,
  'memory_gb': mem_total_gb,
  'site': optimize_pillar.get('site', ''),
  'site_hint': site_hint,
  'env_path': env_path,
  'site_root': site_root,
  'detection_status': detection_status
} %}
{% set nginx_conf_candidates = ['/etc/nginx/nginx.conf', '/usr/local/nginx/conf/nginx.conf'] %}
{% set nginx_ns = namespace(conf=None) %}
{% for candidate in nginx_conf_candidates if not nginx_ns.conf %}
  {% if salt['file.file_exists'](candidate) %}
    {% set nginx_ns.conf = candidate %}
  {% endif %}
{% endfor %}
{% set php_versions = ['8.3', '8.2', '8.1', '8.0', '7.4'] %}
{% set php_ns = namespace(version=None) %}
{% for ver in php_versions if not php_ns.version %}
  {% if salt['file.file_exists']('/etc/php/{}/fpm/php.ini'.format(ver)) %}
    {% set php_ns.version = ver %}
  {% endif %}
{% endfor %}
{% set php_ini = '/etc/php/{}/fpm/php.ini'.format(php_ns.version) if php_ns.version else None %}
{% set php_cli_ini = '/etc/php/{}/cli/php.ini'.format(php_ns.version) if php_ns.version else None %}
{% set php_fpm_conf = '/etc/php/{}/fpm/php-fpm.conf'.format(php_ns.version) if php_ns.version else None %}
{% set php_pool_conf = '/etc/php/{}/fpm/pool.d/www.conf'.format(php_ns.version) if php_ns.version else None %}
{% set php_cli_exists = php_cli_ini and salt['file.file_exists'](php_cli_ini) %}

{% if not nginx_ns.conf %}
magento_nginx_config_missing:
  test.fail_without_changes:
    - comment: "未找到 Nginx 配置文件，请先安装并初始化 Nginx"
{% elif detection_status == 'ambiguous' %}
magento_site_selection_required:
  test.fail_without_changes:
    - comment: "检测到多个 Magento 站点，请使用 '--site <name|path>' 指定后再运行"
{% elif detection_status == 'missing' %}
magento_env_missing_warning:
  test.show_notification:
    - text: "未检测到 Magento env.php，已跳过站点级配置，仅应用服务级优化"
{% endif %}

{% if detection_status == 'ambiguous' %}
{# Skip rest of state when ambiguous #}
{% elif not nginx_ns.conf %}
{# Already handled above #}
{% else %}

optimize_nginx_worker_connections:
  file.replace:
    - name: {{ nginx_ns.conf }}
    - pattern: 'worker_connections\s+\d+;'
    - repl: 'worker_connections {{ nginx_config.get("worker_connections", 2048) }};'
    - count: 1
    - backup: True
    - flags:
      - MULTILINE

optimize_nginx_http_block:
  file.blockreplace:
    - name: {{ nginx_ns.conf }}
    - marker_start: '    # BEGIN SaltGoat Magento HTTP tuning'
    - marker_end: '    # END SaltGoat Magento HTTP tuning'
    - append_if_not_found: True
    - content: |
        client_max_body_size {{ nginx_config.get("client_max_body_size", "64M") }};
        gzip on;
        gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;
        gzip_disable "msie6";
        gzip_buffers 16 8k;
        gzip_http_version 1.1;
    - require:
      - file: optimize_nginx_worker_connections

# 测试 Nginx 配置
test_nginx_config:
  cmd.run:
    - name: |
        if command -v nginx >/dev/null 2>&1; then
          nginx -t -c "{{ nginx_ns.conf }}"
        elif [ -x "/usr/local/nginx/sbin/nginx" ]; then
          /usr/local/nginx/sbin/nginx -t -c "{{ nginx_ns.conf }}"
        else
          echo "未检测到 nginx 可执行文件，跳过配置测试"
        fi
    - require:
      - file: optimize_nginx_http_block

# 重新加载 Nginx
reload_nginx:
  service.running:
    - name: nginx
    - reload: true
    - require:
      - cmd: test_nginx_config
{% endif %}

# 优化 PHP 配置
{% if not php_ns.version %}
magento_php_config_missing:
  test.fail_without_changes:
    - comment: "未找到 PHP-FPM 配置文件，请确认 PHP 已正确安装"
{% else %}

php_fpm_log_file:
  file.managed:
    - name: /var/log/php{{ php_ns.version }}-fpm.log
    - makedirs: True
    - user: www-data
    - group: www-data
    - mode: '0666'
    - contents: ''
    - replace: False

php_fpm_conf_error_log_comment:
  file.replace:
    - name: {{ php_fpm_conf }}
    - pattern: '^\s*error_log\s*=\s*/var/log/php{{ php_ns.version }}-fpm\.log'
    - repl: ';error_log = /var/log/php{{ php_ns.version }}-fpm.log'
    - backup: True
    - ignore_if_missing: True

{% if not has_dedicated_pools %}
php_fpm_pool_memory_limit_cleanup:
  file.replace:
    - name: {{ php_pool_conf }}
    - pattern: '^\s*php_admin_value\[memory_limit\].*$'
    - repl: ''
    - flags:
      - MULTILINE
    - ignore_if_missing: True

php_fpm_pool_settings:
  ini.options_present:
    - name: {{ php_pool_conf }}
    - separator: '= '
    - sections:
        www:
          pm.max_children: "{{ php_pool_config.get('max_children', 30) }}"
          pm.max_requests: "{{ php_pool_config.get('max_requests', 500) }}"
          pm.min_spare_servers: "{{ php_pool_config.get('min_spare', 3) }}"
          pm.max_spare_servers: "{{ php_pool_config.get('max_spare', 20) }}"
    - require:
      - file: php_fpm_pool_memory_limit_cleanup
{% endif %}

php_ini_settings:
  ini.options_present:
    - name: {{ php_ini }}
    - separator: ' = '
    - sections:
        PHP:
          memory_limit: "{{ php_config.get('memory_limit', '2048M') }}"
          max_execution_time: "{{ php_config.get('max_execution_time', 300) }}"
          max_input_vars: "{{ php_config.get('max_input_vars', 3000) }}"
          post_max_size: "{{ php_config.get('post_max_size', '64M') }}"
          upload_max_filesize: "{{ php_config.get('upload_max_filesize', '64M') }}"
          realpath_cache_size: "{{ php_config.get('realpath_cache_size', '4096K') }}"
          realpath_cache_ttl: "{{ php_config.get('realpath_cache_ttl', 600) }}"
          error_log: "/var/log/php{{ php_ns.version }}-fpm.log"
        opcache:
          opcache.memory_consumption: "{{ php_config.get('opcache_memory_consumption', 512) }}"
          opcache.max_accelerated_files: "{{ php_config.get('opcache_max_accelerated_files', 20000) }}"
          opcache.validate_timestamps: "{{ php_config.get('opcache_validate_timestamps', 0) }}"
          opcache.revalidate_freq: "{{ php_config.get('opcache_revalidate_freq', 0) }}"
    - require:
      - file: php_fpm_log_file

{% if php_cli_exists %}
php_cli_ini_settings:
  ini.options_present:
    - name: {{ php_cli_ini }}
    - separator: ' = '
    - sections:
        PHP:
          memory_limit: "{{ php_cli_config.get('memory_limit', php_config.get('memory_limit', '2048M')) }}"
          max_execution_time: "{{ php_cli_config.get('max_execution_time', php_config.get('max_execution_time', 300)) }}"
          max_input_vars: "{{ php_cli_config.get('max_input_vars', php_config.get('max_input_vars', 3000)) }}"
          post_max_size: "{{ php_cli_config.get('post_max_size', php_config.get('post_max_size', '64M')) }}"
          upload_max_filesize: "{{ php_cli_config.get('upload_max_filesize', php_config.get('upload_max_filesize', '64M')) }}"
          realpath_cache_size: "{{ php_cli_config.get('realpath_cache_size', php_config.get('realpath_cache_size', '4096K')) }}"
          realpath_cache_ttl: "{{ php_cli_config.get('realpath_cache_ttl', php_config.get('realpath_cache_ttl', 600)) }}"
        opcache:
          opcache.memory_consumption: "{{ php_cli_config.get('opcache_memory_consumption', php_config.get('opcache_memory_consumption', 512)) }}"
          opcache.max_accelerated_files: "{{ php_cli_config.get('opcache_max_accelerated_files', php_config.get('opcache_max_accelerated_files', 20000)) }}"
          opcache.validate_timestamps: "{{ php_cli_config.get('opcache_validate_timestamps', php_config.get('opcache_validate_timestamps', 0)) }}"
          opcache.revalidate_freq: "{{ php_cli_config.get('opcache_revalidate_freq', php_config.get('opcache_revalidate_freq', 0)) }}"
{% endif %}

php_fpm_xml_module_cleanup:
  file.absent:
    - name: /etc/php/{{ php_ns.version }}/fpm/conf.d/20-xml.ini

{% if php_cli_exists %}
php_cli_xml_module_cleanup:
  file.absent:
    - name: /etc/php/{{ php_ns.version }}/cli/conf.d/20-xml.ini
{% endif %}

{% endif %}

{% if php_ns.version %}
# 测试 PHP 配置
test_php_config:
  cmd.run:
    - name: |
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
      - ini: php_ini_settings
      - ini: php_fpm_pool_settings
      - file: php_fpm_log_file
      - file: php_fpm_xml_module_cleanup
{% if php_cli_exists %}
      - ini: php_cli_ini_settings
      - file: php_cli_xml_module_cleanup
{% endif %}

# 重新加载 PHP-FPM
reload_php_fpm:
  cmd.run:
    - name: |
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
{% endif %}

# 优化 MySQL 配置
optimize_mysql_config:
  ini.options_present:
    - name: /etc/mysql/mysql.conf.d/lemp.cnf
    - separator: '='
    - sections:
        mysqld:
          innodb_buffer_pool_size: {{ mysql_config.get('innodb_buffer_pool_size', '16G') }}
          innodb_buffer_pool_instances: {{ mysql_config.get('innodb_buffer_pool_instances', 8) }}
          innodb_log_buffer_size: {{ mysql_config.get('innodb_log_buffer_size', '16M') }}
          innodb_flush_log_at_trx_commit: {{ mysql_config.get('innodb_flush_log_at_trx_commit', 2) }}
          innodb_thread_concurrency: {{ mysql_config.get('innodb_thread_concurrency', 16) }}
          max_connections: {{ mysql_config.get('max_connections', 500) }}
          tmp_table_size: {{ mysql_config.get('tmp_table_size', '64M') }}
          max_heap_table_size: {{ mysql_config.get('max_heap_table_size', '64M') }}

# 重启 MySQL
restart_mysql:
  service.running:
    - name: mysql
    - restart: true
    - require:
      - ini: optimize_mysql_config

# 优化 Valkey 配置
optimize_valkey_config:
  file.blockreplace:
    - name: /etc/valkey/valkey.conf
    - marker_start: "# BEGIN SaltGoat Magento tuning"
    - marker_end: "# END SaltGoat Magento tuning"
    - append_if_not_found: True
    - content: |
        maxmemory {{ valkey_config.get('maxmemory', '1gb') }}
        maxmemory-policy {{ valkey_config.get('maxmemory_policy', 'allkeys-lru') }}
        timeout {{ valkey_config.get('timeout', 300) }}
        tcp-keepalive {{ valkey_config.get('tcp_keepalive', 60) }}

# 重启 Valkey
restart_valkey:
  service.running:
    - name: valkey
    - restart: true
    - require:
      - file: optimize_valkey_config

# 优化 OpenSearch 配置
optimize_opensearch_config:
  file.blockreplace:
    - name: /etc/opensearch/opensearch.yml
    - marker_start: "# BEGIN SaltGoat Magento tuning"
    - marker_end: "# END SaltGoat Magento tuning"
    - append_if_not_found: True
    - content: |
        indices.memory.index_buffer_size: {{ opensearch_config.get('index_buffer_size', '20%') }}
        indices.queries.cache.size: {{ opensearch_config.get('queries_cache_size', '10%') }}
        indices.fielddata.cache.size: {{ opensearch_config.get('fielddata_cache_size', '20%') }}
        thread_pool.write.queue_size: {{ opensearch_config.get('thread_pool_write_queue_size', 1000) }}
        thread_pool.search.queue_size: {{ opensearch_config.get('thread_pool_search_queue_size', 1000) }}

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

# 重启 RabbitMQ
restart_rabbitmq:
  service.running:
    - name: rabbitmq
    - restart: true
    - require:
      - file: optimize_rabbitmq_config

# 生成 Magento 优化报告
generate_magento_optimization_report:
  file.managed:
    - name: {{ report_path }}
    - mode: '0644'
    - user: root
    - group: root
    - makedirs: True
    - template: jinja
    - contents: |
        ==========================================
        Magento 2 优化报告
        ==========================================
        时间: {{ salt['grains.get']('date_time', {}).get('iso8601', 'unknown') }}
        请求档位: {{ meta.get('requested_profile', 'unknown') }}
        生效档位: {{ meta.get('effective_profile', 'unknown') }}
        自动识别档位: {{ meta.get('auto_profile', 'unknown') }}
        系统内存 (GB): {{ meta.get('memory_gb', 'unknown') }}
        目标站点: {{ meta.get('site') or '未指定' }}

        配置详情 (YAML):
{% for section, values in profile_config.items() %}
        {{ section }}:
{% if values is mapping %}
{% for k, v in values.items() %}
          {{ k }}: {{ v }}
{% endfor %}
{% elif values is iterable %}
{% for item in values %}
          - {{ item }}
{% endfor %}
{% else %}
          {{ values }}
{% endif %}
{% endfor %}

        使用建议:
          - 优化完成后请根据报告确认业务需求
          - 建议执行 `saltgoat monitor services` 验证服务状态
          - 若需回滚，请恢复相关配置或使用备份

# 完成优化并提示报告位置
magento_optimization_complete:
  cmd.run:
    - name: |
        echo "Magento 优化完成。生效档位: {{ meta.get('effective_profile', 'unknown') }}。报告位于: {{ report_path }}"
    - require:
      - file: optimize_nginx_http_block
{% if php_ns.version %}
      - ini: php_ini_settings
      - ini: php_fpm_pool_settings
      - file: php_fpm_log_file
      - file: php_fpm_xml_module_cleanup
{% if php_cli_exists %}
      - ini: php_cli_ini_settings
      - file: php_cli_xml_module_cleanup
{% endif %}
{% endif %}
      - ini: optimize_mysql_config
      - file: optimize_valkey_config
      - file: optimize_opensearch_config
      - file: optimize_rabbitmq_config
      - file: generate_magento_optimization_report
