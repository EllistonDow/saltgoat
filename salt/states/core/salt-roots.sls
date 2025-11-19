{# Ensure master/minion file_roots & pillar_roots point to the repo, and salt user can read #}

{% set pillar_roots = salt['config.get']('pillar_roots', {}).get('base', ['/home/doge/saltgoat/salt/pillar']) %}
{% set pillar_root = pillar_roots[0] %}
{% set repo_root = pillar_root.rsplit('/salt/pillar', 1)[0] %}
{% set file_roots = [repo_root + '/salt/states', repo_root + '/salt'] %}

/etc/salt/master.d:
  file.directory:
    - user: root
    - group: salt
    - mode: 750
    - makedirs: True

/etc/salt/master.d/saltgoat.conf:
  file.managed:
    - user: root
    - group: salt
    - mode: 640
    - makedirs: True
    - contents: |
        file_roots:
          base:
{% for path in file_roots %}
            - {{ path }}
{% endfor %}

        pillar_roots:
          base:
            - {{ pillar_root }}

/etc/salt/minion.d/saltgoat-roots.conf:
  file.managed:
    - user: root
    - group: root
    - mode: 640
    - makedirs: True
    - contents: |
        file_roots:
          base:
{% for path in file_roots %}
            - {{ path }}
{% endfor %}
        pillar_roots:
          base:
            - {{ pillar_root }}

salt_user_group:
  group.present:
    - name: doge

salt_user_membership:
  user.present:
    - name: salt
    - groups:
      - doge
    - require:
      - group: salt_user_group

restart_salt_master_after_roots:
  service.running:
    - name: salt-master
    - enable: True
    - reload: True
    - watch:
      - file: /etc/salt/master.d/saltgoat.conf

restart_salt_minion_after_roots:
  service.running:
    - name: salt-minion
    - enable: True
    - reload: True
    - watch:
      - file: /etc/salt/minion.d/saltgoat-roots.conf
