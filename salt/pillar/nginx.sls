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
        fastcgi_pass: unix:/run/php/php8.3-fpm.sock
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
        '/':
          raw: |
            proxy_pass http://127.0.0.1:8082;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
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
