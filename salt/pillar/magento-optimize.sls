magento_optimize:
  profile: auto
  sites:
    bank:
      site_root: /var/www/bank
      php_pool:
        pool_name: magento-bank
        managed_by: saltgoat-multisite
        store_codes:
        - bank
        weight: 1
        last_adjusted: '2025-11-16T00:53:04Z'
    duobank:
      site_root: /var/www/bank
      php_pool:
        pool_name: magento-duobank
        managed_by: saltgoat-multisite
        store_codes:
        - duobank
        weight: 1
        last_adjusted: '2025-11-16T00:53:46Z'
    treebank:
      site_root: /var/www/bank
      php_pool:
        pool_name: magento-treebank
        managed_by: saltgoat-multisite
        store_codes:
        - treebank
        weight: 1
        last_adjusted: '2025-11-16T00:54:13Z'
