nginx:
  package: nginx
  service: nginx
  user: www-data
  group: www-data
  default_site: false
  client_max_body_size: 64m
  sites:
    bank:
      enabled: true
      server_name:
      - bank.magento.tattoogoat.com
      listen:
      - port: 80
      root: /var/www/bank
      index:
      - index.php
      - index.html
      php:
        enabled: true
        fastcgi_pass: unix:/run/php/php8.3-fpm.sock
      headers:
        X-Frame-Options: SAMEORIGIN
        X-Content-Type-Options: nosniff
      magento: true
      ssl:
        enabled: true
        cert: /etc/letsencrypt/live/bank.magento.tattoogoat.com/fullchain.pem
        key: /etc/letsencrypt/live/bank.magento.tattoogoat.com/privkey.pem
        protocols: TLSv1.2 TLSv1.3
        prefer_server_ciphers: false
  csp:
    enabled: true
    level: 3
    policy: 'default-src ''self'' http: https: data: blob: ''unsafe-inline''; script-src
      ''self'' ''unsafe-inline'' ''unsafe-eval''; style-src ''self'' ''unsafe-inline'''
  modsecurity:
    enabled: true
    level: 5
    admin_path: /admin_tattoo
    module_path: /usr/lib/nginx/modules/ngx_http_modsecurity_module.so
  ssl_email: -dry-on
