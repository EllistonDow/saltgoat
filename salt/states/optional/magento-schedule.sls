# SaltGoat Magento 2 定时维护任务（Salt Schedule 优先，自动回退 Cron）
# salt/states/optional/magento-schedule.sls

{% set site_name = pillar.get('site_name', 'tank') %}
{% set maintenance_script = '/usr/local/bin/magento-maintenance-salt' %}
{% set salt_minion_service = salt['file.file_exists']('/lib/systemd/system/salt-minion.service') or salt['file.file_exists']('/etc/systemd/system/salt-minion.service') %}

/usr/local/bin/magento-maintenance-salt:
  file.managed:
    - source: salt://scripts/magento-maintenance-salt.sh
    - user: root
    - group: root
    - mode: 755

/var/log/magento-cron.log:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - contents: ''

/var/log/magento-maintenance.log:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - contents: ''

/var/log/magento-health.log:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - contents: ''

{% if salt_minion_service %}

/etc/cron.d/magento-maintenance:
  file.absent

{% for name, command, cron in [
  ('magento-cron', "cd /var/www/{{ site_name }} && sudo -u www-data php bin/magento cron:run >> /var/log/magento-cron.log 2>&1", '*/5 * * * *'),
  ('magento-daily-maintenance', "{{ maintenance_script }} {{ site_name }} daily >> /var/log/magento-maintenance.log 2>&1", '0 2 * * *'),
  ('magento-weekly-maintenance', "{{ maintenance_script }} {{ site_name }} weekly >> /var/log/magento-maintenance.log 2>&1", '0 3 * * 0'),
  ('magento-monthly-maintenance', "{{ maintenance_script }} {{ site_name }} monthly >> /var/log/magento-maintenance.log 2>&1", '0 4 1 * *'),
  ('magento-health-check', "{{ maintenance_script }} {{ site_name }} health >> /var/log/magento-health.log 2>&1", '0 * * * *')
] %}
magento_schedule_{{ name }}:
  schedule.present:
    - name: {{ name }}
    - function: cmd.run
    - job_args:
      - "{{ command }}"
    - job_kwargs:
        shell: /bin/bash
    - cron: '{{ cron }}'
    - run_on_start: False
    - persistent: True
    - maxrunning: 1
{% endfor %}

{% if salt['service.available']('salt-minion') %}
salt-minion-schedule-service:
  service.running:
    - name: salt-minion
    - enable: True
    - watch:
      - schedule: magento_schedule_magento-cron
      - schedule: magento_schedule_magento-daily-maintenance
      - schedule: magento_schedule_magento-weekly-maintenance
      - schedule: magento_schedule_magento-monthly-maintenance
      - schedule: magento_schedule_magento-health-check
{% endif %}

{% else %}

/etc/cron.d/magento-maintenance:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - contents: |
        # Magento 2 定时维护任务（Salt Schedule 不可用，回退系统 Cron）
        */5 * * * * www-data cd /var/www/{{ site_name }} && sudo -u www-data php bin/magento cron:run >> /var/log/magento-cron.log 2>&1
        0 2 * * * root {{ maintenance_script }} {{ site_name }} daily >> /var/log/magento-maintenance.log 2>&1
        0 3 * * 0 root {{ maintenance_script }} {{ site_name }} weekly >> /var/log/magento-maintenance.log 2>&1
        0 4 1 * * root {{ maintenance_script }} {{ site_name }} monthly >> /var/log/magento-maintenance.log 2>&1
        0 * * * * root {{ maintenance_script }} {{ site_name }} health >> /var/log/magento-health.log 2>&1

cron-service-magento:
  service.running:
    - name: cron
    - enable: True

{% endif %}
