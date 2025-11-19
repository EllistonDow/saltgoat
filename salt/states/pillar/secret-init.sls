{# Ensure required secret pillar files exist by copying samples if missing #}

{% set pillar_roots = salt['config.get']('pillar_roots', {}).get('base', ['/home/doge/saltgoat/salt/pillar']) %}
{% set pillar_root = pillar_roots[0] %}
{% set repo_root = pillar_root.rsplit('/salt/pillar', 1)[0] %}
{% set secret_dir = repo_root + '/salt/pillar/secret' %}

pillar_secret_group:
  group.present:
    - name: doge

secret_dir_present:
  file.directory:
    - name: {{ secret_dir }}
    - user: root
    - group: doge
    - mode: 750
    - makedirs: True
    - require:
      - group: pillar_secret_group

magento_schedule_secret:
  file.managed:
    - name: {{ secret_dir }}/magento-schedule.sls
    - source: salt://pillar/magento-schedule.sls.sample
    - user: root
    - group: doge
    - mode: 640
    - require:
      - file: secret_dir_present
    - unless: test -f {{ secret_dir }}/magento-schedule.sls
