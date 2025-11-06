{% set sysctl_config = '/etc/sysctl.d/99-saltgoat.conf' %}

saltgoat-sysctl-dir:
  file.directory:
    - name: /etc/sysctl.d
    - user: root
    - group: root
    - mode: 755

saltgoat-sysctl-config:
  file.managed:
    - name: {{ sysctl_config }}
    - user: root
    - group: root
    - mode: 644
    - contents: ''
    - replace: False
    - require:
      - file: saltgoat-sysctl-dir

vm-overcommit-memory:
  sysctl.present:
    - name: vm.overcommit_memory
    - value: 1
    - config: {{ sysctl_config }}
    - require:
      - file: saltgoat-sysctl-config
