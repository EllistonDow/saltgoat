{# Postfix service management #}
{% from "services/postfix/map.jinja" import cfg, serialized_cfg with context %}

{% set service_name = cfg.service %}
{% set packages = cfg.packages %}
{% set sasl_enabled = cfg.auth.get('username') and cfg.auth.get('password') %}

postfix_packages:
  pkg.installed:
    - pkgs: {{ packages }}

{% if cfg.aliases %}
postfix_aliases_file:
  file.managed:
    - name: /etc/postfix/aliases
    - user: root
    - group: root
    - mode: 644
    - contents: |
{%- for alias in cfg.aliases %}
        {{ alias.get('name') }}: {{ alias.get('value') }}
{%- endfor %}
    - require:
      - pkg: postfix_packages

postfix_aliases_db:
  cmd.run:
    - name: newaliases
    - onchanges:
      - file: postfix_aliases_file
    - require:
      - pkg: postfix_packages
{% endif %}

postfix_main_cf:
  file.managed:
    - name: /etc/postfix/main.cf
    - source: salt://services/postfix/main.cf.jinja
    - template: jinja
    - context:
        cfg_serialized: {{ serialized_cfg }}
    - user: root
    - group: root
    - mode: 640
    - require:
      - pkg: postfix_packages

{% if sasl_enabled %}
postfix_sasl_passwd:
  file.managed:
    - name: {{ cfg.sasl_password_file }}
    - user: root
    - group: root
    - mode: 600
    - contents: |
        [{{ cfg.relay.host }}]:{{ cfg.relay.port }} {{ cfg.auth.username }}:{{ cfg.auth.password }}
    - require:
      - pkg: postfix_packages

postfix_sasl_db:
  cmd.run:
    - name: postmap {{ cfg.sasl_password_file }}
    - require:
      - file: postfix_sasl_passwd
    - onchanges:
      - file: postfix_sasl_passwd
{% else %}
postfix_sasl_cleanup_file:
  file.absent:
    - name: {{ cfg.sasl_password_file }}
    - require:
      - pkg: postfix_packages

postfix_sasl_cleanup_db:
  file.absent:
    - name: {{ cfg.sasl_password_file }}.db
{% endif %}

postfix_check_config:
  cmd.run:
    - name: postfix check
    - require:
      - file: postfix_main_cf
    - onchanges:
      - file: postfix_main_cf
{% if sasl_enabled %}
      - cmd: postfix_sasl_db
{% endif %}
{% if cfg.aliases %}
      - cmd: postfix_aliases_db
{% endif %}

postfix_service:
  service.running:
    - name: {{ service_name }}
    - enable: True
    - require:
      - pkg: postfix_packages
      - cmd: postfix_check_config
    - watch:
      - file: postfix_main_cf
{% if sasl_enabled %}
      - cmd: postfix_sasl_db
{% endif %}
{% if cfg.aliases %}
      - cmd: postfix_aliases_db
{% endif %}
