{#-
  SaltGoat Reactor configuration
-#}

/etc/salt/master.d:
  file.directory:
    - user: root
    - group: salt
    - mode: 750

/etc/salt/master.d/reactor.conf:
  file.managed:
    - user: root
    - group: salt
    - mode: 640
    - contents: |
        reactor:
          - 'salt/beacon/*/service/*':
            - salt://reactor/service_autoheal.sls
          - 'salt/beacon/*/load/*':
            - salt://reactor/resource_alert.sls
          - 'salt/beacon/*/mem/*':
            - salt://reactor/resource_alert.sls
          - 'salt/beacon/*/memusage/*':
            - salt://reactor/resource_alert.sls
          - 'salt/beacon/*/diskusage/*':
            - salt://reactor/resource_alert.sls
          - 'salt/beacon/*/inotify/*':
            - salt://reactor/config_change.sls
          - 'salt/beacon/*/watchdog/*':
            - salt://reactor/config_change.sls
          - 'salt/beacon/*/pkg/*':
            - salt://reactor/package_update.sls
          - 'salt/beacon/*/telegram_bot_msg/*':
            - salt://reactor/telegram_chatops.sls
          - 'saltgoat/backup/*':
            - salt://reactor/backup_notification.sls
    - require:
      - file: /etc/salt/master.d

/srv/salt/reactor:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

include:
  - .reactor-files

salt-master-reactor-service:
  service.running:
    - name: salt-master
    - enable: True
    - watch:
      - file: /etc/salt/master.d/reactor.conf
    - onlyif:
      - test -x /usr/bin/systemctl
      - systemctl list-unit-files | grep -q '^salt-master.service'
