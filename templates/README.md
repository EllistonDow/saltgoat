# SaltGoat 模板文件

这个目录包含SaltGoat的预设模板文件，用于自动化任务和站点配置。

## 自动化模板

### 系统更新模板
- **脚本**: `system-update.sh`
- **任务**: `system-update`
- **调度**: 每周日凌晨2点
- **功能**: 自动更新系统包

### 备份清理模板
- **脚本**: `backup-cleanup.sh`
- **任务**: `backup-cleanup`
- **调度**: 每周一凌晨3点
- **功能**: 清理旧备份文件

### 日志轮转模板
- **脚本**: `log-rotation.sh`
- **任务**: `log-rotation`
- **调度**: 每天凌晨1点
- **功能**: 轮转和压缩日志文件

### 安全扫描模板
- **脚本**: `security-scan.sh`
- **任务**: `security-scan`
- **调度**: 每周三凌晨4点
- **功能**: 执行安全扫描

## 使用方法

```bash
# 创建系统更新模板
saltgoat automation templates system-update

# 创建备份清理模板
saltgoat automation templates backup-cleanup

# 创建日志轮转模板
saltgoat automation templates log-rotation

# 创建安全扫描模板
saltgoat automation templates security-scan
```

## 扩展模板

你可以在这个目录中添加自定义模板文件，用于：
- 站点配置模板
- 数据库备份模板
- 监控脚本模板
- 自定义自动化任务模板

## 注意事项

- 模板文件应该包含适当的注释
- 确保脚本具有执行权限
- 测试模板功能后再部署到生产环境
