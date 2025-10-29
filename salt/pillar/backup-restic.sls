{% set secrets = pillar.get('secrets', {}) %}
{% set restic_secrets = secrets.get('restic', {}) %}

backup:
  restic:
    enabled: true
    repo: "{{ restic_secrets.get('repo', '/var/backups/restic/repos/default') }}"
    password: "{{ restic_secrets.get('password', 'ChangeMeRestic!') }}"
    paths:
{% for item in restic_secrets.get('paths', ['/var/www/example']) %}
    - {{ item }}
{% endfor %}
    excludes:
    - '*.log'
    - var/cache
    - var/page_cache
    - generated/code
    - generated/metadata
    tags:
{% for tag in restic_secrets.get('tags', ['example', 'magento']) %}
    - {{ tag }}
{% endfor %}
    extra_backup_args: --one-file-system
    check_after_backup: true
    timer: daily
    randomized_delay: 15m
    service_user: "{{ restic_secrets.get('service_user', 'root') }}"
    repo_owner: "{{ restic_secrets.get('repo_owner', 'root') }}"
    retention:
      keep_last: 7
      keep_daily: 7
      keep_weekly: 4
      keep_monthly: 6
      prune: true
