{#-
  基于 Pillar `magento_optimize:sites`（或自动检测的 Magento 根目录）生成 PHP-FPM 池。
  每个站点可在 `php_pool` 下覆盖默认值，未设置时根据系统资源自动计算。
-#}
{% set php_version = salt['pillar.get']('saltgoat:php_version', '8.3') %}
{% set pool_dir = '/etc/php/{}/fpm/pool.d'.format(php_version) %}
{% set pool_defaults = salt['pillar.get']('magento_optimize:php_pool_defaults', {}) %}
{% set magento_optimize = salt['pillar.get']('magento_optimize', {}) %}
{% set sites = magento_optimize.get('sites', {}) or {} %}
{% set auto_detect = magento_optimize.get('auto_detect_sites', sites | length == 0) %}
{% if auto_detect and (sites | length == 0) %}
  {% set env_candidates = salt['file.find']('/var/www', maxdepth=4, type='f', name='env.php') %}
  {% set auto_ns = namespace(data={}) %}
  {% set suffix = '/app/etc/env.php' %}
  {% for env_path in env_candidates %}
    {% if env_path.endswith(suffix) %}
      {% set site_root = env_path.rsplit(suffix, 1)[0] %}
      {% set bin_path = site_root + '/bin/magento' %}
      {% if salt['file.file_exists'](bin_path) %}
        {% set raw_site = site_root.split('/') | last %}
        {% set site_id = raw_site | lower | regex_replace('[^a-z0-9_-]', '-') %}
        {% set pool_name = 'magento-' + site_id %}
        {% set detected = {
          site_id: {
            'site_root': site_root,
            'env_path': env_path,
            'php_pool': {
              'pool_name': pool_name,
              'weight': 1
            }
          }
        } %}
        {% set auto_ns.data = salt['slsutil.merge'](auto_ns.data, detected, strategy='recurse', merge_lists=False) %}
      {% endif %}
    {% endif %}
  {% endfor %}
  {% if auto_ns.data %}
    {% set sites = auto_ns.data %}
  {% endif %}
{% endif %}
{% set site_items = sites.items() %}
{% set site_count = site_items | length %}
{% set cpu_cores = (salt['grains.get']('num_cpus', 2) or 2) | int %}
{% set mem_total_mb = (salt['grains.get']('mem_total', 4096) or 4096) | int %}
{% set reserve_mb = (pool_defaults.get('reserve_mb', 4096) or 4096) | int %}
{% set available_mb = mem_total_mb - reserve_mb if mem_total_mb > reserve_mb else (mem_total_mb * 3 // 4) %}
{% if available_mb < 512 %}
  {% set available_mb = mem_total_mb // 2 %}
{% endif %}
{% set ns_weight = namespace(total=0) %}
{% for site_id, site_cfg in site_items %}
  {% set pool_cfg = site_cfg.get('php_pool', {}) %}
  {% set ns_weight.total = ns_weight.total + (pool_cfg.get('weight', 1) or 1) %}
{% endfor %}
{% if ns_weight.total == 0 %}
  {% set ns_weight.total = site_count if site_count > 0 else 1 %}
{% endif %}

{% set ns_pools = namespace(items=[]) %}
{% for site_id, site_cfg in site_items %}
  {% set pool_cfg = site_cfg.get('php_pool', {}) %}
  {% if pool_cfg is mapping %}
    {% set pool_name = pool_cfg.get('name') or pool_cfg.get('pool_name') or ('magento-' ~ site_id) %}
    {% set pm_mode = pool_cfg.get('pm', pool_defaults.get('pm', 'dynamic')) %}
    {% set weight = pool_cfg.get('weight', 1) or 1 %}
    {% set estimated_child_mb = pool_cfg.get('estimated_child_mb', pool_defaults.get('estimated_child_mb', 2048)) %}
    {% if estimated_child_mb < 256 %}
      {% set estimated_child_mb = 256 %}
    {% endif %}
    {% set share_mb = (available_mb * weight // ns_weight.total) | int %}
    {% if share_mb < estimated_child_mb %}
      {% set share_mb = estimated_child_mb %}
    {% endif %}
    {% set auto_children = (share_mb // estimated_child_mb) | int %}
    {% if auto_children < 1 %}
      {% set auto_children = 1 %}
    {% endif %}
    {% set min_children = pool_cfg.get('min_children', pool_defaults.get('min_children', 4)) %}
    {% if auto_children < min_children %}
      {% set auto_children = min_children %}
    {% endif %}
    {% set max_cap = pool_cfg.get('max_cap', pool_defaults.get('max_cap', 64)) %}
    {% if max_cap and auto_children > max_cap %}
      {% set auto_children = max_cap %}
    {% endif %}
    {% set cpu_based = (cpu_cores * pool_cfg.get('per_cpu', pool_defaults.get('per_cpu', 2))) %}
    {% if cpu_based > 0 and auto_children > cpu_based %}
      {% set auto_children = cpu_based %}
    {% endif %}
    {% set max_children = (pool_cfg.get('max_children') or auto_children) | int %}
    {% if max_children < min_children %}
      {% set max_children = min_children %}
    {% endif %}
    {% if max_cap and max_children > max_cap %}
      {% set max_children = max_cap %}
    {% endif %}
    {% set start_servers = pool_cfg.get('start_servers') %}
    {% if start_servers is none %}
      {% if pm_mode == 'dynamic' %}
        {% set start_servers = (max_children // 2) | int %}
        {% if start_servers < min_children %}
          {% set start_servers = min_children %}
        {% endif %}
      {% else %}
        {% set start_servers = pool_defaults.get('start_servers', 0) %}
      {% endif %}
    {% endif %}
    {% if start_servers > max_children %}
      {% set start_servers = max_children %}
    {% endif %}
    {% set min_spare = pool_cfg.get('min_spare_servers') %}
    {% if min_spare is none %}
      {% if pm_mode == 'dynamic' %}
        {% set min_spare = (max_children // 3) | int %}
        {% if min_spare < min_children %}
          {% set min_spare = min_children %}
        {% endif %}
      {% else %}
        {% set min_spare = 0 %}
      {% endif %}
    {% endif %}
    {% if min_spare > max_children %}
      {% set min_spare = max_children %}
    {% endif %}
    {% set max_spare = pool_cfg.get('max_spare_servers') %}
    {% if max_spare is none %}
      {% if pm_mode == 'dynamic' %}
        {% set max_spare = (max_children * 2 // 3) | int %}
        {% if max_spare <= min_spare %}
          {% set max_spare = min_spare + 2 %}
        {% endif %}
        {% if max_spare > max_children %}
          {% set max_spare = max_children %}
        {% endif %}
      {% else %}
        {% set max_spare = 0 %}
      {% endif %}
    {% endif %}
    {% if max_spare > max_children %}
      {% set max_spare = max_children %}
    {% endif %}
    {% set max_requests = pool_cfg.get('max_requests', pool_defaults.get('max_requests', 1500)) %}
    {% set idle_timeout = pool_cfg.get('process_idle_timeout', pool_defaults.get('process_idle_timeout', '60s')) %}
    {% set listen = pool_cfg.get('listen', '/run/php/php{}-fpm-{}.sock'.format(php_version, pool_name)) %}
    {% set php_admin_values = salt['slsutil.merge']({'memory_limit': pool_cfg.get('memory_limit', pool_defaults.get('memory_limit', '2048M'))}, pool_cfg.get('php_admin_values', {}), strategy='recurse') %}
    {% set php_values = pool_cfg.get('php_values', {}) %}
    {% set slowlog = pool_cfg.get('slowlog', '/var/log/php{}-fpm-{}.slow.log'.format(php_version, pool_name)) %}
    {% set ns_pools.items = ns_pools.items + [ {
      'site_id': site_id,
      'pool_name': pool_name,
      'listen': listen,
      'pm': pm_mode,
      'max_children': max_children,
      'start_servers': start_servers,
      'min_spare_servers': min_spare,
      'max_spare_servers': max_spare,
      'max_requests': max_requests,
      'process_idle_timeout': idle_timeout,
      'php_admin_values': php_admin_values,
      'php_values': php_values,
      'slowlog': slowlog,
      'extra_settings': pool_cfg.get('raw', []),
      'include': pool_cfg.get('include', []),
      'pm_status_path': pool_cfg.get('status_path'),
      'chroot': pool_cfg.get('chroot'),
      'chdir': pool_cfg.get('chdir', '/'),
      'user': pool_cfg.get('user', pool_defaults.get('user', 'www-data')),
      'group': pool_cfg.get('group', pool_defaults.get('group', 'www-data')),
      'clear_env': pool_cfg.get('clear_env', pool_defaults.get('clear_env', True)),
      'ping_path': pool_cfg.get('ping_path', pool_defaults.get('ping_path', '/ping')),
      'ping_response': pool_cfg.get('ping_response', pool_defaults.get('ping_response', 'pong')),
      'status_path': pool_cfg.get('status_path', pool_defaults.get('status_path', '/status')),
      'rlimit_files': pool_cfg.get('rlimit_files', pool_defaults.get('rlimit_files')),
      'request_terminate_timeout': pool_cfg.get('request_terminate_timeout', pool_defaults.get('request_terminate_timeout', '330s')),
      'catch_workers_output': pool_cfg.get('catch_workers_output', pool_defaults.get('catch_workers_output', 'yes'))
    } ] %}
  {% endif %}
{% endfor %}
{% set pool_items = ns_pools.items %}

{% if pool_items %}

ensure_php_fpm_pool_dir:
  file.directory:
    - name: {{ pool_dir }}
    - mode: 755
    - user: root
    - group: root

ensure_php_fpm_log_dir:
  file.directory:
    - name: /var/log/php{{ php_version }}
    - mode: 750
    - user: www-data
    - group: www-data

{% for pool in pool_items %}
manage_php_pool_{{ pool.pool_name }}:
  file.managed:
    - name: {{ pool_dir }}/{{ pool.pool_name }}.conf
    - source: salt://core/php-fpm-pool.conf
    - template: jinja
    - context:
        pool: {{ pool | json }}
        php_version: {{ php_version | json }}
    - require:
      - file: ensure_php_fpm_pool_dir
    - watch_in:
      - service: start_php_fpm
{% endfor %}

{% endif %}
