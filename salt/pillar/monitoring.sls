saltgoat:
  monitor:
    sites:
    - name: bank
      url: https://bank.magento.tattoogoat.com/
      timeout: 6
      retries: 2
      expect: 200
      tls_warn_days: 14
      tls_critical_days: 7
      timeout_services:
      - php8.3-fpm
      - varnish
      server_error_services:
      - php8.3-fpm
      - nginx
      - varnish
      failure_services:
      - php8.3-fpm
      - nginx
      - varnish
      auto: true
    - name: pwas
      url: https://bank.magento.tattoogoat.com/
      timeout: 6
      retries: 2
      expect: 200
      tls_warn_days: 14
      tls_critical_days: 7
      timeout_services:
      - php8.3-fpm
      - varnish
      server_error_services:
      - php8.3-fpm
      - nginx
      - varnish
      failure_services:
      - php8.3-fpm
      - nginx
      - varnish
      auto: true
    - name: tank
      url: https://bank.magento.tattoogoat.com/
      timeout: 6
      retries: 2
      expect: 200
      tls_warn_days: 14
      tls_critical_days: 7
      timeout_services:
      - php8.3-fpm
      - varnish
      server_error_services:
      - php8.3-fpm
      - nginx
      - varnish
      failure_services:
      - php8.3-fpm
      - nginx
      - varnish
      auto: true
    - name: duobank
      url: https://duobank.magento.tattoogoat.com/
      timeout: 6
      retries: 2
      expect: 200
      tls_warn_days: 14
      tls_critical_days: 7
      timeout_services:
      - php8.3-fpm
      - varnish
      server_error_services:
      - php8.3-fpm
      - nginx
      - varnish
      failure_services:
      - php8.3-fpm
      - nginx
      - varnish
      auto: true
    - name: treebank
      url: https://treebank.magento.tattoogoat.com/
      timeout: 6
      retries: 2
      expect: 200
      tls_warn_days: 14
      tls_critical_days: 7
      timeout_services:
      - php8.3-fpm
      - varnish
      server_error_services:
      - php8.3-fpm
      - nginx
      - varnish
      failure_services:
      - php8.3-fpm
      - nginx
      - varnish
      auto: true
  beacons:
    service:
      services:
        varnish:
          interval: 20
