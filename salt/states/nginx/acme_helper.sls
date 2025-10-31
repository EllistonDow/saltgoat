{% set site = salt['pillar.get']('nginx:current_site') %}
{% set root = salt['pillar.get']('nginx:sites:' ~ site ~ ':root', '/var/www/' ~ site) %}
{% set magento = salt['pillar.get']('nginx:sites:' ~ site ~ ':magento', False) %}
{% set webroot_override = salt['pillar.get']('nginx:sites:' ~ site ~ ':ssl_webroot', '') %}

{% if webroot_override %}
{% set webroot = webroot_override.rstrip('/') %}
{% elif magento %}
{% set webroot = root.rstrip('/') + '/pub' %}
{% else %}
{% set webroot = root.rstrip('/') %}
{% endif %}

nginx-acme-webroot-{{ site }}:
  file.directory:
    - name: {{ webroot }}/.well-known/acme-challenge
    - user: www-data
    - group: www-data
    - mode: 755
    - makedirs: True

nginx-acme-clean-{{ site }}:
  file.replace:
    - name: /etc/nginx/sites-available/{{ site }}
    - pattern: '\n# SALTGOAT-ACME-{{ site }}-START[\s\S]*?# SALTGOAT-ACME-{{ site }}-END'
    - repl: ''

nginx-acme-snippet-{{ site }}:
  file.replace:
    - name: /etc/nginx/sites-available/{{ site }}
    - pattern: '(\s*include\s+.*nginx\.conf\.sample;\s*)'
    - repl: "\\1    # SALTGOAT-ACME-{{ site }}-START\\n    location ^~ /.well-known/acme-challenge/ {\\n        root {{ webroot }};\\n        try_files $uri =404;\\n    }\\n    # SALTGOAT-ACME-{{ site }}-END\\n"
    - append_if_not_found: False

nginx-acme-reload-{{ site }}:
  service.running:
    - name: nginx
    - enable: True
    - reload: True
    - watch:
      - file: nginx-acme-snippet-{{ site }}
