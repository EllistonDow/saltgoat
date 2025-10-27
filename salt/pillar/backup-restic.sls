backup:
  restic:
    enabled: true
    repo: /home/doge/Dropbox/bank/snapshots
    password: "(tBO1+IV^+2WAVokIEqgH1Jn"
    paths:
    - /var/www/bank
    excludes:
    - '*.log'
    - var/cache
    - var/page_cache
    - generated/code
    - generated/metadata
    tags:
    - bank
    - magento
    extra_backup_args: --one-file-system
    check_after_backup: true
    timer: daily
    randomized_delay: 15m
    service_user: root
    repo_owner: doge
    retention:
      keep_last: 7
      keep_daily: 7
      keep_weekly: 4
      keep_monthly: 6
      prune: true
