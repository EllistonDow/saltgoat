# SaltGoat Magento工具集

## 概述

Magento工具集为SaltGoat提供了专门的Magento开发和维护工具，包括CLI工具安装、缓存管理、索引管理等功能。

## 功能特性

### 📦 工具安装
- **n98-magerun2** - Magento 2 CLI工具
- **phpunit** - PHP单元测试框架
- **xdebug** - Xdebug调试工具

### 🗂️ 缓存管理
- 清理所有缓存
- 检查缓存状态
- 预热缓存

### 📊 索引管理
- 重建所有索引
- 检查索引状态

### 🚀 部署管理
- 部署到生产环境

### 💾 备份恢复
- 创建完整备份
- 从备份恢复

### 📈 性能分析
- 分析性能状况

### 🔒 安全扫描
- 扫描安全问题

### 🔄 更新管理
- 更新Magento

## 使用方法

### 基本语法
```bash
saltgoat magetools <command> [options]
```

### 工具安装
```bash
# 安装N98 Magerun2
saltgoat magetools install n98-magerun2

# 安装PHPUnit
saltgoat magetools install phpunit

# 安装Xdebug
saltgoat magetools install xdebug
```

### 缓存管理
```bash
# 清理缓存
saltgoat magetools cache clear

# 检查缓存状态
saltgoat magetools cache status

# 预热缓存
saltgoat magetools cache warm
```

### 索引管理
```bash
# 重建索引
saltgoat magetools index reindex

# 检查索引状态
saltgoat magetools index status
```

### 其他功能
```bash
# 性能分析
saltgoat magetools performance

# 安全扫描
saltgoat magetools security

# 备份
saltgoat magetools backup

# 部署
saltgoat magetools deploy
```

## 工具说明

### N98 Magerun2
Magento 2的官方CLI工具，提供：
- 缓存管理
- 索引重建
- 系统信息查看
- 开发者控制台

### PHPUnit
PHP单元测试框架，用于：
- 测试自定义模块
- 确保代码质量
- 功能回归测试
- 代码覆盖率分析

### Xdebug
PHP调试工具，提供：
- 断点调试
- 性能分析
- 代码覆盖率
- 远程调试

## 帮助信息

```bash
# 查看帮助
saltgoat magetools help
saltgoat help magetools
```

## 注意事项

1. **PHP扩展**: PHPUnit需要dom、mbstring、xml、xmlwriter等扩展
2. **权限**: 某些操作需要sudo权限
3. **Magento环境**: 部分功能需要在Magento项目目录中运行
4. **版本兼容**: 工具版本与Magento版本需要兼容

## 版本信息

- **SaltGoat版本**: v0.6.0+
- **支持Magento**: 1.x, 2.x
- **PHP要求**: 7.4+
