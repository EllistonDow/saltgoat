{#-
  Manage a single SaltGoat automation script.
-#}

include:
  - optional.automation.init

{% set default_cfg = salt['pillar.get']('saltgoat:automation', {}) %}
{% set automation = pillar.get('automation', {}) %}
{% set scripts_dir = automation.get('scripts_dir', default_cfg.get('scripts_dir')) %}
{% set owner = automation.get('owner', default_cfg.get('owner', 'root')) %}
{% set group = automation.get('group', default_cfg.get('group', owner)) %}
{% set script_cfg = automation.get('script', {}) %}

{% if not script_cfg %}
saltgoat-automation-script-missing:
  test.fail_without_changes:
    - comment: 'automation.script state requires automation:script pillar data'
{% else %}
{% set default_scripts_dir = scripts_dir or automation.get('base_dir', default_cfg.get('base_dir', '/srv/saltgoat/automation')) + '/scripts' %}
{% set script_name = script_cfg.get('name', 'automation-script') %}
{% set script_path = script_cfg.get('path', default_scripts_dir + '/' + script_name + '.sh') %}
{% set ensure = script_cfg.get('ensure', 'present') %}
{% set mode = script_cfg.get('mode', default_cfg.get('script_mode', '755')) %}

{% if ensure == 'absent' %}
{{ script_path }}:
  file.absent
{% else %}
{{ script_path }}:
  file.managed:
    - user: {{ script_cfg.get('user', owner) }}
    - group: {{ script_cfg.get('group', group) }}
    - mode: {{ mode }}
    - makedirs: True
    - contents_pillar: automation:script:body
    - replace: {{ script_cfg.get('overwrite', False) }}
    - require:
      - file: {{ default_scripts_dir }}
{% endif %}
{% endif %}
