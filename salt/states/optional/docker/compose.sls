docker-compose-dir:
  file.directory:
    - name: /opt/saltgoat/docker
    - user: root
    - group: root
    - mode: 750
    - makedirs: True

docker-shared-network:
  cmd.run:
    - name: docker network create saltgoat-core
    - unless: docker network inspect saltgoat-core >/dev/null 2>&1
    - require:
      - file: docker-compose-dir
