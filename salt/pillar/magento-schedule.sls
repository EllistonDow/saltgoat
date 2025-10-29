# Magento mysqldump Salt Schedule 示例

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
