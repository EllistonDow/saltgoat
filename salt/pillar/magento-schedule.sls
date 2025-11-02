# Magento mysqldump Salt Schedule（默认空列表，按需配置）

magento_schedule:
  mysql_dump_jobs:
    - name: bankmage-dump-hourly
      cron: '0 * * * *'
      database: bankmage
      backup_dir: /home/doge/Dropbox/bank/databases
      repo_owner: doge
      site: bank
    - name: tankmage-dump-every-2h
      cron: '0 */2 * * *'
      database: tankmage
      backup_dir: /home/doge/Dropbox/tank/databases
      repo_owner: doge
      site: tank
  api_watchers:
    - name: bank-api-watch
      cron: '*/5 * * * *'
      site: bank
      kinds:
        - orders
        - customers
    - name: tank-api-watch
      cron: '*/5 * * * *'
      site: tank
      kinds:
        - orders
        - customers
  stats_jobs:
    - name: bank-stats-daily
      cron: '5 6 * * *'
      site: bank
      period: daily
      telegram_thread: 2634
    - name: bank-stats-weekly
      cron: '15 6 * * 1'
      site: bank
      period: weekly
      no_telegram: true
      telegram_thread: 2634
    - name: bank-stats-monthly
      cron: '20 6 1 * *'
      site: bank
      period: monthly
      telegram_thread: 2634
    - name: pwas-stats-daily
      cron: '7 6 * * *'
      site: pwas
      period: daily
      telegram_thread: 2635
    - name: pwas-stats-weekly
      cron: '17 6 * * 1'
      site: pwas
      period: weekly
      no_telegram: true
      telegram_thread: 2635
    - name: pwas-stats-monthly
      cron: '22 6 1 * *'
      site: pwas
      period: monthly
      telegram_thread: 2635
    - name: tank-stats-daily
      cron: '10 6 * * *'
      site: tank
      period: daily
      telegram_thread: 2636
    - name: tank-stats-weekly
      cron: '20 6 * * 1'
      site: tank
      period: weekly
      no_telegram: true
      telegram_thread: 2636
    - name: tank-stats-monthly
      cron: '25 6 1 * *'
      site: tank
      period: monthly
      telegram_thread: 2636
