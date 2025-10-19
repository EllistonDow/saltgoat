# SaltGoat 定时任务配置
# /srv/salt/schedules/saltgoat.sls

# 内存监控任务
memory_monitor:
  schedule.present:
    - function: cmd.run
    - args: ['echo "Memory check at $(date)"']
    - when: '*/5 * * * *'  # 每5分钟
    - splay: 30  # 随机延迟0-30秒
    - maxrunning: 1  # 最多运行1个实例

# 系统更新任务
system_update:
  schedule.present:
    - function: cmd.run
    - args: ['echo "System update check at $(date)"']
    - when: '0 3 * * 0'  # 每周日凌晨3点
    - splay: 600  # 随机延迟0-10分钟
    - maxrunning: 1

# 日志清理任务
log_cleanup:
  schedule.present:
    - function: cmd.run
    - args: ['echo "Log cleanup at $(date)"']
    - when: '0 1 * * 0'  # 每周日凌晨1点
    - splay: 300  # 随机延迟0-5分钟

# 服务健康检查
service_health_check:
  schedule.present:
    - function: cmd.run
    - args: ['echo "Service health check at $(date)"']
    - when: '*/10 * * * *'  # 每10分钟
    - splay: 60  # 随机延迟0-1分钟
