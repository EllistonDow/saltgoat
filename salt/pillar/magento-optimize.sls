magento_optimize:
  profile: "auto"
  site: "bank"
  site_hint: "bank"
  env_path: "/var/www/bank/app/etc/env.php"
  site_root: "/var/www/bank"
  detection_status: "found"
  overrides: {}

# Salt Schedule mysqldump 示例，用于站点级数据库备份
# 若你拥有多个站点，可复制以下块并调整为各自的数据库/路径
magento_schedule:
  mysql_dump_jobs:
    - name: bankmage-dump-hourly
      cron: '0 * * * *'
      database: bankmage
      backup_dir: /home/doge/Dropbox/bank/databases
      repo_owner: doge
    - name: tankmage-dump-every-2h
      cron: '0 */2 * * *'
      database: tankmage
      backup_dir: /home/doge/Dropbox/tank/databases
      repo_owner: doge
