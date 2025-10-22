# Adminer 数据库管理面板模块

## 概述

Adminer 是一个轻量级的 Web 数据库管理工具，单文件 PHP 应用，提供完整的数据库管理功能。相比 phpMyAdmin，Adminer 更加轻量、快速、安全。

## 功能特性

- **多数据库支持**: MySQL、PostgreSQL、SQLite、MS SQL、Oracle
- **轻量级**: 单文件应用，无需复杂安装
- **快速**: 响应速度快，资源占用少
- **安全**: 内置安全功能，支持多种认证方式
- **主题支持**: 多种界面主题可选
- **移动友好**: 响应式设计，支持移动设备

## 安装要求

- PHP 7.4+ (推荐 PHP 8.3)
- Nginx 或 Apache
- MySQL/PostgreSQL 等数据库

## 使用方法

### 安装 Adminer

```bash
# 安装 Adminer
saltgoat adminer install
```

### 查看状态

```bash
# 查看 Adminer 状态
saltgoat adminer status
```

### 配置管理

```bash
# 查看当前配置
saltgoat adminer config show

# 更新到最新版本
saltgoat adminer config update

# 安装主题
saltgoat adminer config theme nette
```

### 安全配置

```bash
# 配置安全设置
saltgoat adminer security
```

### 备份配置

```bash
# 备份 Adminer 配置
saltgoat adminer backup
```

### 卸载

```bash
# 卸载 Adminer
saltgoat adminer uninstall
```

## 访问地址

安装完成后，通过以下地址访问 Adminer：

- **标准访问**: `http://your-server-ip:8081`
- **安全访问**: `http://your-server-ip:8081/login.php` (推荐)

## 数据库连接

### MySQL 连接

- **服务器**: `localhost` 或 `127.0.0.1`
- **用户名**: MySQL 用户名
- **密码**: MySQL 密码
- **数据库**: 选择要管理的数据库

### PostgreSQL 连接

- **服务器**: `localhost:5432`
- **用户名**: PostgreSQL 用户名
- **密码**: PostgreSQL 密码
- **数据库**: 选择要管理的数据库

## 主题支持

Adminer 支持多种主题：

### 可用主题

- **default**: 默认主题
- **nette**: Nette 风格主题
- **hydra**: Hydra 风格主题
- **konya**: Konya 风格主题

### 安装主题

```bash
# 安装 Nette 主题
saltgoat adminer config theme nette

# 访问主题版本
# http://your-server-ip:8081/nette.php
```

## 安全配置

### 基本安全

1. **IP 限制**: 在 `.htaccess` 中限制访问 IP
2. **服务器限制**: 只允许连接本地数据库
3. **HTTPS**: 建议使用 HTTPS 访问

### 高级安全

```bash
# 配置完整安全设置
saltgoat adminer security
```

这将创建：
- 登录限制脚本
- 服务器访问限制
- 安全头配置

## 与 SaltGoat 集成

Adminer 与 SaltGoat 完美集成：

- **自动配置**: 自动创建 Nginx 配置
- **权限管理**: 使用 www-data 用户权限
- **服务监控**: 集成到 SaltGoat 监控系统
- **备份支持**: 集成 SaltGoat 备份系统

## 故障排除

### 无法访问

1. 检查 Nginx 配置：
   ```bash
   sudo nginx -t
   ```

2. 检查文件权限：
   ```bash
   ls -la /var/www/adminer/
   ```

3. 检查 PHP-FPM 状态：
   ```bash
   systemctl status php8.3-fpm
   ```

### 数据库连接失败

1. 检查数据库服务状态
2. 验证用户名和密码
3. 检查防火墙设置
4. 确认数据库用户权限

### 权限问题

```bash
# 修复文件权限
sudo chown -R www-data:www-data /var/www/adminer/
sudo chmod 644 /var/www/adminer/adminer.php
```

## 性能优化

### Nginx 配置优化

Adminer 的 Nginx 配置已包含：

- 静态文件缓存
- Gzip 压缩
- 安全头设置
- PHP-FPM 优化

### PHP 优化

建议在 `php.ini` 中设置：

```ini
memory_limit = 256M
max_execution_time = 300
upload_max_filesize = 100M
post_max_size = 100M
```

## 最佳实践

1. **定期更新**: 保持 Adminer 为最新版本
2. **安全访问**: 使用 VPN 或限制访问 IP
3. **备份配置**: 定期备份 Adminer 配置
4. **监控访问**: 定期检查访问日志
5. **使用主题**: 选择适合的主题提升用户体验

## 相关命令

```bash
# 查看所有可用命令
saltgoat adminer help

# 完整状态检查
saltgoat adminer status

# 安全配置
saltgoat adminer security

# 备份配置
saltgoat adminer backup
```

## 与 phpMyAdmin 对比

| 特性 | Adminer | phpMyAdmin |
|------|---------|------------|
| 文件大小 | 单文件 (~500KB) | 多文件 (~50MB) |
| 安装复杂度 | 简单 | 复杂 |
| 资源占用 | 低 | 高 |
| 响应速度 | 快 | 较慢 |
| 主题支持 | 多种 | 有限 |
| 移动支持 | 优秀 | 一般 |
