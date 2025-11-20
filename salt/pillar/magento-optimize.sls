magento_optimize:
  profile: auto
  auto_detect_sites: false
  overrides: {}
  sites:
    papa:
      env_path: /var/www/papa/app/etc/env.php
      site_root: /var/www/papa
      php_pool:
        pool_name: magento-papa
        role: frontend
        weight: 1
    hawk:
      env_path: /var/www/hawk/app/etc/env.php
      site_root: /var/www/hawk
      php_pool:
        pool_name: magento-hawk
        role: frontend
        weight: 1
    ambi:
      env_path: /var/www/ambi/app/etc/env.php
      site_root: /var/www/ambi
      php_pool:
        pool_name: magento-ambi
        role: frontend
        weight: 1
