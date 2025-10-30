{#-
  SaltGoat Beacon configuration
  Applies beacon settings defined in pillar saltgoat:beacons
-#}

/var/log/saltgoat:
  file.directory:
    - user: root
    - group: root
    - mode: 750

/var/log/saltgoat/alerts.log:
  file.managed:
    - user: root
    - group: root
    - mode: 640
    - contents: ''
    - replace: False
    - require:
      - file: /var/log/saltgoat

/var/log/saltgoat/chatops.log:
  file.managed:
    - user: root
    - group: root
    - mode: 640
    - contents: ''
    - replace: False
    - require:
      - file: /var/log/saltgoat

/etc/saltgoat:
  file.directory:
    - user: root
    - group: root
    - mode: 750
    - makedirs: True

/etc/saltgoat/telegram.json:
  file.managed:
    - user: root
    - group: root
    - mode: 640
    - source: salt://templates/telegram_config.json.jinja
    - template: jinja
    - require:
      - file: /etc/saltgoat

/etc/saltgoat/chatops.json:
  file.managed:
    - user: root
    - group: root
    - mode: 640
    - source: salt://templates/chatops_config.json.jinja
    - template: jinja
    - require:
      - file: /etc/saltgoat

/opt/saltgoat-telegram:
  file.directory:
    - user: root
    - group: root
    - mode: 755

/opt/saltgoat-reactor:
  file.directory:
    - user: root
    - group: root
    - mode: 755

/opt/saltgoat-reactor/logger.py:
  file.managed:
    - user: root
    - group: root
    - mode: 755
    - source: salt://templates/reactor_logger.py.jinja
    - template: jinja
    - require:
      - file: /opt/saltgoat-reactor

/opt/saltgoat-reactor/reactor_common.py:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - source: salt://templates/reactor_common.py.jinja
    - template: jinja
    - require:
      - file: /opt/saltgoat-reactor

/opt/saltgoat-reactor/telegram_dispatch.py:
  file.managed:
    - user: root
    - group: root
    - mode: 755
    - source: salt://templates/telegram_dispatch.py.jinja
    - template: jinja
    - require:
      - file: /opt/saltgoat-reactor

/opt/saltgoat-reactor/service_autoheal.py:
  file.managed:
    - user: root
    - group: root
    - mode: 755
    - source: salt://templates/service_autoheal.py.jinja
    - template: jinja
    - require:
      - file: /opt/saltgoat-reactor

/opt/saltgoat-reactor/telegram_chatops.py:
  file.managed:
    - user: root
    - group: root
    - mode: 755
    - source: salt://templates/telegram_chatops.py.jinja
    - template: jinja
    - require:
      - file: /opt/saltgoat-reactor

/var/lib/saltgoat:
  file.directory:
    - user: root
    - group: root
    - mode: 750
    - makedirs: True

/var/lib/saltgoat/chatops:
  file.directory:
    - user: root
    - group: root
    - mode: 750
    - require:
      - file: /var/lib/saltgoat

/var/lib/saltgoat/chatops/pending:
  file.directory:
    - user: root
    - group: root
    - mode: 750
    - require:
      - file: /var/lib/saltgoat/chatops

salt-beacon-system-packages:
  pkg.installed:
    - pkgs:
      - python3-pip
      - python3-watchdog
      - python3-requests
      - python3-twilio

/opt/saltstack/salt/lib/python3.10/site-packages/telegram:
  file.directory:
    - user: root
    - group: root
    - mode: 755

/opt/saltstack/salt/lib/python3.10/site-packages/telegram/__init__.py:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - source: salt://templates/telegram_minimal.py.jinja
    - template: jinja
    - require:
      - file: /opt/saltstack/salt/lib/python3.10/site-packages/telegram

salt-beacon-onedir-packages:
  pip.installed:
    - bin_env: /opt/saltstack/salt/bin/pip3
    - require:
      - file: /opt/saltstack/salt/lib/python3.10/site-packages/telegram/__init__.py
    - pkgs:
      - watchdog
      - pyinotify
      - pyroute2
      - twilio

/opt/saltgoat-telegram/telegram:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - require:
      - file: /opt/saltgoat-telegram

/opt/saltgoat-telegram/telegram/__init__.py:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - source: salt://templates/telegram_minimal.py.jinja
    - template: jinja
    - require:
      - file: /opt/saltgoat-telegram/telegram

/etc/salt/minion.d:
  file.directory:
    - user: root
    - group: root
    - mode: 755

/etc/salt/minion.d/saltgoat-pythonpath.conf:
  file.managed:
    - user: root
    - group: root
    - mode: 640
    - contents: |
        pythonpath:
          - /opt/saltgoat-telegram
          - /opt/saltgoat-reactor
    - require:
      - file: /etc/salt/minion.d

/etc/salt/minion.d/beacons.conf:
  file.managed:
    - user: root
    - group: root
    - mode: 640
    - source: salt://templates/beacons.conf.jinja
    - template: jinja
    - require:
      - file: /etc/salt/minion.d

{% if salt['service.available']('salt-minion') %}
salt-minion-beacons-service:
  service.running:
    - name: salt-minion
    - enable: True
    - watch:
      - file: /etc/salt/minion.d/beacons.conf
      - file: /etc/salt/minion.d/saltgoat-pythonpath.conf
{% endif %}
