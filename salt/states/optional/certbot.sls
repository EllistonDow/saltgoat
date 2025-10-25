# Certbot 安装和配置


# 添加 Certbot 仓库
add_certbot_repository:
  cmd.run:
    - name: |
        snap install core; snap refresh core
        snap install --classic certbot
        ln -sf /snap/bin/certbot /usr/bin/certbot
    - unless: test -f /usr/bin/certbot

# 创建 Certbot 配置目录
create_certbot_config_dir:
  file.directory:
    - name: /etc/letsencrypt
    - user: root
    - group: root
    - mode: 755
    - require:
      - cmd: add_certbot_repository

# 创建 Certbot 配置
configure_certbot:
  file.managed:
    - name: /etc/letsencrypt/cli.ini
    - contents: |
        # Certbot configuration
        email = admin@example.com
        agree-tos = true
        non-interactive = true
        expand = true
        text = true
        renew-hook = systemctl reload nginx
    - require:
      - file: create_certbot_config_dir

# 创建 Certbot 自动续期脚本
create_certbot_renewal_script:
  file.managed:
    - name: /etc/cron.d/certbot-renewal
    - contents: |
        # Certbot automatic renewal
        0 12 * * * root /usr/bin/certbot renew --quiet --post-hook "systemctl reload nginx"
    - require:
      - cmd: add_certbot_repository

# 创建 Nginx SSL 配置模板
create_nginx_ssl_template:
  file.managed:
    - name: /etc/nginx/snippets/ssl.conf
    - contents: |
        # SSL configuration
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;
        ssl_stapling on;
        ssl_stapling_verify on;
        
        # Security headers
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options DENY always;
        add_header X-Content-Type-Options nosniff always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    - require:
      - cmd: add_certbot_repository

# 创建 SSL 证书申请脚本
create_ssl_certificate_script:
  file.managed:
    - name: /usr/local/bin/request-ssl-cert
    - contents: |
        #!/bin/bash
        # SSL certificate request script for multi-site environment
        
        if [ -z "$1" ]; then
            echo "Usage: $0 <domain_name> [additional_domains...]"
            echo "Example: $0 example.com www.example.com"
            exit 1
        fi
        
        DOMAIN=$1
        EMAIL="admin@example.com"
        
        if [ -z "$EMAIL" ]; then
            echo "Error: SSL_EMAIL not set in Salt Pillars"
            exit 1
        fi
        
        # Build domain list
        DOMAINS="-d $DOMAIN"
        shift
        for domain in "$@"; do
            DOMAINS="$DOMAINS -d $domain"
        done
        
        echo "Requesting SSL certificate for: $DOMAINS"
        certbot --nginx $DOMAINS --email $EMAIL --agree-tos --non-interactive
        
        if [ $? -eq 0 ]; then
            echo "SSL certificate has been successfully installed!"
            echo "Your site is now available at https://$DOMAIN"
        else
            echo "Failed to install SSL certificate"
            exit 1
        fi
    - mode: 755
    - require:
      - cmd: add_certbot_repository

# 测试 Certbot 安装
test_certbot:
  cmd.run:
    - name: certbot --version
    - require:
      - cmd: add_certbot_repository
