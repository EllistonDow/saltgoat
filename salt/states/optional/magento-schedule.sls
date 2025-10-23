# SaltGoat Magento 2 定时维护任务
# salt/states/optional/magento-schedule.sls

# 检测系统内存并设置变量
detect_system_memory:
  cmd.run:
    - name: |
        TOTAL_MEMORY_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        TOTAL_MEMORY_GB=$((TOTAL_MEMORY_KB / 1024 / 1024))
        
        # 根据内存大小确定配置级别
        if [ $TOTAL_MEMORY_GB -ge 256 ]; then
          echo "enterprise" > /tmp/memory_level
        elif [ $TOTAL_MEMORY_GB -ge 128 ]; then
          echo "high" > /tmp/memory_level
        elif [ $TOTAL_MEMORY_GB -ge 48 ]; then
          echo "medium" > /tmp/memory_level
        elif [ $TOTAL_MEMORY_GB -ge 16 ]; then
          echo "standard" > /tmp/memory_level
        else
          echo "minimal" > /tmp/memory_level
        fi
    - creates: /tmp/memory_level

# 创建 Magento 维护脚本
create_magento_maintenance_script:
  file.managed:
    - name: /usr/local/bin/magento-maintenance-salt
    - source: salt://scripts/magento-maintenance-salt.sh
    - mode: 755
    - user: root
    - group: root
    - require:
      - cmd: detect_system_memory

# 创建定时任务配置文件
create_cron_config:
  file.managed:
    - name: /etc/cron.d/magento-maintenance
    - contents: |
        # Magento 2 定时维护任务
        # 每5分钟执行 Magento cron
        */5 * * * * www-data cd /var/www/{{ pillar.get('site_name', 'tank') }} && sudo -u www-data php bin/magento cron:run >> /var/log/magento-cron.log 2>&1
        
        # 每日维护任务 - 每天凌晨2点执行
        0 2 * * * root /usr/local/bin/magento-maintenance-salt {{ pillar.get('site_name', 'tank') }} daily >> /var/log/magento-maintenance.log 2>&1
        
        # 每周维护任务 - 每周日凌晨3点执行
        0 3 * * 0 root /usr/local/bin/magento-maintenance-salt {{ pillar.get('site_name', 'tank') }} weekly >> /var/log/magento-maintenance.log 2>&1
        
        # 每月维护任务 - 每月1日凌晨4点执行（完整部署流程）
        0 4 1 * * root /usr/local/bin/magento-maintenance-salt {{ pillar.get('site_name', 'tank') }} monthly >> /var/log/magento-maintenance.log 2>&1
        
        # 健康检查任务 - 每小时执行
        0 * * * * root /usr/local/bin/magento-maintenance-salt {{ pillar.get('site_name', 'tank') }} health >> /var/log/magento-health.log 2>&1
    - mode: 644
    - user: root
    - group: root
    - require:
      - file: create_magento_maintenance_script

# 创建日志文件
create_log_files:
  file.managed:
    - name: /var/log/magento-cron.log
    - mode: 644
    - user: root
    - group: root
    - require:
      - file: create_cron_config

create_maintenance_log:
  file.managed:
    - name: /var/log/magento-maintenance.log
    - mode: 644
    - user: root
    - group: root
    - require:
      - file: create_cron_config

create_health_log:
  file.managed:
    - name: /var/log/magento-health.log
    - mode: 644
    - user: root
    - group: root
    - require:
      - file: create_cron_config

# 重启 cron 服务以应用配置
restart_cron_service:
  service.running:
    - name: cron
    - enable: True
    - require:
      - file: create_cron_config