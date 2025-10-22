# Magento 2 权限管理最佳实践

## 🎯 **核心原则**

### ✅ **推荐做法**
```bash
# 1. 统一用户权限（官方推荐）
sudo chown -R www-data:www-data /var/www/site1

# 2. 使用 www-data 用户执行 Magento 命令
sudo -u www-data php bin/magento cache:flush
sudo -u www-data php bin/magento setup:upgrade

# 3. 确保目录权限正确
sudo chmod -R 755 /var/www/site1/{app,bin,dev,lib,phpserver,pub,setup,vendor}
sudo chmod 660 /var/www/site1/app/etc/env.php
```

### ❌ **避免的做法**
```bash
# 不要直接使用 sudo php bin/magento
sudo php bin/magento cache:flush  # ❌ 会导致文件归属 root

# 不要混合使用不同用户
sudo php bin/magento setup:upgrade  # ❌ 生成 root 文件
# 然后 Web 服务器无法写入这些文件
```

## 🔧 **SaltGoat 权限管理**

### **自动权限修复**
```bash
# SaltGoat 自动处理权限问题
saltgoat magetools permissions fix /var/www/site1
```

### **权限检查**
```bash
# 检查当前权限状态
saltgoat magetools permissions check /var/www/site1
```

## 📋 **权限问题诊断**

### **常见问题**
1. **文件归属 root**：`ls -la` 显示文件属于 root
2. **Web 访问错误**：500 错误，无法写入缓存
3. **CLI 命令失败**：权限被拒绝

### **解决方案**
```bash
# 1. 修复文件归属
sudo chown -R www-data:www-data /var/www/site1

# 2. 修复目录权限
sudo find /var/www/site1 -type d -exec chmod 755 {} \;
sudo find /var/www/site1 -type f -exec chmod 644 {} \;

# 3. 特殊文件权限
sudo chmod 644 /var/www/site1/app/etc/env.php
sudo chmod 777 /var/www/site1/var
sudo chmod 777 /var/www/site1/pub/media
```

## 🚀 **生产环境建议**

### **1. 用户管理**
- Web 服务器：`www-data`
- CLI 操作：`sudo -u www-data`
- 文件归属：统一 `www-data:www-data`

### **2. 目录权限**
```bash
# 可执行目录
755: app, bin, dev, lib, phpserver, pub, setup, vendor

# 配置文件（可读权限）
644: app/etc/env.php

# 可写目录
775: var, generated, pub/media, pub/static, app/etc
```

### **3. 安全考虑**
- 避免使用 `sudo php bin/magento`
- 定期检查文件权限
- 使用 SaltGoat 的权限管理功能

## 🔍 **故障排除**

### **检查权限**
```bash
# 检查文件归属
ls -la /var/www/site1/var/cache/

# 检查目录权限
ls -ld /var/www/site1/var/

# 检查 Magento 权限
saltgoat magetools permissions check /var/www/site1
```

### **修复权限**
```bash
# 一键修复所有权限
saltgoat magetools permissions fix /var/www/site1

# 手动修复
sudo chown -R www-data:www-data /var/www/site1
sudo chmod -R 755 /var/www/site1
sudo chmod 660 /var/www/site1/app/etc/env.php
```

## 📚 **总结**

**记住这个原则：**
- ✅ **统一用户**：Web 和 CLI 都用 `www-data`
- ✅ **正确权限**：使用 SaltGoat 的权限管理
- ❌ **避免 sudo**：不要直接 `sudo php bin/magento`

这样就能避免权限混乱，确保 Magento 2 正常运行！
