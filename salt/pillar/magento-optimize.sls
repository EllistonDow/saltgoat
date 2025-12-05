magento_optimize:
  profile: auto
  auto_detect_sites: false
  php_pool_defaults:
    memory_limit: 2048M
    max_requests: 1500
    process_idle_timeout: 60s
    reserve_mb: 4096
    per_cpu: 2
    min_children: 2
    max_cap: 64
  overrides:
    mysql:
      innodb_buffer_pool_size: '32G'
      innodb_buffer_pool_instances: 12
    opensearch:
      index_buffer_size: '30%'
      queries_cache_size: '15%'
      fielddata_cache_size: '30%'
  sites:
    ambi:
      site_root: /var/www/ambi
      env_path: /var/www/ambi/app/etc/env.php
      php_pool:
        pool_name: magento-ambi
        max_children: 8
        min_spare_servers: 4
        max_spare_servers: 5
        start_servers: 4
    bdgy:
      site_root: /var/www/bdgy
      env_path: /var/www/bdgy/app/etc/env.php
      php_pool:
        pool_name: magento-bdgy
        max_children: 4
        min_spare_servers: 2
        max_spare_servers: 3
        start_servers: 2
    hawk:
      site_root: /var/www/hawk
      env_path: /var/www/hawk/app/etc/env.php
      php_pool:
        pool_name: magento-hawk
        max_children: 4
        min_spare_servers: 2
        max_spare_servers: 3
        start_servers: 2
    ipwa:
      site_root: /var/www/ipwa
      env_path: /var/www/ipwa/app/etc/env.php
      php_pool:
        pool_name: magento-ipwa
        max_children: 4
        min_spare_servers: 2
        max_spare_servers: 3
        start_servers: 2
    ntca:
      site_root: /var/www/ntca
      env_path: /var/www/ntca/app/etc/env.php
      php_pool:
        pool_name: magento-ntca
        max_children: 4
        min_spare_servers: 2
        max_spare_servers: 3
        start_servers: 2
    papa:
      site_root: /var/www/papa
      env_path: /var/www/papa/app/etc/env.php
      php_pool:
        pool_name: magento-papa
        max_children: 8
        min_spare_servers: 4
        max_spare_servers: 5
        start_servers: 4
    sava:
      site_root: /var/www/sava
      env_path: /var/www/sava/app/etc/env.php
      php_pool:
        pool_name: magento-sava
        max_children: 4
        min_spare_servers: 2
        max_spare_servers: 3
        start_servers: 2
