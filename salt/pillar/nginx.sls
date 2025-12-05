nginx:
  package: nginx
  service: nginx
  default_site: false
  client_max_body_size: 64m
  gzip: true
  sites:
    bdgy:
      enabled: true
      server_name:
      - bdgyoo.com
      - www.bdgyoo.com
      listen:
      - port: 80
      - port: 443
        ssl: true
      root: /var/www/bdgy
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
        cert: /etc/letsencrypt/live/bdgyoo.com/fullchain.pem
        key: /etc/letsencrypt/live/bdgyoo.com/privkey.pem
        protocols: TLSv1.2 TLSv1.3
        prefer_server_ciphers: false
        redirect: true
    sava:
      enabled: true
      server_name:
      - savageneedles.com
      - www.savageneedles.com
      listen:
      - port: 80
      - port: 443
        ssl: true
      root: /var/www/sava
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
        cert: /etc/letsencrypt/live/savageneedles.com/fullchain.pem
        key: /etc/letsencrypt/live/savageneedles.com/privkey.pem
        protocols: TLSv1.2 TLSv1.3
        prefer_server_ciphers: false
        redirect: true
    ipwa:
      enabled: true
      server_name:
      - ipowerwatch.com
      - www.ipowerwatch.com
      listen:
      - port: 80
      - port: 443
        ssl: true
      root: /var/www/ipwa
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
        cert: /etc/letsencrypt/live/ipowerwatch.com/fullchain.pem
        key: /etc/letsencrypt/live/ipowerwatch.com/privkey.pem
        protocols: TLSv1.2 TLSv1.3
        prefer_server_ciphers: false
        redirect: true
    ntca:
      enabled: true
      server_name:
      - nucleartattooca.com
      - www.nucleartattooca.com
      listen:
      - port: 80
      - port: 443
        ssl: true
      root: /var/www/ntca
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
        cert: /etc/letsencrypt/live/nucleartattooca.com/fullchain.pem
        key: /etc/letsencrypt/live/nucleartattooca.com/privkey.pem
        protocols: TLSv1.2 TLSv1.3
        prefer_server_ciphers: false
        redirect: true
    hawk:
      enabled: true
      server_name:
      - hawktattoosupply.com
      - www.hawktattoosupply.com
      listen:
      - port: 80
      - port: 443
        ssl: true
      root: /var/www/hawk
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
        cert: /etc/letsencrypt/live/hawktattoosupply.com/fullchain.pem
        key: /etc/letsencrypt/live/hawktattoosupply.com/privkey.pem
        protocols: TLSv1.2 TLSv1.3
        prefer_server_ciphers: false
        redirect: true
    ambi:
      enabled: true
      server_name:
      - ambitiontattoosupply.com
      - www.ambitiontattoosupply.com
      listen:
      - port: 80
      - port: 443
        ssl: true
      root: /var/www/ambi
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
        cert: /etc/letsencrypt/live/ambitiontattoosupply.com/fullchain.pem
        key: /etc/letsencrypt/live/ambitiontattoosupply.com/privkey.pem
        protocols: TLSv1.2 TLSv1.3
        prefer_server_ciphers: false
        redirect: true
    papa:
      enabled: true
      server_name:
      - papatattoo.com
      - www.papatattoo.com
      listen:
      - port: 80
      - port: 443
        ssl: true
      root: /var/www/papa
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
        cert: /etc/letsencrypt/live/papatattoo.com/fullchain.pem
        key: /etc/letsencrypt/live/papatattoo.com/privkey.pem
        protocols: TLSv1.2 TLSv1.3
        prefer_server_ciphers: false
        redirect: true
  ssl_email: ssl@tschenfeng.com
  csp:
    enabled: true
    level: 3
    policy: 'default-src ''self'' http: https: data: blob: ''unsafe-inline''; script-src
      ''self'' ''unsafe-inline'' ''unsafe-eval''; style-src ''self'' ''unsafe-inline'''
  modsecurity:
    enabled: true
    level: 5
    admin_path: /admin_tattoo
