{# Erlang/OTP 26 build from source for RabbitMQ 4.1.x #}

{% set otp_version = salt['pillar.get']('otp_version', '26.2.5') %}
{% set otp_prefix = '/usr/local/otp-' ~ otp_version %}
{% set otp_tar = '/tmp/otp_src_' ~ otp_version ~ '.tar.gz' %}
{% set otp_url = 'https://github.com/erlang/otp/releases/download/OTP-' ~ otp_version ~ '/otp_src_' ~ otp_version ~ '.tar.gz' %}
{% set make_jobs = grains.get('num_cpus', 2) %}

otp_version_guard:
  test.fail_without_changes:
    - name: Erlang/OTP 版本 {{ otp_version }} 低于支持的最小版本 26.2.5
    - onlyif:
      - dpkg --compare-versions {{ otp_version }} lt 26.2.5

otp_build_deps:
  pkg.installed:
    - names:
      - build-essential
      - libncurses-dev
      - libssl-dev
      - libffi-dev
      - libssh-dev
      - unixodbc-dev
      - autoconf

otp_source_tarball:
  cmd.run:
    - name: curl -fsSL -o {{ otp_tar }} {{ otp_url }}
    - creates: {{ otp_tar }}
    - require:
      - pkg: otp_build_deps

otp_build_install:
  cmd.run:
    - cwd: /tmp
    - name: |
        tar -xf {{ otp_tar }} && \
        cd otp_src_{{ otp_version }} && \
        ./configure --prefix={{ otp_prefix }} --without-wx --without-odbc --without-javac --without-debugger --without-observer --without-hipe --without-cosEvent --without-cosTime --without-cosTransactions --without-erl_docgen --without-edoc --without-et --without-megaco && \
        make -j{{ make_jobs }} && make install
    - creates: {{ otp_prefix }}/bin/erl
    - require:
      - cmd: otp_source_tarball

otp_symlink_erl:
  file.symlink:
    - name: /usr/local/bin/erl
    - target: {{ otp_prefix }}/bin/erl
    - force: True
    - require:
      - cmd: otp_build_install

otp_symlink_erlc:
  file.symlink:
    - name: /usr/local/bin/erlc
    - target: {{ otp_prefix }}/bin/erlc
    - force: True
    - require:
      - cmd: otp_build_install

otp_symlink_escript:
  file.symlink:
    - name: /usr/local/bin/escript
    - target: {{ otp_prefix }}/bin/escript
    - force: True
    - require:
      - cmd: otp_build_install
