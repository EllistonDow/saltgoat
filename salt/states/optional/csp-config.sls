# SaltGoat CSP 配置状态
# 基于 Salt Pillar 动态配置 CSP

{% set csp_enabled = salt['pillar.get']('csp_enabled', True) %}
{% set csp_policy = salt['pillar.get']('csp_policy', "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'") %}

# 更新 Nginx 主配置中的 CSP
nginx-csp-config:
  file.replace:
    - name: /etc/nginx/nginx.conf
    - pattern: '^(\s*)add_header Content-Security-Policy.*$'
    - repl: |
        {% if csp_enabled %}
        \1add_header Content-Security-Policy "{{ csp_policy }}" always;
        {% else %}
        \1# add_header Content-Security-Policy "{{ csp_policy }}" always;
        {% endif %}
    - backup: minion

# 测试 Nginx 配置
nginx-config-test:
  cmd.run:
    - name: /usr/sbin/nginx -t -c /etc/nginx/nginx.conf
    - require:
      - file: nginx-csp-config

# 重新加载 Nginx
nginx-reload:
  service.running:
    - name: nginx
    - reload: True
    - require:
      - cmd: nginx-config-test
