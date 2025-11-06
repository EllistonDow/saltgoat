# Uptime Kuma 监控面板模块

## 概述

Uptime Kuma 是一个现代化的自托管监控工具，提供实时服务监控、状态页面和告警通知功能。支持多种监控类型和通知方式，是替代传统监控工具的绝佳选择。

## 功能特性

- **多协议监控**: HTTP/HTTPS、TCP、Ping、DNS、关键词监控
- **实时状态页面**: 美观的公共状态页面
- **多种通知方式**: 邮件、Slack、Discord、Telegram、Webhook
- **响应时间监控**: 详细的响应时间统计
- **证书监控**: SSL 证书过期提醒
- **移动应用**: 支持移动设备访问
- **API 支持**: RESTful API 接口
- **多语言支持**: 支持多种语言界面

## 使用方法

### 安装 Uptime Kuma

```bash
# 安装 Uptime Kuma（Docker Compose）
sudo saltgoat uptime-kuma install
```

### 查看状态

```bash
# 查看 Uptime Kuma 状态
sudo saltgoat uptime-kuma status
```

### 拉取镜像

```bash
# 更新到最新版本镜像
sudo saltgoat uptime-kuma pull
# 重新部署
sudo saltgoat uptime-kuma restart
```

### 日志管理

```bash
# 查看最近 200 行日志
sudo saltgoat uptime-kuma logs
# 查看最近 500 行日志
sudo saltgoat uptime-kuma logs 500
```

### 服务管理

```bash
# 重启 Uptime Kuma 容器
sudo saltgoat uptime-kuma restart

# 停止容器
sudo saltgoat uptime-kuma down
```

### 卸载

```bash
# 清理旧版 systemd 安装
sudo saltgoat uptime-kuma cleanup-legacy
# 停止并移除容器
sudo saltgoat uptime-kuma down
```

## 访问地址

安装完成后，通过以下地址访问 Uptime Kuma：

- **Web 界面**: `http://your-server-ip:3001`（或经 Traefik 暴露的域名）
- **默认账户**: admin / admin
- **状态页面**: `https://status.example.com/status/your-status-page`

## 监控类型

### HTTP/HTTPS 监控

- **URL 监控**: 监控网站可用性
- **关键词监控**: 检查页面内容
- **响应时间**: 监控响应速度
- **状态码**: 检查 HTTP 状态码

### 系统监控

- **Ping 监控**: 网络连通性检查
- **TCP 监控**: 端口连通性检查
- **DNS 监控**: DNS 解析检查
- **证书监控**: SSL 证书过期检查

### 数据库监控

- **MySQL**: 数据库连接监控
- **PostgreSQL**: 数据库连接监控
- **Redis**: 缓存服务监控

## 通知配置

### 邮件通知

1. 在 Uptime Kuma 中添加邮件通知
2. 配置 SMTP 服务器信息
3. 设置告警规则

### 即时通讯通知

- **Slack**: 集成 Slack 工作区
- **Discord**: Discord 服务器通知
- **Telegram**: Telegram Bot 通知
- **微信**: 企业微信通知

### Webhook 通知

- 自定义 Webhook URL
- JSON 格式数据推送
- 支持自定义告警内容

## 状态页面

### 创建状态页面

1. 在 Uptime Kuma 中创建状态页面
2. 选择要显示的监控项目
3. 自定义页面样式和布局
4. 发布状态页面

### 状态页面特性

- **实时更新**: 自动更新服务状态
- **自定义样式**: 支持 CSS 自定义
- **多语言**: 支持多种语言
- **移动友好**: 响应式设计

## 性能优化

### 系统优化

- **内存限制**: 建议分配 512MB+ 内存
- **CPU 优化**: 多核 CPU 提升性能
- **存储优化**: SSD 存储提升 I/O 性能

### 监控优化

- **监控间隔**: 合理设置监控间隔
- **并发限制**: 控制并发监控数量
- **数据保留**: 设置合理的数据保留期

## 安全配置

### 访问控制

1. **修改默认密码**: 立即修改 admin 密码
2. **IP 限制**: 限制访问 IP 地址
3. **HTTPS**: 使用 HTTPS 访问
4. **防火墙**: 配置防火墙规则

### 数据安全

- **定期备份**: 定期备份监控数据
- **权限控制**: 合理设置用户权限
- **日志审计**: 启用访问日志记录

## 故障排除

### 服务无法启动

```bash
# 检查容器状态与日志
sudo saltgoat uptime-kuma status
sudo saltgoat uptime-kuma logs
```

### 无法访问 Web 界面

1. 检查防火墙配置
2. 确认服务正在运行
3. 检查端口是否被占用

### 监控失败

1. 检查网络连接
2. 验证监控目标可达性
3. 检查通知配置

### 性能问题

1. 检查系统资源使用
2. 优化监控间隔
3. 减少并发监控数量

## 最佳实践

1. **定期更新**: 保持 Uptime Kuma 为最新版本
2. **合理监控**: 设置合理的监控间隔
3. **告警配置**: 配置合适的告警阈值
4. **数据备份**: 定期备份监控数据
5. **安全访问**: 使用 VPN 或限制访问 IP
6. **状态页面**: 创建公共状态页面
7. **通知测试**: 定期测试通知功能

## 相关命令

> 安装命令会根据 Pillar 自动写入 `nginx:sites:uptime-kuma`、生成透传配置，并在缺少证书时调用 `saltgoat nginx add-ssl uptime-kuma <domain>` 自动申请 HTTPS。如需查看其它子命令，可执行 `saltgoat uptime-kuma help`。

## 与其他监控工具对比

| 特性 | Uptime Kuma | Nagios | Zabbix | Prometheus |
|------|-------------|--------|--------|------------|
| 安装复杂度 | 简单 | 复杂 | 中等 | 中等 |
| 资源占用 | 低 | 高 | 高 | 中等 |
| 界面友好度 | 优秀 | 一般 | 良好 | 良好 |
| 状态页面 | 内置 | 插件 | 插件 | 插件 |
| 移动支持 | 优秀 | 一般 | 良好 | 良好 |
| 自托管 | 是 | 是 | 是 | 是 |
