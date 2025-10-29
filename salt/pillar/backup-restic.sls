backup:
  restic:
    enabled: true
    repo: /var/backups/restic/default
    password: vi1uhqfHtElVKih^Z2=NT9o(
    paths:
    - /var/www
    excludes:
    - '*.log'
    - var/cache
    - var/page_cache
    - generated/code
    - generated/metadata
    tags:
    - magento
    extra_backup_args: --one-file-system
    check_after_backup: true
    timer: daily
    randomized_delay: 15m
    service_user: root
    repo_owner: root
    retention:
      keep_last: 7
      keep_daily: 7
      keep_weekly: 4
      keep_monthly: 6
      prune: true
