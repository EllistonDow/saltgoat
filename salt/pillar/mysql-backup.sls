mysql_backup:
  enabled: true
  backup_dir: /var/backups/mysql/xtrabackup
  mysql_user: backup
  mysql_password: "StrongBackUpP@ss"
  mysql_host: localhost
  mysql_port: 3306
  socket: /var/run/mysqld/mysqld.sock
  connection_user: root
  connection_password: "StrongBackUpP@ss"
  retention_days: 7
  prepare_backup: false
  compress: false
  extra_args: ''
  service_user: root
  repo_owner: root
  timer: daily
  randomized_delay: 15m
