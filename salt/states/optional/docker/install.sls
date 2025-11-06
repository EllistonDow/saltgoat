docker-packages:
  pkg.installed:
    - pkgs:
      - ca-certificates
      - curl
      - gnupg
      - lsb-release

docker-gpg-key:
  cmd.run:
    - name: |
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
    - creates: /etc/apt/keyrings/docker.gpg
    - require:
      - pkg: docker-packages

{% set arch = salt['grains.get']('osarch', 'amd64') %}
{% set codename = salt['grains.get']('oscodename', 'noble') %}

docker-apt-source:
  file.managed:
    - name: /etc/apt/sources.list.d/docker.list
    - contents: |
        deb [arch={{ arch }} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu {{ codename }} stable
    - template: jinja
    - require:
      - cmd: docker-gpg-key

docker-engine:
  pkg.installed:
    - refresh: True
    - pkgs:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-buildx-plugin
      - docker-compose-plugin
    - require:
      - file: docker-apt-source

docker-service:
  service.running:
    - name: docker
    - enable: True
    - require:
      - pkg: docker-engine
