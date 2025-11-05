{% set docker = salt['pillar.get']('docker', {}) %}

include:
  - optional.docker.install
  - optional.docker.compose
