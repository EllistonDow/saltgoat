# SaltGoat Magento 维护系统快速参考

## 🚀 快速开始

### 快速启用 Salt Schedule
```bash
saltgoat magetools cron tank install
```

### 检查状态
```bash
saltgoat magetools cron tank status
```

### 测试功能
```bash
saltgoat magetools cron tank test
```

## 📋 维护命令速查

### 维护模式
```bash
# 检查状态
saltgoat magetools maintenance tank status

# 启用维护模式
saltgoat magetools maintenance tank enable

# 禁用维护模式
saltgoat magetools maintenance tank disable
```

### 维护任务
```bash
# 每日维护（缓存清理、索引重建、会话清理、日志清理）
saltgoat magetools maintenance tank daily

# 每周维护（备份、日志轮换、Valkey刷新（可选）、性能检查）
saltgoat magetools maintenance tank weekly

# 每月维护（完整部署流程）
saltgoat magetools maintenance tank monthly

# 健康检查（Magento状态、数据库连接、缓存状态、索引状态）
saltgoat magetools maintenance tank health

# 创建备份
saltgoat magetools maintenance tank backup

# 清理日志和缓存
saltgoat magetools maintenance tank cleanup

# 完整部署流程
saltgoat magetools maintenance tank deploy
```

> Restic 单站点备份示例：`saltgoat magetools maintenance tank weekly --trigger-restic --restic-site tank --restic-backup-dir /home/Dropbox/tank/snapshots`，必要时可叠加 `--restic-extra-path`。

## ⏰ 定时任务管理

### Salt Schedule 任务
```bash
# 安装
saltgoat magetools cron tank install

# 查看状态
saltgoat magetools cron tank status

# 测试
saltgoat magetools cron tank test

# 查看日志
saltgoat magetools cron tank logs

# 卸载
saltgoat magetools cron tank uninstall
```

> 若主机尚未运行 `salt-minion`，上述命令会自动写入 `/etc/cron.d/magento-maintenance` 并使用系统 Cron；启用 `salt-minion` 后重新执行 `install` 即可切换回 Salt Schedule。

## 📊 定时任务配置

### 执行时间
- **每5分钟** - Magento cron 任务
- **每天凌晨2点** - 每日维护任务
- **每周日凌晨3点** - 每周维护任务
- **每月1日凌晨4点** - 每月维护任务（完整部署流程）
- **每小时** - 健康检查任务

### 日志文件
- `/var/log/magento-cron.log` - Magento cron 任务日志
- `/var/log/magento-maintenance.log` - 维护任务日志
- `/var/log/magento-health.log` - 健康检查日志

## 🔧 故障排除

### 权限问题
```bash
saltgoat magetools permissions fix /var/www/tank
```

### 查看日志
```bash
# 查看维护日志
saltgoat magetools cron tank logs

# 查看系统日志
tail -f /var/log/magento-maintenance.log
tail -f /var/log/magento-health.log
```

### 手动执行维护
```bash
# 手动执行每日维护
saltgoat magetools maintenance tank daily

# 手动执行健康检查
saltgoat magetools maintenance tank health
```

## 📚 详细文档

- [完整维护系统文档](MAGENTO_MAINTENANCE.md)
- [权限管理文档](MAGENTO_PERMISSIONS.md)

## 🎯 最佳实践

1. **使用 Salt Schedule** - 符合 SaltGoat 设计理念
2. **定期检查日志** - 监控维护任务执行情况
3. **备份重要数据** - 执行重要操作前创建备份
4. **监控健康检查** - 及时发现系统问题

---

**提示**: 所有命令都需要在 SaltGoat 项目目录中执行，或使用完整路径。
