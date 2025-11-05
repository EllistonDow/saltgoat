docker-compose-dir:
  file.directory:
    - name: /opt/saltgoat/docker
    - user: root
    - group: root
    - mode: 750
    - makedirs: True
