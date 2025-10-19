# SaltGoat 定时任务配置
# /srv/salt/schedules/saltgoat.sls

# 内存监控任务
schedule:
  memory_monitor:
    function: cmd.run
    args: ['/usr/local/bin/saltgoat-memory-monitor']
    when: '*/5 * * * *'  # 每5分钟
    splay: 30  # 随机延迟0-30秒
    maxrunning: 1  # 最多运行1个实例
    returner: mysql  # 结果存储到数据库

# 系统更新任务
schedule:
  system_update:
    function: pkg.upgrade
    when: '0 3 * * 0'  # 每周日凌晨3点
    splay: 600  # 随机延迟0-10分钟
    maxrunning: 1

# 日志清理任务
schedule:
  log_cleanup:
    function: cmd.run
    args: ['find /var/log -name "*.log" -mtime +7 -delete']
    when: '0 1 * * 0'  # 每周日凌晨1点
    splay: 300  # 随机延迟0-5分钟

# 数据库备份任务
schedule:
  database_backup:
    function: cmd.run
    args: ['mysqldump --all-databases > /backup/db_$(date +%Y%m%d_%H%M%S).sql']
    when: '0 2 * * *'  # 每天凌晨2点
    splay: 300  # 随机延迟0-5分钟
    onlyif: 'test -d /backup'

# 服务健康检查
schedule:
  service_health_check:
    function: service.status
    args: ['nginx', 'mysql', 'php8.3-fpm', 'valkey', 'opensearch', 'rabbitmq']
    when: '*/10 * * * *'  # 每10分钟
    splay: 60  # 随机延迟0-1分钟
    returner: mysql

# 磁盘空间检查
schedule:
  disk_space_check:
    function: disk.usage
    when: '0 */6 * * *'  # 每6小时
    splay: 300  # 随机延迟0-5分钟
    onlyif: 'test -d /var/log/saltgoat'

# 安全更新检查
schedule:
  security_updates:
    function: pkg.list_upgrades
    when: '0 4 * * 1'  # 每周一凌晨4点
    splay: 600  # 随机延迟0-10分钟
    returner: mysql
