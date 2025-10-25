# SaltGoat 系统优化模块

## 📋 功能概述

系统优化模块提供全面的系统性能优化功能，包括自动调优、性能测试、基准测试、网络速度测试等。

## 🚀 使用方法

### 基本语法
```bash
saltgoat <optimization_command> [options]
```

### 支持的优化功能

| 功能 | 命令 | 描述 |
|------|------|------|
| `optimize` | 系统优化 | Magento2优化、LEMP环境优化 |
| `auto-tune` | 自动调优 | 基于系统资源的自动优化 |
| `benchmark` | 基准测试 | 系统性能基准测试 |
| `speedtest` | 网络测试 | 网络速度和延迟测试 |

## 📖 使用示例

### 系统优化
```bash
# Magento2 优化（自动档位）
saltgoat optimize magento

# 指定档位与站点
saltgoat optimize magento --profile medium --site shop01

# 仅预览变更并输出报告
saltgoat optimize magento --dry-run --show-results
```

### 自动调优
```bash
# 自动调优系统
saltgoat auto-tune

# 查看调优建议
saltgoat auto-tune --suggest
```

### 基准测试
```bash
# 运行基准测试
saltgoat benchmark

# 指定测试类型
saltgoat benchmark cpu
saltgoat benchmark memory
saltgoat benchmark disk
```

### 网络测试
```bash
# 网络速度测试
saltgoat speedtest

# 指定服务器测试
saltgoat speedtest --server 1234

# 详细测试结果
saltgoat speedtest --verbose
```

## 🔧 优化功能详解

### Magento2 优化
- **档位映射**: 根据内存自动匹配 `low → enterprise` 或通过 `--profile` 指定
- **Nginx 优化**: 工作进程、连接数、Gzip 规则（Salt 原生管理）
- **PHP 优化**: 内存限制、OPcache、FPM 池参数、CLI 配置
- **MySQL 优化**: InnoDB 缓冲池、日志、连接数等通过 `ini.options_present` 应用
- **Valkey 优化**: 最大内存、淘汰策略、连接策略块替换
- **OpenSearch 优化**: 缓冲区、线程池等通过 `file.blockreplace` 保持幂等
- **RabbitMQ 优化**: 使用 Salt 模板发布 Magento 专用配置
- **优化报告**: 结果写入 `/var/lib/saltgoat/reports/magento-optimize-summary.txt`，`--show-results` 可随时查看

### 自动调优
- **CPU优化**: 基于CPU核心数的进程配置
- **内存优化**: 基于内存大小的缓存配置
- **磁盘优化**: 基于磁盘类型的I/O配置
- **网络优化**: 基于网络带宽的连接配置

### 基准测试
- **CPU测试**: 计算性能、多核性能
- **内存测试**: 读写速度、延迟测试
- **磁盘测试**: I/O性能、随机读写
- **网络测试**: 带宽测试、延迟测试

### 网络测试
- **速度测试**: 下载、上传速度
- **延迟测试**: 网络延迟、抖动
- **服务器选择**: 自动选择最优服务器
- **结果分析**: 详细的测试报告

## 📊 优化结果

### Magento2优化结果
```
==========================================
Magento2优化完成
==========================================
[SUCCESS] Nginx配置已优化
[SUCCESS] PHP-FPM配置已优化
[SUCCESS] MySQL配置已优化
[SUCCESS] Valkey配置已优化
[SUCCESS] OpenSearch配置已优化
[SUCCESS] RabbitMQ配置已优化
==========================================
优化参数:
- Nginx worker_processes: 8
- Nginx worker_connections: 1024
- PHP memory_limit: 512M
- MySQL query_cache_size: 128M
- Valkey maxmemory: 2G
==========================================
```

### 自动调优结果
```
==========================================
自动调优完成
==========================================
[INFO] 系统资源分析:
- CPU核心数: 8
- 内存大小: 64GB
- 磁盘类型: SSD
- 网络带宽: 1Gbps
==========================================
[SUCCESS] 优化建议已应用
[INFO] 预计性能提升: 25-40%
==========================================
```

### 基准测试结果
```
==========================================
基准测试结果
==========================================
[INFO] CPU性能: 8500分 (优秀)
[INFO] 内存性能: 9200分 (优秀)
[INFO] 磁盘性能: 7800分 (良好)
[INFO] 网络性能: 6800分 (良好)
==========================================
[INFO] 总体评分: 8075分 (良好)
[INFO] 建议优化: 磁盘I/O和网络延迟
==========================================
```

## 📁 文件结构

```
modules/optimization/
├── optimize.sh            # 主优化脚本
├── auto-tune.sh          # 自动调优脚本
├── benchmark.sh          # 基准测试脚本
├── speedtest.sh          # 网络测试脚本
└── README.md             # 本文档
```

## 🔗 相关功能

- **故障诊断**: `saltgoat diagnose` - 系统故障诊断
- **性能分析**: `saltgoat profile analyze` - 性能分析
- **系统维护**: `saltgoat maintenance` - 系统维护

## 📝 更新日志

- **v0.5.7** - 模块化重构，完善优化功能
- Magento2专业优化配置
- 智能自动调优算法
- 全面的基准测试套件
- 网络性能测试工具
