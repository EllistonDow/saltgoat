{# Ensure required secret pillar files exist by copying samples if missing #}

{% set pillar_roots = salt['config.get']('pillar_roots', {}).get('base', ['/home/doge/saltgoat/salt/pillar']) %}
{% set pillar_root = pillar_roots[0] %}
{% set repo_root = pillar_root.rsplit('/salt/pillar', 1)[0] %}
{% set secret_dir = repo_root + '/salt/pillar/secret' %}
{% set secret_templates = [
  'saltgoat',
  'auth',
  'nginx',
  'magento-optimize',
  'magento-valkey',
  'monitoring',
  'notifications',
  'salt-beacons',
  'telegram-topics',
  'magento-schedule'
] %}

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

{% for name in secret_templates %}
ensure_secret_{{ name | replace('-', '_') }}:
  file.managed:
    - name: {{ secret_dir }}/{{ name }}.sls
    - source: file://{{ repo_root }}/salt/pillar/{{ name }}.sls.sample
    - user: root
    - group: doge
    - mode: 640
    - require:
      - file: secret_dir_present
    - unless: test -f {{ secret_dir }}/{{ name }}.sls
{% endfor %}
