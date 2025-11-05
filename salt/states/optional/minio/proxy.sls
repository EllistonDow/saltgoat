{% set minio = salt['pillar.get']('minio', {}) %}
{% set proxy = minio.get('proxy', {}) %}
{% if proxy.get('enabled') and proxy.get('domain') %}
{% set domain = proxy.get('domain') %}
{% set console_enabled = proxy.get('console_enabled', True) %}
{% set console_domain = proxy.get('console_domain') or domain %}
{% set ssl_email = proxy.get('ssl_email', salt['pillar.get']('ssl_email', 'admin@example.com')) %}
{% set site_id = proxy.get('site_id', 'minio-' + domain.replace('.', '-')) %}
{% set acme_root = proxy.get('acme_webroot', '/var/lib/saltgoat/minio-proxy/acme') %}
{% set listen_address = minio.get('listen_address', '127.0.0.1:9000') %}
{% set console_address = minio.get('console_address', '127.0.0.1:9001') %}
{% set api_upstream = proxy.get('api_upstream', listen_address) %}
{% if '://' not in api_upstream %}
{% set api_upstream = 'http://' + api_upstream %}
{% endif %}
{% set console_upstream = proxy.get('console_upstream', console_address) %}
{% if '://' not in console_upstream %}
{% set console_upstream = 'http://' + console_upstream %}
{% endif %}
{% set cert_dir = '/etc/letsencrypt/live/' + domain %}
{% set cert_path = cert_dir + '/fullchain.pem' %}
{% set key_path = cert_dir + '/privkey.pem' %}

minio-proxy-acme-dir:
  file.directory:
    - name: {{ acme_root }}
    - user: www-data
    - group: www-data
    - mode: 755
    - makedirs: True

/etc/nginx/sites-available/{{ site_id }}:
  file.managed:
    - source: salt://optional/minio/minio-nginx.conf.jinja
    - template: jinja
    - context:
        domain: {{ domain }}
        console_domain: {{ console_domain }}
        console_enabled: {{ console_enabled }}
        api_upstream: {{ api_upstream }}
        console_upstream: {{ console_upstream }}
        acme_root: {{ acme_root }}
        cert_path: {{ cert_path }}
        key_path: {{ key_path }}
    - require:
      - file: minio-proxy-acme-dir

/etc/nginx/sites-enabled/{{ site_id }}:
  file.symlink:
    - target: /etc/nginx/sites-available/{{ site_id }}
    - force: True
    - require:
      - file: /etc/nginx/sites-available/{{ site_id }}

minio-proxy-certbot:
  cmd.run:
    - name: >
        certbot certonly --webroot -w {{ acme_root }} -d {{ domain }}{% if console_enabled and console_domain and console_domain != domain %} -d {{ console_domain }}{% endif %}
        --email {{ ssl_email }} --agree-tos --non-interactive --expand
    - unless: test -f {{ cert_path }}
    - require:
      - file: /etc/nginx/sites-enabled/{{ site_id }}

minio-proxy-nginx:
  service.running:
    - name: nginx
    - enable: True
    - reload: True
    - require:
      - file: /etc/nginx/sites-enabled/{{ site_id }}
    - watch:
      - file: /etc/nginx/sites-available/{{ site_id }}
      - cmd: minio-proxy-certbot
{% else %}
minio-proxy-disabled:
  test.succeed_without_changes:
    - name: minio proxy disabled
{% endif %}
