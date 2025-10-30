# SaltGoat 监控集成模块

## 📋 功能概述

监控集成模块提供完整的监控解决方案，包括Prometheus数据收集、Grafana可视化、智能监控配置等功能。

## 🚀 使用方法

### 基本语法
```bash
sudo saltgoat monitoring <service> [options]
```

### 支持的监控服务

| 服务 | 描述 | 功能 |
|------|------|------|
| `prometheus` | Prometheus监控 | 数据收集、存储、查询 |
| `grafana` | Grafana仪表板 | 数据可视化、告警通知 |
| `smart` | 智能监控 | 基于业务场景的自动配置 |
| `dynamic` | 动态监控 | 根据性能需求调整监控级别 |
| `cost` | 成本优化监控 | 平衡监控覆盖度和成本 |

## 📖 使用示例

### Prometheus监控
```bash
# 安装Prometheus监控
sudo saltgoat monitoring prometheus

# 配置不同级别的监控
sudo saltgoat monitoring prometheus low      # 基础监控
sudo saltgoat monitoring prometheus medium   # 中等监控
sudo saltgoat monitoring prometheus high     # 高级监控
sudo saltgoat monitoring prometheus auto    # 自动配置
```

### Grafana仪表板
```bash
# 安装Grafana
sudo saltgoat monitoring grafana

# 配置邮件通知
sudo saltgoat monitoring grafana email <smtp_host> <user> <password> <from_email>

# 测试邮件发送
sudo saltgoat monitoring grafana test-email

# 查看邮件配置帮助
sudo saltgoat monitoring grafana email-help
```

### 智能监控
```bash
# 启用智能监控
sudo saltgoat monitoring smart

# 动态监控配置
sudo saltgoat monitoring dynamic

# 成本优化监控
sudo saltgoat monitoring cost
```

## 📊 监控组件

### Prometheus组件
- **Prometheus Server** - 数据收集和存储
- **Node Exporter** - 系统指标收集
- **Nginx Exporter** - Nginx指标收集
- **MySQL Exporter** - MySQL指标收集

### Grafana组件
- **Grafana Server** - 可视化平台
- **仪表板** - 预配置的监控面板
- **告警规则** - 自动告警配置
- **通知渠道** - 邮件、Telegram等

## 🔧 配置管理

### 访问地址
- **Prometheus**: `http://<server_ip>:9090`
- **Grafana**: `http://<server_ip>:3000` (admin/admin)

### 防火墙配置
监控模块会自动配置防火墙规则：
- Prometheus: 9090端口
- Grafana: 3000端口
- Node Exporter: 9100端口
- Nginx Exporter: 9113端口

### 推荐仪表板
- **Node Exporter**: 1860
- **Nginx**: 12559
- **MySQL**: 7362
- **Valkey**: 11835

## 📁 文件结构

```
modules/monitoring/
├── monitor-integration.sh          # 主监控集成脚本
├── monitoring-levels.sh            # 监控级别配置
├── smart-monitoring.sh             # 智能监控配置
├── dynamic-monitoring.sh           # 动态监控配置
├── cost-optimized-monitoring.sh    # 成本优化监控
├── grafana-email.sh                # Grafana邮件配置
└── README.md                       # 本文档
```

## 🔗 相关功能

- **故障诊断**: `sudo saltgoat diagnose` - 系统故障诊断
- **性能分析**: `sudo saltgoat profile analyze` - 性能分析
- **系统维护**: `sudo saltgoat maintenance` - 系统维护

## 📝 更新日志

- **v0.5.7** - 模块化重构，支持多种监控配置
- 智能监控和动态配置
- 成本优化监控策略
- Grafana邮件通知集成
