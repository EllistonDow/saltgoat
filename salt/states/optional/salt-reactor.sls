{#-
  SaltGoat Reactor configuration
-#}

/etc/salt/master.d:
  file.directory:
    - user: root
    - group: root
    - mode: 755

/etc/salt/master.d/reactor.conf:
  file.managed:
    - user: root
    - group: root
    - mode: 640
    - contents: |
        reactor:
          - 'salt/beacon/*/service/':
            - salt://reactor/service_autoheal.sls
          - 'salt/beacon/*/load/*':
            - salt://reactor/resource_alert.sls
          - 'salt/beacon/*/mem/*':
            - salt://reactor/resource_alert.sls
          - 'salt/beacon/*/diskusage/*':
            - salt://reactor/resource_alert.sls
          - 'salt/beacon/*/inotify/*':
            - salt://reactor/config_change.sls
          - 'salt/beacon/*/pkg/*':
            - salt://reactor/package_update.sls
    - require:
      - file: /etc/salt/master.d

/srv/salt/reactor:
  file.directory:
    - user: root
    - group: root
    - mode: 755

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
