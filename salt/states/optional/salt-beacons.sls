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
    - require:
      - file: /var/log/saltgoat

/etc/salt/minion.d:
  file.directory:
    - user: root
    - group: root
    - mode: 755

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
{% endif %}
