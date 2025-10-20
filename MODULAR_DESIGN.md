# SaltGoat 模块化架构设计

## 当前问题
- 单文件 1529 行，难以维护
- 功能硬编码，扩展困难
- 配置分散，管理复杂

## 建议的模块化结构

```
saltgoat/
├── saltgoat                    # 主入口脚本（简化版）
├── modules/                     # 功能模块目录
│   ├── mysql.sh                # MySQL 管理模块
│   ├── nginx.sh                # Nginx 管理模块
│   ├── rabbitmq.sh             # RabbitMQ 管理模块
│   ├── memory.sh                # 内存监控模块
│   ├── schedule.sh              # 定时任务模块
│   ├── permissions.sh           # 权限管理模块
│   └── system.sh                # 系统管理模块
├── config/                      # 配置文件目录
│   ├── modules.conf             # 模块配置文件
│   └── defaults.conf            # 默认配置
├── lib/                         # 公共库
│   ├── logger.sh                # 日志函数
│   ├── utils.sh                 # 工具函数
│   └── validator.sh             # 参数验证
└── templates/                   # 模板文件
    ├── nginx-site.conf          # Nginx 站点模板
    └── mysql-user.sql           # MySQL 用户模板
```

## 模块化优势

### 1. 易于扩展
- 新功能只需添加新模块文件
- 主脚本自动发现和加载模块
- 模块间相互独立

### 2. 易于维护
- 每个模块职责单一
- 代码量小，易于理解
- 可以独立测试和调试

### 3. 易于配置
- 统一的配置管理
- 模块级别的配置
- 支持动态配置

### 4. 易于部署
- 可以选择性安装模块
- 支持模块的启用/禁用
- 便于打包和分发

## 实现方案

### 主脚本结构
```bash
#!/bin/bash
# SaltGoat 主入口脚本

# 加载公共库
source lib/logger.sh
source lib/utils.sh
source lib/validator.sh

# 加载配置
source config/defaults.conf

# 自动发现和加载模块
load_modules() {
    for module in modules/*.sh; do
        if [[ -f "$module" ]]; then
            source "$module"
        fi
    done
}

# 主命令路由
main() {
    load_modules
    case "$1" in
        "mysql") mysql_handler "$@" ;;
        "nginx") nginx_handler "$@" ;;
        "memory") memory_handler "$@" ;;
        # ... 其他模块
    esac
}
```

### 模块结构示例
```bash
# modules/mysql.sh
mysql_handler() {
    case "$2" in
        "create") mysql_create_site "$3" "$4" "$5" ;;
        "list") mysql_list_sites ;;
        "backup") mysql_backup_site "$3" ;;
        "delete") mysql_delete_site "$3" ;;
    esac
}

mysql_create_site() {
    # MySQL 创建逻辑
}
```

## 迁移计划

### 阶段1：模块提取
1. 提取 MySQL 相关函数到 `modules/mysql.sh`
2. 提取 Nginx 相关函数到 `modules/nginx.sh`
3. 提取其他模块...

### 阶段2：公共库重构
1. 提取日志函数到 `lib/logger.sh`
2. 提取工具函数到 `lib/utils.sh`
3. 提取验证函数到 `lib/validator.sh`

### 阶段3：配置管理
1. 创建配置文件结构
2. 实现动态配置加载
3. 支持环境变量覆盖

### 阶段4：主脚本简化
1. 简化主脚本为路由和加载器
2. 实现模块自动发现
3. 添加模块管理功能

## 预期效果

- 主脚本从 1529 行减少到 ~200 行
- 每个模块文件 ~100-200 行
- 新功能开发时间减少 50%
- 代码维护难度降低 70%
- 支持插件式扩展
