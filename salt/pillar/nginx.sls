nginx:
  sites:
    pwas:
      enabled: true
      server_name:
      - pwas.magento.tattoogoat.com
      ssl_email: ssl@tschenfeng.com
      listen:
      - port: 80
      - port: 443
        ssl: true
      root: /var/www/pwas
      index:
      - index.php
      - index.html
      php:
        enabled: true
        pool: magento-pwas
      headers:
        X-Frame-Options: SAMEORIGIN
        X-Content-Type-Options: nosniff
      magento: true
      ssl:
        enabled: true
        cert: /etc/letsencrypt/live/pwas.magento.tattoogoat.com/fullchain.pem
        key: /etc/letsencrypt/live/pwas.magento.tattoogoat.com/privkey.pem
        protocols: TLSv1.2 TLSv1.3
        prefer_server_ciphers: false
        redirect: true
    pwa-frontend:
      enabled: true
      server_name:
      - pwa.magento.tattoogoat.com
      listen:
      - port: 80
      - port: 443
        ssl: true
      root: /var/www/pwas/pwa-studio/packages/venia-concept/.proxy-root
      index:
      - index.html
      php:
        enabled: false
      locations:
        /:
          raw: 'proxy_pass http://127.0.0.1:8082;

            proxy_set_header Host $host;

            proxy_set_header X-Real-IP $remote_addr;

            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

            proxy_set_header X-Forwarded-Proto $scheme;

            proxy_http_version 1.1;

            proxy_set_header Connection "";

            '
      headers:
        X-Frame-Options: SAMEORIGIN
        X-Content-Type-Options: nosniff
      ssl:
        enabled: true
        cert: /etc/letsencrypt/live/pwa.magento.tattoogoat.com/fullchain.pem
        key: /etc/letsencrypt/live/pwa.magento.tattoogoat.com/privkey.pem
        protocols: TLSv1.2 TLSv1.3
        prefer_server_ciphers: false
        redirect: true
    bank:
      enabled: true
      server_name:
      - bank.magento.tattoogoat.com
      listen:
      - port: 80
      - port: 443
        ssl: true
      root: /var/www/bank
      index:
      - index.php
      - index.html
      php:
        enabled: true
        pool: magento-bank
      headers:
        X-Frame-Options: SAMEORIGIN
        X-Content-Type-Options: nosniff
      magento: true
      magento_run:
        type: store
        code: default
      ssl:
        enabled: true
        cert: /etc/letsencrypt/live/bank.magento.tattoogoat.com/fullchain.pem
        key: /etc/letsencrypt/live/bank.magento.tattoogoat.com/privkey.pem
        protocols: TLSv1.2 TLSv1.3
        prefer_server_ciphers: false
        redirect: true
    duobank:
      enabled: true
      server_name:
      - duobank.magento.tattoogoat.com
      listen:
      - port: 80
      - port: 443
        ssl: true
      root: /var/www/bank
      index:
      - index.php
      - index.html
      php:
        enabled: true
        pool: magento-bank
      magento_run:
        type: store
        code: duobank
      headers:
        X-Frame-Options: SAMEORIGIN
        X-Content-Type-Options: nosniff
      magento: true
      ssl:
        enabled: true
        cert: /etc/letsencrypt/live/duobank.magento.tattoogoat.com/fullchain.pem
        key: /etc/letsencrypt/live/duobank.magento.tattoogoat.com/privkey.pem
        protocols: TLSv1.2 TLSv1.3
        prefer_server_ciphers: false
        redirect: true
    tank:
      enabled: true
      server_name:
      - tank.magento.tattoogoat.com
      listen:
      - port: 80
      - port: 443
        ssl: true
      root: /var/www/tank
      index:
      - index.php
      - index.html
      php:
        enabled: true
        pool: magento-tank
      magento: true
      magento_run:
        type: store
        code: en
      headers:
        X-Frame-Options: SAMEORIGIN
        X-Content-Type-Options: nosniff
      ssl:
        enabled: true
        cert: /etc/letsencrypt/live/tank.magento.tattoogoat.com/fullchain.pem
        key: /etc/letsencrypt/live/tank.magento.tattoogoat.com/privkey.pem
        protocols: TLSv1.2 TLSv1.3
        prefer_server_ciphers: false
        redirect: true
    treebank:
      enabled: true
      server_name:
      - treebank.magento.tattoogoat.com
      listen:
      - port: 80
      - port: 443
        ssl: true
      root: /var/www/bank
      index:
      - index.php
      - index.html
      php:
        enabled: true
        pool: magento-bank
      headers:
        X-Frame-Options: SAMEORIGIN
        X-Content-Type-Options: nosniff
      magento: true
      magento_run:
        type: store
        code: treebank
      ssl:
        enabled: true
        cert: /etc/letsencrypt/live/treebank.magento.tattoogoat.com/fullchain.pem
        key: /etc/letsencrypt/live/treebank.magento.tattoogoat.com/privkey.pem
        protocols: TLSv1.2 TLSv1.3
        prefer_server_ciphers: false
        redirect: true
    uptime-kuma:
      enabled: true
      server_name:
      - status.magento.tattoogoat.com
      listen:
      - port: 80
      - port: 443
        ssl: true
      root: /var/www/uptime-kuma
      php:
        enabled: false
      headers:
        X-Frame-Options: SAMEORIGIN
        X-Content-Type-Options: nosniff
      ssl:
        enabled: true
        cert: /etc/letsencrypt/live/status.magento.tattoogoat.com/fullchain.pem
        key: /etc/letsencrypt/live/status.magento.tattoogoat.com/privkey.pem
        protocols: TLSv1.2 TLSv1.3
        prefer_server_ciphers: false
        redirect: true
      locations:
        /:
          directives:
          - proxy_pass http://127.0.0.1:18080
          - proxy_set_header Host $host
          - proxy_set_header X-Real-IP $remote_addr
          - proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for
          - proxy_set_header X-Forwarded-Proto $scheme
        /.well-known/acme-challenge/:
          directives:
          - alias /var/www/uptime-kuma/.well-known/acme-challenge/
          - try_files $uri =404
    foo:
      enabled: true
      server_name:
      - foo.com
      listen:
      - port: 80
      root: /var/www/foo
      index:
      - index.php
      - index.html
      php:
        enabled: true
        fastcgi_pass: unix:/run/php/php8.3-fpm.sock
      headers:
        X-Frame-Options: SAMEORIGIN
        X-Content-Type-Options: nosniff
    mattermost:
      enabled: true
      server_name:
      - chat.magento.tattoogoat.com
      listen:
      - port: 80
      - port: 443
        ssl: true
      root: /var/www/mattermost
      php:
        enabled: false
      headers:
        X-Frame-Options: SAMEORIGIN
        X-Content-Type-Options: nosniff
      ssl:
        enabled: true
        cert: /etc/letsencrypt/live/chat.magento.tattoogoat.com/fullchain.pem
        key: /etc/letsencrypt/live/chat.magento.tattoogoat.com/privkey.pem
        protocols: TLSv1.2 TLSv1.3
        prefer_server_ciphers: false
        redirect: true
      locations:
        /:
          directives:
          - proxy_pass http://127.0.0.1:18080
          - proxy_set_header Host $host
          - proxy_set_header X-Real-IP $remote_addr
          - proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for
          - proxy_set_header X-Forwarded-Proto $scheme
        /.well-known/acme-challenge/:
          directives:
          - alias /var/www/mattermost/.well-known/acme-challenge/
          - try_files $uri =404
  ssl_email: ssl@tschenfeng.com
