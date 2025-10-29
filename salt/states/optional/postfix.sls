{# Optional Postfix deployment orchestrator #}
{% set postfix_cfg = salt['pillar.get']('mail:postfix', {}) %}
{% set enabled = postfix_cfg.get('enabled', False) %}

{% if enabled %}
include:
  - services.postfix
{% else %}
postfix_disabled_packages:
  pkg.removed:
    - pkgs:
      - postfix
      - mailutils
      - bsd-mailx
      - libsasl2-modules
    - purge: True
    - refresh: False

postfix_disabled_main_cf:
  file.absent:
    - name: /etc/postfix/main.cf
    - require:
      - pkg: postfix_disabled_packages

postfix_disabled_sasl_files:
  file.absent:
    - name: /etc/postfix/sasl_passwd

postfix_disabled_sasl_db:
  file.absent:
    - name: /etc/postfix/sasl_passwd.db

postfix_disabled_service:
  service.dead:
    - name: postfix
    - enable: False
    - require:
      - pkg: postfix_disabled_packages
{% endif %}
