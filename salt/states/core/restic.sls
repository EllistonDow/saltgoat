{# Install Restic binary from official releases #}

{% set restic_version = salt['pillar.get']('saltgoat:versions:restic', '0.16.3') %}
{% set restic_url = 'https://github.com/restic/restic/releases/download/v{}/restic_{}_linux_amd64.bz2'.format(restic_version, restic_version) %}
{% set restic_binary = '/usr/local/bin/restic' %}
{% set restic_cache_dir = '/var/lib/saltgoat/cache' %}
{% set restic_marker = restic_cache_dir ~ '/restic.version' %}

restic_pkg_deps:
  pkg.installed:
    - names:
      - curl
      - bzip2

restic_cache_dir:
  file.directory:
    - name: {{ restic_cache_dir }}
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

restic_binary_install:
  cmd.run:
    - name: |
        set -euo pipefail
        tmp="$(mktemp /tmp/restic.XXXXXX.bz2)"
        curl -fsSL {{ restic_url }} -o "${tmp}"
        dest="${tmp%.bz2}"
        bunzip2 -f "${tmp}"
        install -m 755 "${dest}" {{ restic_binary }}
        rm -f "${dest}"
        echo "{{ restic_version }}" > {{ restic_marker }}
    - require:
      - pkg: restic_pkg_deps
      - file: restic_cache_dir
    - unless: test -x {{ restic_binary }} && test -f {{ restic_marker }} && grep -qx "{{ restic_version }}" {{ restic_marker }}
