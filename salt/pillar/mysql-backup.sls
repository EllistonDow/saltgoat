{% set mysql_root_password = salt['pillar.get']('secrets.mysql_password', pillar.get('mysql_password', 'ChangeMeRoot!')) %}
{% set mysql_backup_password = salt['pillar.get']('secrets.mysql_backup_password', pillar.get('mysql_backup_password', 'ChangeMeBackup!')) %}

mysql_backup:
  enabled: true
  backup_dir: /var/backups/mysql/xtrabackup
  mysql_user: backup
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
  repo_owner: root
  timer: daily
  randomized_delay: 15m
