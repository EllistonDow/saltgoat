{% import_yaml 'secret/saltgoat.sls' as saltgoat_secret %}
{% set mysql_root_password = pillar.get('auth:mysql:root_password', pillar.get('mysql_password', '+LxhloGXLOzD3oOPkwKZrXGO')) %}
{% set mysql_backup_password = saltgoat_secret.get('mysql_backup_password') %}

{% if not mysql_backup_password %}
mysql_backup_missing_password:
  test.fail_without_changes:
    - comment: "mysql_backup_password 未定义。请在 salt/pillar/secret/saltgoat.sls 设置后再渲染 Pillar。"
{% else %}
mysql_backup:
  enabled: true
  backup_dir: /var/backups/mysql/xtrabackup
  mysql_user: mysqlbackup
  mysql_password: "{{ mysql_backup_password }}"
  mysql_host: localhost
  mysql_port: 3306
  socket: /var/run/mysqld/mysqld.sock
  connection_user: root
  connection_password: "{{ mysql_root_password }}"
  retention_days: 7
  prepare_backup: false
  compress: false
  extra_args: ''
  service_user: root
  repo_owner: doge
  timer: daily
  randomized_delay: 15m
{% endif %}
