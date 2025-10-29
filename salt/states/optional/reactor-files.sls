/srv/salt/reactor/service_autoheal.sls:
  file.managed:
    - source: salt://reactor/service_autoheal.sls
    - user: root
    - group: root
    - mode: 640

/srv/salt/reactor/resource_alert.sls:
  file.managed:
    - source: salt://reactor/resource_alert.sls
    - user: root
    - group: root
    - mode: 640

/srv/salt/reactor/config_change.sls:
  file.managed:
    - source: salt://reactor/config_change.sls
    - user: root
    - group: root
    - mode: 640

/srv/salt/reactor/package_update.sls:
  file.managed:
    - source: salt://reactor/package_update.sls
    - user: root
    - group: root
    - mode: 640

/srv/salt/reactor/backup_notification.sls:
  file.managed:
    - source: salt://reactor/backup_notification.sls
    - user: root
    - group: root
    - mode: 640
