# Cockpit 系统管理面板模块

## 概述

Cockpit 是一个现代化的 Web 系统管理界面，提供直观的服务器管理功能。通过 Web 浏览器可以管理系统服务、网络配置、存储、用户账户等。

## 功能特性

- **系统监控**: CPU、内存、磁盘使用率实时监控
- **服务管理**: 启动、停止、重启系统服务
- **网络管理**: 网络接口配置和管理
- **存储管理**: 磁盘分区、挂载点管理
- **用户管理**: 系统用户和组管理
- **容器支持**: Docker 容器管理
- **虚拟机支持**: 虚拟机管理
- **日志查看**: 系统日志实时查看

## 安装要求

- Ubuntu 24.04 LTS
- Root 权限
- 网络连接

## 使用方法

### 安装 Cockpit

```bash
# 安装 Cockpit 及其所有插件
saltgoat cockpit install
```

### 查看状态

```bash
# 查看 Cockpit 服务状态
saltgoat cockpit status
```

### 配置管理

```bash
# 查看当前配置
saltgoat cockpit config show

# 配置防火墙规则
saltgoat cockpit config firewall

# 配置 SSL 证书
saltgoat cockpit config ssl
```

### 日志管理

```bash
# 查看最近 50 行日志
saltgoat cockpit logs

# 查看最近 100 行日志
saltgoat cockpit logs 100
```

### 服务管理

```bash
# 重启 Cockpit 服务
saltgoat cockpit restart
```

### 卸载

```bash
# 卸载 Cockpit
saltgoat cockpit uninstall
```

## 访问地址

安装完成后，通过以下地址访问 Cockpit：

- **HTTPS**: `https://your-server-ip:9091`
- **默认认证**: 使用系统用户账户登录

## 安全配置

### 防火墙配置

Cockpit 默认使用端口 9091，需要开放防火墙：

```bash
# UFW
sudo ufw allow 9091/tcp

# Firewalld
sudo firewall-cmd --permanent --add-port=9091/tcp
sudo firewall-cmd --reload
```

### SSL 证书

Cockpit 默认使用自签名证书。要使用自定义证书：

1. 将证书文件放置在：
   - `/etc/cockpit/ws-certs.d/50-cockpit.cert`
   - `/etc/cockpit/ws-certs.d/50-cockpit.key`

2. 重启 Cockpit 服务：
   ```bash
   saltgoat cockpit restart
   ```

## 插件说明

安装的 Cockpit 插件包括：

- **cockpit-system**: 系统监控和管理
- **cockpit-networkmanager**: 网络管理
- **cockpit-storaged**: 存储管理
- **cockpit-packagekit**: 软件包管理
- **cockpit-machines**: 虚拟机管理

注意：某些插件可能在某些 Ubuntu 版本中不可用，安装脚本会自动跳过不可用的插件。

## 故障排除

### 服务无法启动

```bash
# 检查服务状态
systemctl status cockpit.socket

# 查看详细日志
journalctl -u cockpit.socket -f
```

### 无法访问 Web 界面

1. 检查防火墙配置
2. 确认服务正在运行
3. 检查端口是否被占用

### 权限问题

确保使用有 sudo 权限的用户登录 Cockpit。

## 与 SaltGoat 集成

Cockpit 与 SaltGoat 完美集成，可以：

- 监控 SaltGoat 管理的服务状态
- 查看系统资源使用情况
- 管理 LEMP 栈组件
- 监控 Salt 服务状态

## 最佳实践

1. **定期更新**: 保持 Cockpit 及其插件为最新版本
2. **安全访问**: 使用 VPN 或限制访问 IP
3. **备份配置**: 定期备份 Cockpit 配置文件
4. **监控日志**: 定期检查 Cockpit 日志文件

## 相关命令

```bash
# 查看所有可用命令
saltgoat cockpit help

# 完整状态检查
saltgoat cockpit status

# 配置防火墙
saltgoat cockpit config firewall
```
