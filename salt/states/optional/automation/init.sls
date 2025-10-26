{#-
  SaltGoat automation directory bootstrap
-#}

{% set default_cfg = salt['pillar.get']('saltgoat:automation', {}) %}
{% set automation = pillar.get('automation', {}) %}
{% set base_dir = automation.get('base_dir', default_cfg.get('base_dir', '/srv/saltgoat/automation')) %}
{% set scripts_dir = automation.get('scripts_dir', default_cfg.get('scripts_dir', base_dir + '/scripts')) %}
{% set jobs_dir = automation.get('jobs_dir', default_cfg.get('jobs_dir', base_dir + '/jobs')) %}
{% set logs_dir = automation.get('logs_dir', default_cfg.get('logs_dir', base_dir + '/logs')) %}
{% set owner = automation.get('owner', default_cfg.get('owner', 'root')) %}
{% set group = automation.get('group', default_cfg.get('group', owner)) %}
{% set dir_mode = automation.get('mode', default_cfg.get('mode', '750')) %}
{% set logs_mode = automation.get('logs_mode', default_cfg.get('logs_mode', '750')) %}

{{ base_dir }}:
  file.directory:
    - user: {{ owner }}
    - group: {{ group }}
    - mode: {{ dir_mode }}
    - makedirs: True

{{ scripts_dir }}:
  file.directory:
    - user: {{ owner }}
    - group: {{ group }}
    - mode: {{ dir_mode }}
    - makedirs: True
    - require:
      - file: {{ base_dir }}

{{ jobs_dir }}:
  file.directory:
    - user: {{ owner }}
    - group: {{ group }}
    - mode: 750
    - makedirs: True
    - require:
      - file: {{ base_dir }}

{{ logs_dir }}:
  file.directory:
    - user: {{ owner }}
    - group: {{ group }}
    - mode: {{ logs_mode }}
    - makedirs: True
    - require:
      - file: {{ base_dir }}
