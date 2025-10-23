#!/bin/bash
# Magento 工具集
# modules/magetools/magetools.sh

# Magento 工具主函数
magetools_handler() {
    case "$1" in
        "install")
            install_magento_tool "$2"
            ;;
        "cache")
            case "$2" in
                "clear")
                    clear_magento_cache
                    ;;
                "status")
                    check_cache_status
                    ;;
                "warm")
                    warm_magento_cache
                    ;;
                *)
                    log_error "未知的缓存操作: $2"
                    log_info "支持: clear, status, warm"
                    exit 1
                    ;;
            esac
            ;;
        "index")
            case "$2" in
                "reindex")
                    reindex_magento
                    ;;
                "status")
                    check_index_status
                    ;;
                *)
                    log_error "未知的索引操作: $2"
                    log_info "支持: reindex, status"
                    exit 1
                    ;;
            esac
            ;;
        "template")
            case "$2" in
                "create")
                    create_magento_template "$3"
                    ;;
                "list")
                    list_magento_templates
                    ;;
                *)
                    log_error "未知的模板操作: $2"
                    log_info "支持: create, list"
                    exit 1
                    ;;
            esac
            ;;
        "deploy")
            deploy_magento
            ;;
        "backup")
            backup_magento
            ;;
        "restore")
            restore_magento "$2"
            ;;
        "performance")
            analyze_magento_performance
            ;;
        "security")
            scan_magento_security
            ;;
        "update")
            update_magento
            ;;
        "permissions")
            case "$2" in
                "fix")
                    fix_magento_permissions "$3"
                    ;;
                "check")
                    check_magento_permissions "$3"
                    ;;
                "reset")
                    reset_magento_permissions "$3"
                    ;;
                *)
                    log_error "未知的权限操作: $2"
                    log_info "支持: fix, check, reset"
                    exit 1
                    ;;
            esac
            ;;
        "convert")
            case "$2" in
                "magento2")
                    convert_to_magento2 "$3"
                    ;;
                "check")
                    check_magento2_compatibility "$3"
                    ;;
                *)
                    log_error "未知的转换操作: $2"
                    log_info "支持: magento2, check"
                    exit 1
                    ;;
            esac
            ;;
        "valkey-renew")
            # 调用 valkey-renew 脚本
            "${SCRIPT_DIR}/modules/magetools/valkey-renew.sh" "$2" "$3"
            ;;
        "rabbitmq")
            case "$2" in
                "all"|"smart")
                    # 调用 rabbitmq 脚本
                    sudo "${SCRIPT_DIR}/modules/magetools/rabbitmq.sh" "$2" "$3" "${4:-2}"
                    ;;
                "check")
                    # 检查 rabbitmq 状态
                    "${SCRIPT_DIR}/modules/magetools/rabbitmq-check.sh" "$3"
                    ;;
                *)
                    log_error "未知的 RabbitMQ 操作: $2"
                    log_info "支持的操作: all, smart, check"
                    exit 1
                    ;;
            esac
            ;;
        "opensearch")
            # 调用 opensearch 认证配置脚本
            "${SCRIPT_DIR}/modules/magetools/opensearch-auth.sh" "$2"
            ;;
        "maintenance")
            # 调用 Magento 维护管理脚本
            "${SCRIPT_DIR}/modules/magetools/magento-maintenance.sh" "$2" "$3"
            ;;
        "cron")
            # 调用定时任务管理脚本
            "${SCRIPT_DIR}/modules/magetools/magento-cron.sh" "$2" "$3"
            ;;
        "salt-schedule")
            # 调用 Salt Schedule 管理脚本
            "${SCRIPT_DIR}/modules/magetools/magento-salt-schedule.sh" "$2" "$3"
            ;;
        "migrate")
            if [[ -z "$3" ]]; then
                log_error "用法: saltgoat magetools migrate <site_path> <site_name> [action]"
                log_info "操作: detect (检测), fix (修复)"
                log_info "示例: saltgoat magetools migrate /var/www/tank tank detect"
                exit 1
            fi
            source "${SCRIPT_DIR}/modules/magetools/migrate-detect.sh" "$3" "$4" "$5"
            ;;
        "help"|"--help"|"-h")
            show_magetools_help
            ;;
        *)
            log_error "用法: saltgoat magetools <command> [options]"
            log_info "命令:"
            log_info "  install <tool>       - 安装Magento工具 (n98-magerun2, magerun, etc.)"
            log_info "  permissions fix      - 修复Magento权限"
            log_info "  permissions check    - 检查权限状态"
            log_info "  permissions reset    - 重置权限"
            log_info "  convert magento2     - 转换为Magento2配置"
            log_info "  convert check        - 检查Magento2兼容性"
            log_info "  valkey-renew <site>  - Valkey缓存自动续期"
            log_info "  rabbitmq setup <mode> <site> - RabbitMQ队列管理"
            log_info "  opensearch <user>     - OpenSearch Nginx认证配置"
            log_info "  maintenance <site> <action> - Magento维护管理"
            log_info "  cron <site> <action>       - 定时任务管理"
            log_info "  salt-schedule <site> <action> - Salt Schedule 管理"
            log_info "  help                 - 显示帮助"
            exit 1
            ;;
    esac
}

# 安装Magento工具
install_magento_tool() {
    local tool_name="$1"
    
    if [[ -z "$tool_name" ]]; then
        log_error "请指定要安装的工具"
        log_info "支持的工具:"
        log_info "  n98-magerun2    - N98 Magerun2 (Magento 2 CLI工具)"
        log_info "  phpunit         - PHPUnit单元测试框架"
        log_info "  xdebug          - Xdebug调试工具"
        log_info "  grunt           - Grunt构建工具"
        log_info "  gulp            - Gulp构建工具"
        log_info "  webpack         - Webpack打包工具"
        log_info "  nodejs          - Node.js运行环境"
        log_info "  eslint          - ESLint代码检查工具"
        log_info "  prettier        - Prettier代码格式化工具"
        log_info "  sass            - Sass CSS预处理器"
        return 1
    fi
    
    log_highlight "安装Magento工具: $tool_name"
    
    case "$tool_name" in
        "n98-magerun2")
            install_n98_magerun2
            ;;
        "phpunit")
            install_phpunit
            ;;
        "xdebug")
            install_xdebug
            ;;
        "grunt")
            install_grunt
            ;;
        "gulp")
            install_gulp
            ;;
        "webpack")
            install_webpack
            ;;
        "nodejs")
            install_nodejs
            ;;
        "eslint")
            install_eslint
            ;;
        "prettier")
            install_prettier
            ;;
        "sass")
            install_sass
            ;;
        *)
            log_error "未知的工具: $tool_name"
            log_info "支持的工具: n98-magerun2, phpunit, xdebug, grunt, gulp, webpack, nodejs, eslint, prettier, sass"
            return 1
            ;;
    esac
}

# 安装N98 Magerun2
install_n98_magerun2() {
    log_info "安装N98 Magerun2..."
    
    # 检查是否已安装
    if command -v n98-magerun2 >/dev/null 2>&1; then
        log_success "N98 Magerun2 已安装"
        n98-magerun2 --version
        return 0
    fi
    
    # 下载并安装
    log_info "下载N98 Magerun2..."
    curl -O https://files.magerun.net/n98-magerun2.phar
    
    if [[ -f "n98-magerun2.phar" ]]; then
        sudo mv n98-magerun2.phar /usr/local/bin/n98-magerun2
        sudo chmod +x /usr/local/bin/n98-magerun2
        
        log_success "N98 Magerun2 安装完成"
        log_info "使用方法: n98-magerun2 --help"
        
        # 显示常用命令
        echo ""
        log_info "常用命令:"
        echo "  n98-magerun2 cache:clean"
        echo "  n98-magerun2 index:reindex"
        echo "  n98-magerun2 sys:info"
        echo "  n98-magerun2 dev:console"
    else
        log_error "N98 Magerun2 下载失败"
        return 1
    fi
}

# 安装PHPUnit
install_phpunit() {
    log_info "安装PHPUnit单元测试框架..."
    
    # 检查是否已安装
    if command -v phpunit >/dev/null 2>&1; then
        log_success "PHPUnit 已安装"
        phpunit --version
        return 0
    fi
    
    # 检查PHP版本
    local php_version=$(php -v | head -1 | awk '{print $2}' | cut -d. -f1,2)
    log_info "检测到PHP版本: $php_version"
    
    # 检查并安装必需的PHP扩展
    log_info "检查PHP扩展..."
    local missing_extensions=()
    
    if ! php -m | grep -q "dom"; then
        missing_extensions+=("php${php_version}-dom")
    fi
    if ! php -m | grep -q "mbstring"; then
        missing_extensions+=("php${php_version}-mbstring")
    fi
    if ! php -m | grep -q "xml"; then
        missing_extensions+=("php${php_version}-xml")
    fi
    if ! php -m | grep -q "xmlwriter"; then
        missing_extensions+=("php${php_version}-xmlwriter")
    fi
    
    if [[ ${#missing_extensions[@]} -gt 0 ]]; then
        log_info "安装缺失的PHP扩展: ${missing_extensions[*]}"
        sudo apt install "${missing_extensions[@]}" -y
    fi
    
    # 全局安装PHPUnit
    log_info "下载PHPUnit..."
    wget https://phar.phpunit.de/phpunit.phar
    
    if [[ -f "phpunit.phar" ]]; then
        chmod +x phpunit.phar
        sudo mv phpunit.phar /usr/local/bin/phpunit
        
        log_success "PHPUnit 安装完成"
        log_info "使用方法: phpunit --help"
        
        # 显示PHPUnit说明
        echo ""
        log_info "PHPUnit 是什么？"
        echo "  - PHP单元测试框架"
        echo "  - 用于测试Magento自定义模块"
        echo "  - 确保代码质量和功能正确性"
        echo ""
        log_info "常用命令:"
        echo "  phpunit --version          # 查看版本"
        echo "  phpunit tests/             # 运行测试"
        echo "  phpunit --coverage-html    # 生成覆盖率报告"
        
        # 验证安装
        if phpunit --version >/dev/null 2>&1; then
            log_success "PHPUnit 验证成功"
        else
            log_warning "PHPUnit 可能需要额外的PHP扩展"
        fi
    else
        log_error "PHPUnit 下载失败"
        return 1
    fi
}

# 安装Xdebug
install_xdebug() {
    log_info "安装Xdebug..."
    
    # 检查是否已安装
    if php -m | grep -q xdebug; then
        log_success "Xdebug 已安装"
        php -m | grep xdebug
        return 0
    fi
    
    # 安装Xdebug
    log_info "通过apt安装Xdebug..."
    sudo apt update
    sudo apt install php-xdebug -y
    
    # 配置Xdebug
    log_info "配置Xdebug..."
    sudo tee -a /etc/php/8.3/mods-available/xdebug.ini >/dev/null <<EOF

; SaltGoat Xdebug配置
xdebug.mode = debug
xdebug.start_with_request = yes
xdebug.client_host = 127.0.0.1
xdebug.client_port = 9003
xdebug.log = /var/log/xdebug.log
EOF
    
    # 重启PHP-FPM
    sudo systemctl restart php8.3-fpm
    
    log_success "Xdebug 安装完成"
    log_info "重启PHP-FPM服务以应用配置"
}

# 安装Grunt
install_grunt() {
    log_info "安装Grunt构建工具..."
    
    # 检查Node.js
    if ! command -v node >/dev/null 2>&1; then
        log_info "Node.js未安装，先安装Node.js..."
        install_nodejs
    fi
    
    # 检查是否已安装
    if command -v grunt >/dev/null 2>&1; then
        log_success "Grunt 已安装"
        grunt --version
        return 0
    fi
    
    # 全局安装Grunt CLI
    log_info "安装Grunt CLI..."
    sudo npm install -g grunt-cli
    
    log_success "Grunt 安装完成"
    log_info "使用方法: grunt --help"
    log_info "常用命令:"
    echo "  grunt --version          # 查看版本"
    echo "  grunt default            # 运行默认任务"
    echo "  grunt watch              # 监听文件变化"
}

# 安装Gulp
install_gulp() {
    log_info "安装Gulp构建工具..."
    
    # 检查Node.js
    if ! command -v node >/dev/null 2>&1; then
        log_info "Node.js未安装，先安装Node.js..."
        install_nodejs
    fi
    
    # 检查是否已安装
    if command -v gulp >/dev/null 2>&1; then
        log_success "Gulp 已安装"
        gulp --version
        return 0
    fi
    
    # 全局安装Gulp CLI
    log_info "安装Gulp CLI..."
    sudo npm install -g gulp-cli
    
    log_success "Gulp 安装完成"
    log_info "使用方法: gulp --help"
    log_info "常用命令:"
    echo "  gulp --version           # 查看版本"
    echo "  gulp default             # 运行默认任务"
    echo "  gulp watch               # 监听文件变化"
}

# 安装Webpack
install_webpack() {
    log_info "安装Webpack打包工具..."
    
    # 检查Node.js
    if ! command -v node >/dev/null 2>&1; then
        log_info "Node.js未安装，先安装Node.js..."
        install_nodejs
    fi
    
    # 检查是否已安装
    if command -v webpack >/dev/null 2>&1; then
        log_success "Webpack 已安装"
        webpack --version
        return 0
    fi
    
    # 全局安装Webpack
    log_info "安装Webpack..."
    sudo npm install -g webpack webpack-cli
    
    log_success "Webpack 安装完成"
    log_info "使用方法: webpack --help"
    log_info "常用命令:"
    echo "  webpack --version        # 查看版本"
    echo "  webpack --mode production # 生产模式打包"
    echo "  webpack --watch          # 监听模式"
}

# 安装Node.js
install_nodejs() {
    log_info "安装Node.js..."
    
    # 检查是否已安装
    if command -v node >/dev/null 2>&1; then
        log_success "Node.js 已安装"
        node --version
        npm --version
        return 0
    fi
    
    # 安装Node.js (使用NodeSource仓库)
    log_info "添加NodeSource仓库..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    
    log_info "安装Node.js..."
    sudo apt install nodejs -y
    
    log_success "Node.js 安装完成"
    log_info "Node.js版本: $(node --version)"
    log_info "npm版本: $(npm --version)"
    
    # 显示常用命令
    echo ""
    log_info "常用命令:"
    echo "  node --version           # 查看Node.js版本"
    echo "  npm --version             # 查看npm版本"
    echo "  npm install <package>     # 安装包"
    echo "  npm init                  # 初始化项目"
}

# 安装ESLint
install_eslint() {
    log_info "安装ESLint代码检查工具..."
    
    # 检查Node.js
    if ! command -v node >/dev/null 2>&1; then
        log_info "Node.js未安装，先安装Node.js..."
        install_nodejs
    fi
    
    # 检查是否已安装
    if command -v eslint >/dev/null 2>&1; then
        log_success "ESLint 已安装"
        eslint --version
        return 0
    fi
    
    # 全局安装ESLint
    log_info "安装ESLint..."
    sudo npm install -g eslint
    
    log_success "ESLint 安装完成"
    log_info "使用方法: eslint --help"
    log_info "常用命令:"
    echo "  eslint --version         # 查看版本"
    echo "  eslint file.js           # 检查单个文件"
    echo "  eslint src/              # 检查目录"
    echo "  eslint --init            # 初始化配置"
}

# 安装Prettier
install_prettier() {
    log_info "安装Prettier代码格式化工具..."
    
    # 检查Node.js
    if ! command -v node >/dev/null 2>&1; then
        log_info "Node.js未安装，先安装Node.js..."
        install_nodejs
    fi
    
    # 检查是否已安装
    if command -v prettier >/dev/null 2>&1; then
        log_success "Prettier 已安装"
        prettier --version
        return 0
    fi
    
    # 全局安装Prettier
    log_info "安装Prettier..."
    sudo npm install -g prettier
    
    log_success "Prettier 安装完成"
    log_info "使用方法: prettier --help"
    log_info "常用命令:"
    echo "  prettier --version       # 查看版本"
    echo "  prettier file.js         # 格式化单个文件"
    echo "  prettier src/            # 格式化目录"
    echo "  prettier --write src/    # 直接写入格式化"
}

# 安装Sass
install_sass() {
    log_info "安装Sass CSS预处理器..."
    
    # 检查Node.js
    if ! command -v node >/dev/null 2>&1; then
        log_info "Node.js未安装，先安装Node.js..."
        install_nodejs
    fi
    
    # 检查是否已安装
    if command -v sass >/dev/null 2>&1; then
        log_success "Sass 已安装"
        sass --version
        return 0
    fi
    
    # 全局安装Sass
    log_info "安装Sass..."
    sudo npm install -g sass
    
    log_success "Sass 安装完成"
    log_info "使用方法: sass --help"
    log_info "常用命令:"
    echo "  sass --version           # 查看版本"
    echo "  sass input.scss output.css # 编译单个文件"
    echo "  sass src/:dist/          # 编译目录"
    echo "  sass --watch src/:dist/  # 监听模式"
}

# 创建Magento项目模板
create_magento_template() {
    local template_name="$1"
    
    if [[ -z "$template_name" ]]; then
        log_error "请指定模板名称"
        log_info "用法: saltgoat magetools template create <name>"
        log_info "可用模板:"
        log_info "  basic     - 基础Magento项目"
        log_info "  advanced  - 高级Magento项目(包含前端工具)"
        log_info "  custom    - 自定义项目"
        return 1
    fi
    
    log_highlight "创建Magento项目模板: $template_name"
    
    case "$template_name" in
        "basic")
            create_basic_template
            ;;
        "advanced")
            create_advanced_template
            ;;
        "custom")
            create_custom_template
            ;;
        *)
            log_error "未知的模板: $template_name"
            log_info "可用模板: basic, advanced, custom"
            return 1
            ;;
    esac
}

# 列出可用模板
list_magento_templates() {
    log_highlight "可用的Magento项目模板:"
    echo ""
    echo "📋 基础模板:"
    echo "  basic     - 基础Magento项目"
    echo "    - 标准Magento结构"
    echo "    - 基础配置文件"
    echo "    - 开发环境设置"
    echo ""
    echo "🚀 高级模板:"
    echo "  advanced  - 高级Magento项目"
    echo "    - 包含前端构建工具"
    echo "    - ESLint + Prettier配置"
    echo "    - Sass预处理器"
    echo "    - Webpack配置"
    echo ""
    echo "⚙️  自定义模板:"
    echo "  custom    - 自定义项目"
    echo "    - 交互式配置"
    echo "    - 选择需要的工具"
    echo "    - 自定义项目结构"
    echo ""
    echo "使用方法:"
    echo "  saltgoat magetools template create basic"
    echo "  saltgoat magetools template create advanced"
    echo "  saltgoat magetools template create custom"
}

# 创建基础模板
create_basic_template() {
    local project_name="magento-project"
    local project_dir="/var/www/$project_name"
    
    log_info "创建基础Magento项目模板..."
    
    # 创建项目目录
    sudo mkdir -p "$project_dir"
    cd "$project_dir"
    
    # 创建基础目录结构
    log_info "创建目录结构..."
    sudo mkdir -p {app,bin,dev,lib,pub,setup,var,generated}
    sudo mkdir -p app/{code,design,etc}
    sudo mkdir -p pub/{media,static}
    sudo mkdir -p var/{cache,log,page_cache,view_preprocessed}
    
    # 创建基础配置文件
    log_info "创建配置文件..."
    
    # composer.json
    sudo tee composer.json >/dev/null << 'EOF'
{
    "name": "magento/project",
    "description": "Magento 2 Project",
    "type": "project",
    "license": "OSL-3.0",
    "require": {
        "magento/product-community-edition": "^2.4"
    },
    "require-dev": {
        "magento/magento2-functional-testing-framework": "^3.0"
    },
    "autoload": {
        "psr-4": {
            "Magento\\Framework\\": "lib/internal/Magento/Framework/",
            "Magento\\Setup\\": "setup/src/Magento/Setup/",
            "Magento\\": "app/code/Magento/"
        }
    }
}
EOF
    
    # .gitignore
    sudo tee .gitignore >/dev/null << 'EOF'
/vendor/
/var/
/pub/media/
/pub/static/
/app/etc/env.php
/app/etc/config.php
/generated/
EOF
    
    # README.md
    sudo tee README.md >/dev/null << 'EOF'
# Magento 2 Project

这是一个基于SaltGoat创建的Magento 2项目模板。

## 安装

1. 安装Composer依赖:
```bash
composer install
```

2. 安装Magento:
```bash
php bin/magento setup:install
```

## 开发

使用SaltGoat工具进行开发:
```bash
saltgoat magetools cache clear
saltgoat magetools index reindex
saltgoat magetools performance
```

## 部署

```bash
saltgoat magetools deploy
```
EOF
    
    # 设置权限
    sudo chown -R www-data:www-data "$project_dir"
    sudo chmod -R 755 "$project_dir"
    
    log_success "基础Magento项目模板创建完成"
    log_info "项目位置: $project_dir"
    log_info "下一步: cd $project_dir && composer install"
}

# 创建高级模板
create_advanced_template() {
    local project_name="magento-advanced"
    local project_dir="/var/www/$project_name"
    
    log_info "创建高级Magento项目模板..."
    
    # 先创建基础模板
    create_basic_template
    
    # 重命名目录
    sudo mv "/var/www/magento-project" "$project_dir"
    cd "$project_dir"
    
    # 安装前端工具
    log_info "安装前端开发工具..."
    ./saltgoat magetools install grunt
    ./saltgoat magetools install gulp
    ./saltgoat magetools install webpack
    ./saltgoat magetools install eslint
    ./saltgoat magetools install prettier
    ./saltgoat magetools install sass
    
    # 创建前端配置文件
    log_info "创建前端配置文件..."
    
    # package.json
    cat > package.json << 'EOF'
{
    "name": "magento-advanced",
    "version": "1.0.0",
    "description": "Advanced Magento 2 Project",
    "scripts": {
        "build": "gulp build",
        "watch": "gulp watch",
        "lint": "eslint app/",
        "format": "prettier --write app/"
    },
    "devDependencies": {
        "gulp": "^4.0.2",
        "gulp-sass": "^5.1.0",
        "gulp-autoprefixer": "^8.0.0",
        "eslint": "^8.0.0",
        "prettier": "^3.0.0"
    }
}
EOF
    
    # .eslintrc.js
    cat > .eslintrc.js << 'EOF'
module.exports = {
    "env": {
        "browser": true,
        "es2021": true,
        "jquery": true
    },
    "extends": "eslint:recommended",
    "parserOptions": {
        "ecmaVersion": 12,
        "sourceType": "module"
    },
    "rules": {
        "indent": ["error", 4],
        "linebreak-style": ["error", "unix"],
        "quotes": ["error", "single"],
        "semi": ["error", "always"]
    }
};
EOF
    
    # .prettierrc
    cat > .prettierrc << 'EOF'
{
    "semi": true,
    "trailingComma": "es5",
    "singleQuote": true,
    "printWidth": 80,
    "tabWidth": 4
}
EOF
    
    # gulpfile.js
    cat > gulpfile.js << 'EOF'
const gulp = require('gulp');
const sass = require('gulp-sass');
const autoprefixer = require('gulp-autoprefixer');

function buildStyles() {
    return gulp.src('app/design/frontend/**/*.scss')
        .pipe(sass().on('error', sass.logError))
        .pipe(autoprefixer())
        .pipe(gulp.dest('pub/static/frontend/'));
}

function watchFiles() {
    gulp.watch('app/design/frontend/**/*.scss', buildStyles);
}

exports.build = buildStyles;
exports.watch = watchFiles;
exports.default = gulp.series(buildStyles, watchFiles);
EOF
    
    # 安装npm依赖
    log_info "安装npm依赖..."
    npm install
    
    log_success "高级Magento项目模板创建完成"
    log_info "项目位置: $project_dir"
    log_info "包含工具: Grunt, Gulp, Webpack, ESLint, Prettier, Sass"
    log_info "下一步: cd $project_dir && composer install && npm run build"
}

# 创建自定义模板
create_custom_template() {
    log_highlight "创建自定义Magento项目模板..."
    
    echo ""
    log_info "请选择需要的功能:"
    echo ""
    echo "1. 基础Magento结构"
    echo "2. 前端构建工具 (Grunt, Gulp, Webpack)"
    echo "3. 代码质量工具 (ESLint, Prettier)"
    echo "4. CSS预处理器 (Sass)"
    echo "5. 测试框架 (PHPUnit)"
    echo "6. 调试工具 (Xdebug)"
    echo ""
    
    read -p "请输入项目名称: " project_name
    read -p "选择功能 (用空格分隔，如: 1 2 3): " selected_features
    
    log_info "创建自定义项目: $project_name"
    log_info "选择的功能: $selected_features"
    
    # 这里可以实现自定义逻辑
    log_success "自定义模板功能开发中..."
}

# 清理Magento缓存
clear_magento_cache() {
    log_highlight "清理Magento缓存..."
    
    if [[ ! -f "bin/magento" ]]; then
        log_error "未找到Magento CLI，请确保在Magento根目录"
        return 1
    fi
    
    log_info "清理所有缓存..."
    php bin/magento cache:clean
    php bin/magento cache:flush
    
    log_info "清理生成的文件..."
    rm -rf var/cache/* var/page_cache/* var/view_preprocessed/*
    
    log_success "缓存清理完成"
}

# 检查缓存状态
check_cache_status() {
    log_highlight "检查Magento缓存状态..."
    
    if [[ ! -f "bin/magento" ]]; then
        log_error "未找到Magento CLI"
        return 1
    fi
    
    log_info "缓存状态:"
    php bin/magento cache:status
    
    echo ""
    log_info "缓存目录大小:"
    du -sh var/cache/ var/page_cache/ var/view_preprocessed/ 2>/dev/null || echo "缓存目录不存在"
}

# 预热缓存
warm_magento_cache() {
    log_highlight "预热Magento缓存..."
    
    if [[ ! -f "bin/magento" ]]; then
        log_error "未找到Magento CLI"
        return 1
    fi
    
    log_info "启用所有缓存..."
    php bin/magento cache:enable
    
    log_info "预热页面缓存..."
    php bin/magento cache:warm
    
    log_success "缓存预热完成"
}

# 重建索引
reindex_magento() {
    log_highlight "重建Magento索引..."
    
    if [[ ! -f "bin/magento" ]]; then
        log_error "未找到Magento CLI"
        return 1
    fi
    
    log_info "重建所有索引..."
    php bin/magento indexer:reindex
    
    log_success "索引重建完成"
}

# 检查索引状态
check_index_status() {
    log_highlight "检查Magento索引状态..."
    
    if [[ ! -f "bin/magento" ]]; then
        log_error "未找到Magento CLI"
        return 1
    fi
    
    log_info "索引状态:"
    php bin/magento indexer:status
}

# 部署Magento
deploy_magento() {
    log_highlight "部署Magento..."
    
    if [[ ! -f "bin/magento" ]]; then
        log_error "未找到Magento CLI"
        return 1
    fi
    
    log_info "设置生产模式..."
    php bin/magento deploy:mode:set production
    
    log_info "编译DI..."
    php bin/magento setup:di:compile
    
    log_info "部署静态内容..."
    php bin/magento setup:static-content:deploy
    
    log_info "设置权限..."
    sudo chown -R www-data:www-data var/ pub/ app/etc/
    sudo chmod -R 755 var/ pub/ app/etc/
    
    log_success "Magento部署完成"
}

# 备份Magento
backup_magento() {
    log_highlight "备份Magento..."
    
    local backup_dir="/home/doge/magento_backups"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="magento_backup_$timestamp"
    
    mkdir -p "$backup_dir"
    
    log_info "创建备份: $backup_name"
    
    # 备份数据库
    log_info "备份数据库..."
    php bin/magento setup:db:backup --code="$backup_name"
    
    # 备份文件
    log_info "备份文件..."
    tar -czf "$backup_dir/${backup_name}_files.tar.gz" \
        --exclude=var/cache \
        --exclude=var/page_cache \
        --exclude=var/view_preprocessed \
        --exclude=var/log \
        --exclude=pub/media/catalog/product/cache \
        .
    
    log_success "备份完成: $backup_dir/$backup_name"
}

# 恢复Magento
restore_magento() {
    local backup_name="$1"
    
    if [[ -z "$backup_name" ]]; then
        log_error "请指定备份名称"
        log_info "用法: saltgoat magetools restore <backup_name>"
        return 1
    fi
    
    log_highlight "恢复Magento: $backup_name"
    
    local backup_dir="/home/doge/magento_backups"
    
    if [[ ! -f "$backup_dir/${backup_name}_files.tar.gz" ]]; then
        log_error "备份文件不存在: $backup_name"
        return 1
    fi
    
    log_warning "这将覆盖当前Magento安装，是否继续? (y/N)"
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "恢复已取消"
        return 0
    fi
    
    log_info "恢复文件..."
    tar -xzf "$backup_dir/${backup_name}_files.tar.gz"
    
    log_info "恢复数据库..."
    php bin/magento setup:db:restore --code="$backup_name"
    
    log_success "Magento恢复完成"
}

# 分析Magento性能
analyze_magento_performance() {
    log_highlight "分析Magento性能..."
    
    echo "=========================================="
    echo "    Magento 性能分析"
    echo "=========================================="
    echo ""
    
    # 检查PHP配置
    log_info "PHP配置:"
    echo "  PHP版本: $(php -v | head -1)"
    echo "  内存限制: $(php -r 'echo ini_get("memory_limit");')"
    echo "  执行时间: $(php -r 'echo ini_get("max_execution_time");')s"
    echo "  OPcache: $(php -r 'echo ini_get("opcache.enable") ? "启用" : "禁用";')"
    echo ""
    
    # 检查Magento配置
    log_info "Magento配置:"
    if [[ -f "app/etc/env.php" ]]; then
        echo "  模式: $(php bin/magento deploy:mode:show 2>/dev/null | grep -o 'production\|developer')"
        echo "  缓存: $(php bin/magento cache:status 2>/dev/null | grep -c 'enabled' || echo '0') 个启用"
    fi
    echo ""
    
    # 检查文件大小
    log_info "文件大小分析:"
    echo "  总大小: $(du -sh . | cut -f1)"
    echo "  var目录: $(du -sh var/ 2>/dev/null | cut -f1 || echo 'N/A')"
    echo "  pub目录: $(du -sh pub/ 2>/dev/null | cut -f1 || echo 'N/A')"
    echo ""
    
    # 性能建议
    log_info "性能建议:"
    echo "  1. 启用所有缓存"
    echo "  2. 使用生产模式"
    echo "  3. 启用OPcache"
    echo "  4. 定期清理日志文件"
    echo "  5. 使用CDN加速静态资源"
}

# 扫描Magento安全
scan_magento_security() {
    log_highlight "扫描Magento安全..."
    
    echo "=========================================="
    echo "    Magento 安全扫描"
    echo "=========================================="
    echo ""
    
    # 检查文件权限
    log_info "文件权限检查:"
    if [[ -f "app/etc/env.php" ]]; then
        local env_perms=$(stat -c "%a" app/etc/env.php)
        if [[ "$env_perms" == "644" ]]; then
            echo "  [SUCCESS] env.php 权限正确: $env_perms"
        else
            echo "  [WARNING] env.php 权限异常: $env_perms (应为644)"
        fi
    fi
    echo ""
    
    # 检查敏感文件
    log_info "敏感文件检查:"
    local sensitive_files=("app/etc/env.php" "composer.json" "composer.lock")
    for file in "${sensitive_files[@]}"; do
        if [[ -f "$file" ]]; then
            echo "  [SUCCESS] $file 存在"
        else
            echo "  [ERROR] $file 缺失"
        fi
    done
    echo ""
    
    # 检查版本
    log_info "版本检查:"
    if [[ -f "composer.json" ]]; then
        local version=$(grep -o '"version": "[^"]*"' composer.json | cut -d'"' -f4)
        echo "  Magento版本: $version"
    fi
    echo ""
    
    # 安全建议
    log_info "安全建议:"
    echo "  1. 定期更新Magento和扩展"
    echo "  2. 使用强密码"
    echo "  3. 启用双因素认证"
    echo "  4. 定期备份数据"
    echo "  5. 监控异常活动"
}

# 更新Magento
update_magento() {
    log_highlight "更新Magento..."
    
    if [[ ! -f "composer.json" ]]; then
        log_error "未找到composer.json文件"
        return 1
    fi
    
    log_warning "更新Magento可能会影响现有功能，是否继续? (y/N)"
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "更新已取消"
        return 0
    fi
    
    log_info "备份当前版本..."
    backup_magento
    
    log_info "更新Composer依赖..."
    composer update
    
    log_info "更新数据库..."
    php bin/magento setup:upgrade
    
    log_info "重新部署..."
    deploy_magento
    
    log_success "Magento更新完成"
}

# 显示帮助
show_magetools_help() {
    echo "=========================================="
    echo "    Magento 工具集帮助"
    echo "=========================================="
    echo ""
    echo "Magento工具集提供以下功能:"
    echo ""
    echo "📦 工具安装:"
    echo "  install n98-magerun2 - 安装N98 Magerun2"
    echo "  install phpunit      - 安装PHPUnit单元测试框架"
    echo "  install xdebug       - 安装Xdebug调试工具"
    echo ""
    echo "[INFO] 权限管理:"
    echo "  permissions fix      - 修复Magento权限 (使用Salt原生功能)"
    echo "  permissions check    - 检查权限状态"
    echo "  permissions reset    - 重置权限"
    echo ""
    echo "[INFO] 站点转换:"
    echo "  convert magento2 [site] - 转换Nginx配置为Magento2格式 (支持站点名称或路径)"
    echo "  convert check        - 检查Magento2兼容性"
    echo ""
    echo "[INFO] Valkey缓存管理:"
    echo "  valkey-renew <site>  - Valkey缓存自动续期 (随机分配数据库编号)"
    echo ""
    echo "[INFO] RabbitMQ队列管理:"
    echo "  rabbitmq all <site> [threads]   - 配置所有消费者（21个）"
    echo "  rabbitmq smart <site> [threads] - 智能配置（仅核心消费者）"
    echo "  rabbitmq check <site>           - 检查消费者状态"
    echo ""
    echo "[INFO] OpenSearch认证管理:"
    echo "  opensearch <user>               - 配置OpenSearch Nginx认证"
    echo ""
    echo "[INFO] Magento维护管理:"
    echo "  maintenance <site> status       - 检查维护状态"
    echo "  maintenance <site> enable       - 启用维护模式"
    echo "  maintenance <site> disable      - 禁用维护模式"
    echo "  maintenance <site> daily       - 执行每日维护任务"
    echo "  maintenance <site> weekly      - 执行每周维护任务"
    echo "  maintenance <site> monthly     - 执行每月维护任务"
    echo "  maintenance <site> backup     - 创建备份"
    echo "  maintenance <site> health     - 健康检查"
    echo "  maintenance <site> cleanup    - 清理日志和缓存"
    echo "  maintenance <site> deploy     - 完整部署流程"
    echo ""
    echo "[INFO] 定时任务管理:"
    echo "  cron <site> <action>           - 系统 Cron 定时任务管理"
    echo "  salt-schedule <site> <action> - Salt Schedule 定时任务管理"
    echo ""
    echo "[INFO] 网站迁移管理:"
    echo "  migrate <path> <site> detect    - 检测迁移配置问题"
    echo "  migrate <path> <site> fix       - 修复迁移配置问题"
    echo ""
    echo "示例:"
    echo "  saltgoat magetools install n98-magerun2"
    echo "  saltgoat magetools permissions fix"
    echo "  saltgoat magetools convert magento2 tank"
    echo "  saltgoat magetools valkey-renew tank"
    echo "  saltgoat magetools rabbitmq check tank"
    echo "  saltgoat magetools opensearch doge"
    echo "  saltgoat magetools maintenance tank daily"
    echo "  saltgoat magetools maintenance tank backup"
    echo "  saltgoat magetools maintenance tank deploy"
    echo "  saltgoat magetools salt-schedule tank install"
}

# 检查 RabbitMQ 状态
check_rabbitmq_status() {
    local site_name="${1:-tank}"
    
    log_highlight "检查 RabbitMQ 消费者状态: $site_name"
    echo ""
    
    # 检查 RabbitMQ 服务状态
    log_info "1. RabbitMQ 服务状态:"
    if systemctl is-active --quiet rabbitmq; then
        log_success "RabbitMQ 服务正常运行"
    else
        log_error "RabbitMQ 服务未运行"
        return 1
    fi
    
    echo ""
    
    # 检查消费者服务状态
    log_info "2. 消费者服务状态:"
    local services=$(systemctl list-units --type=service | grep "magento-consumer-$site_name" | awk '{print $1}' | sed 's/\.service$//')
    
    if [[ -z "$services" ]]; then
        log_warning "未找到 $site_name 的消费者服务"
        return 1
    fi
    
    local total_services=0
    local running_services=0
    local failed_services=0
    local restarting_services=0
    
    # 使用数组处理服务列表
    local service_array=()
    while IFS= read -r service; do
        if [[ -n "$service" ]]; then
            service_array+=("$service")
        fi
    done <<< "$services"
    
    for service in "${service_array[@]}"; do
        ((total_services++))
        local status=$(systemctl is-active "$service" 2>/dev/null)
        local state=$(systemctl show "$service" --property=ActiveState --value 2>/dev/null)
        local restart_count=$(systemctl show "$service" --property=NRestarts --value 2>/dev/null)
        
        case "$status" in
            "active")
                log_success "[SUCCESS] $service (运行中)"
                ((running_services++))
                ;;
            "failed")
                log_error "[ERROR] $service (失败)"
                ((failed_services++))
                ;;
            *)
                if [[ "$state" == "activating" ]]; then
                    log_warning "[WARNING] $service (重启中)"
                    ((restarting_services++))
                else
                    log_warning "[WARNING] $service ($status)"
                fi
                ;;
        esac
        
        # 显示重启次数
        if [[ "$restart_count" -gt 0 ]]; then
            echo "   重启次数: $restart_count"
        fi
    done
    
    echo ""
    log_info "3. 服务统计:"
    echo "   总服务数: $total_services"
    echo "   运行中: $running_services"
    echo "   失败: $failed_services"
    echo "   重启中: $restarting_services"
    
    echo ""
    
    # 检查队列状态
    log_info "4. RabbitMQ 队列状态:"
    local vhost="/$site_name"
    if sudo rabbitmqctl list_queues -p "$vhost" 2>/dev/null | grep -q "Timeout"; then
        log_warning "队列查询超时，可能 RabbitMQ 服务繁忙"
    else
        local queue_count=$(sudo rabbitmqctl list_queues -p "$vhost" 2>/dev/null | wc -l)
        if [[ "$queue_count" -gt 1 ]]; then
            log_success "发现 $((queue_count-1)) 个队列"
            sudo rabbitmqctl list_queues -p "$vhost" 2>/dev/null | head -10
        else
            log_info "暂无队列消息"
        fi
    fi
    
    echo ""
    
    # 检查最近日志
    log_info "5. 最近服务日志 (失败的服务):"
    local failed_services_list=$(systemctl list-units --type=service | grep "magento-consumer-$site_name" | grep "failed\|activating" | awk '{print $1}')
    
    if [[ -n "$failed_services_list" ]]; then
        while IFS= read -r service; do
            if [[ -n "$service" ]]; then
                echo ""
                log_warning "服务: $service"
                sudo journalctl -u "$service" --no-pager -n 5 2>/dev/null | tail -3
            fi
        done <<< "$failed_services_list"
    else
        log_success "所有服务运行正常"
    fi
    
    echo ""
    
    # 总结
    if [[ "$failed_services" -eq 0 && "$restarting_services" -eq 0 ]]; then
        log_success "[SUCCESS] RabbitMQ 消费者状态良好"
    elif [[ "$failed_services" -gt 0 ]]; then
        log_error "[ERROR] 发现 $failed_services 个失败的服务，需要检查"
    else
        log_warning "[WARNING] 有 $restarting_services 个服务在重启，请关注"
    fi
}

# 修复 Magento 权限 (使用 Salt 原生功能)
fix_magento_permissions() {
    local site_path="${1:-$(pwd)}"
    
    # 检查是否在 Magento 目录中
    if [[ ! -f "$site_path/bin/magento" ]]; then
        log_error "未在 Magento 目录中，请指定正确的路径"
        log_info "用法: saltgoat magetools permissions fix [path]"
        log_info "示例: saltgoat magetools permissions fix /var/www/tank"
        return 1
    fi
    
    log_highlight "修复 Magento 权限: $site_path"
    log_info "使用 Salt 原生功能修复权限..."
    
    # 使用 Salt 原生功能修复权限
    log_info "1. 设置站点根目录权限..."
    sudo chown -R www-data:www-data "$site_path"
    sudo chmod 755 "$site_path"
    
    log_info "2. 设置 Magento 核心目录权限..."
    local core_dirs=("app" "bin" "dev" "lib" "phpserver" "pub" "setup" "vendor")
    for dir in "${core_dirs[@]}"; do
        if [[ -d "$site_path/$dir" ]]; then
            sudo chown -R www-data:www-data "$site_path/$dir"
            sudo chmod -R 755 "$site_path/$dir"
        fi
    done
    
    log_info "3. 设置可写目录权限..."
    local writable_dirs=("var" "generated" "pub/media" "pub/static" "app/etc")
    for dir in "${writable_dirs[@]}"; do
        if [[ -d "$site_path/$dir" ]]; then
            sudo chown -R www-data:www-data "$site_path/$dir"
            sudo chmod -R 775 "$site_path/$dir"
        fi
    done
    
    log_info "4. 设置配置文件权限..."
    if [[ -f "$site_path/app/etc/env.php" ]]; then
        sudo chown www-data:www-data "$site_path/app/etc/env.php"
        sudo chmod 644 "$site_path/app/etc/env.php"
    fi
    
    log_info "5. 确保父目录访问权限..."
    local parent_dir=$(dirname "$site_path")
    sudo chmod 755 "$parent_dir"
    sudo chown root:www-data "$parent_dir"
    
    log_info "6. 修复缓存目录权限..."
    if [[ -d "$site_path/var" ]]; then
        sudo chmod -R 777 "$site_path/var"
        sudo chown -R www-data:www-data "$site_path/var"
    fi
    
    if [[ -d "$site_path/generated" ]]; then
        sudo chmod -R 777 "$site_path/generated"
        sudo chown -R www-data:www-data "$site_path/generated"
    fi
    
    log_success "Magento 权限修复完成！"
    log_info "现在可以测试 Magento 命令："
    echo "  sudo -u www-data php bin/magento --version"
    echo "  sudo -u www-data n98-magerun2 --version"
    echo ""
    log_info "[INFO] 权限管理最佳实践:"
    echo "  [SUCCESS] 使用: sudo -u www-data php bin/magento <command>"
    echo "  [ERROR] 避免: sudo php bin/magento <command>"
    echo "  [INFO] 详细说明: docs/MAGENTO_PERMISSIONS.md"
}

# 检查 Magento 权限状态
check_magento_permissions() {
    local site_path="${1:-$(pwd)}"
    
    if [[ ! -f "$site_path/bin/magento" ]]; then
        log_error "未在 Magento 目录中，请指定正确的路径"
        return 1
    fi
    
    log_highlight "检查 Magento 权限状态: $site_path"
    
    echo "目录权限检查:"
    echo "=========================================="
    
    # 检查关键目录权限
    local critical_dirs=("var" "generated" "pub/media" "pub/static" "app/etc")
    for dir in "${critical_dirs[@]}"; do
        if [[ -d "$site_path/$dir" ]]; then
            local perms=$(ls -ld "$site_path/$dir" | awk '{print $1}')
            local owner=$(ls -ld "$site_path/$dir" | awk '{print $3":"$4}')
            echo "$dir: $perms (owner: $owner)"
            
            # 检查权限是否正确
            if [[ "$dir" == "var" || "$dir" == "generated" ]]; then
                if [[ "$perms" != "drwxrwxr-x" ]]; then
                    log_warning "$dir: 权限可能不正确，建议使用 'permissions fix' 修复"
                fi
            fi
        fi
    done
    
    echo ""
    echo "配置文件权限检查:"
    echo "----------------------------------------"
    
    # 检查配置文件权限
    if [[ -f "$site_path/app/etc/env.php" ]]; then
        local perms=$(ls -l "$site_path/app/etc/env.php" | awk '{print $1}')
        local owner=$(ls -l "$site_path/app/etc/env.php" | awk '{print $3":"$4}')
        echo "app/etc/env.php: $perms (owner: $owner)"
        
        if [[ "$perms" != "-rw-rw----" ]]; then
            log_warning "env.php: 权限可能不正确，建议使用 'permissions fix' 修复"
        fi
    fi
    
    echo ""
    echo "测试 Magento 命令:"
    echo "----------------------------------------"
    
    # 测试 Magento 命令
    if sudo -u www-data php bin/magento --version >/dev/null 2>&1; then
        log_success "Magento CLI 正常工作 (使用 www-data 用户)"
    else
        log_error "Magento CLI 无法正常工作，可能需要修复权限"
    fi
    
    # 测试 N98 Magerun2
    if command -v n98-magerun2 >/dev/null 2>&1; then
        if sudo -u www-data n98-magerun2 --version >/dev/null 2>&1; then
            log_success "N98 Magerun2 正常工作 (使用 www-data 用户)"
        else
            log_error "N98 Magerun2 无法正常工作，可能需要修复权限"
        fi
    else
        log_info "N98 Magerun2 未安装，可以使用 'install n98-magerun2' 安装"
    fi
    
    echo ""
    log_info "[INFO] 权限管理最佳实践:"
    echo "  [SUCCESS] 使用: sudo -u www-data php bin/magento <command>"
    echo "  [ERROR] 避免: sudo php bin/magento <command>"
    echo "  [INFO] 详细说明: docs/MAGENTO_PERMISSIONS.md"
}

# 重置 Magento 权限 (强制修复)
reset_magento_permissions() {
    local site_path="${1:-$(pwd)}"
    
    if [[ ! -f "$site_path/bin/magento" ]]; then
        log_error "未在 Magento 目录中，请指定正确的路径"
        return 1
    fi
    
    log_warning "重置 Magento 权限会修改所有文件权限，是否继续? (y/N)"
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "操作已取消"
        return 0
    fi
    
    log_highlight "重置 Magento 权限: $site_path"
    
    # 安全重置权限
    log_info "安全重置所有权限..."
    sudo chown -R www-data:www-data "$site_path"
    
    # 重新设置正确的权限
    log_info "重新设置正确的权限..."
    sudo chmod 755 "$site_path"
    sudo chmod -R 755 "$site_path"/{app,bin,dev,lib,phpserver,pub,setup,vendor}
    sudo chmod -R 775 "$site_path"/{var,generated,pub/media,pub/static,app/etc}
    sudo chmod 644 "$site_path/app/etc/env.php"
    
    log_success "Magento 权限重置完成！"
    log_info "建议运行 'permissions check' 验证权限状态"
}

# 检查 Magento 2 兼容性
check_magento2_compatibility() {
    local site_path="${1:-$(pwd)}"
    
    log_highlight "检查 Magento 2 兼容性: $site_path"
    
    echo "系统环境检查:"
    echo "=========================================="
    
    # 检查 PHP 版本
    local php_version=$(php -v | head -1 | awk '{print $2}' | cut -d. -f1,2)
    echo "PHP 版本: $php_version"
    if [[ "$php_version" == "8.3" || "$php_version" == "8.2" || "$php_version" == "8.1" ]]; then
        log_success "PHP 版本兼容 Magento 2"
    else
        log_warning "PHP 版本可能不兼容 Magento 2，建议使用 PHP 8.1+"
    fi
    
    # 检查 PHP 扩展
    echo ""
    echo "PHP 扩展检查:"
    echo "----------------------------------------"
    local required_extensions=("curl" "gd" "intl" "mbstring" "openssl" "pdo_mysql" "soap" "xml" "zip" "bcmath" "json")
    local missing_extensions=()
    
    for ext in "${required_extensions[@]}"; do
        if php -m | grep -q "^$ext$"; then
            echo "[SUCCESS] $ext"
        else
            echo "[ERROR] $ext (缺失)"
            missing_extensions+=("$ext")
        fi
    done
    
    if [[ ${#missing_extensions[@]} -eq 0 ]]; then
        log_success "所有必需的 PHP 扩展都已安装"
    else
        log_warning "缺失扩展: ${missing_extensions[*]}"
    fi
    
    # 检查 Nginx 配置
    echo ""
    echo "Nginx 配置检查:"
    echo "----------------------------------------"
    
    # 动态检测站点名称
    local site_name=$(basename "$site_path")
    local nginx_config="/etc/nginx/sites-enabled/$site_name"
    
    if [[ -f "$nginx_config" ]]; then
        echo "[SUCCESS] Nginx 站点配置存在"
        
        # 检查是否使用 Magento 2 简化配置（nginx.conf.sample）
        if grep -q "nginx.conf.sample" "$nginx_config"; then
            echo "[SUCCESS] 使用 Magento 2 简化配置（nginx.conf.sample）"
            echo "[SUCCESS] 包含 try_files 配置（在 nginx.conf.sample 中）"
            echo "[SUCCESS] PHP-FPM 配置存在（在 nginx.conf.sample 中）"
        else
            # 检查 Magento 2 特定的 Nginx 配置
            if grep -q "try_files" "$nginx_config"; then
                echo "[SUCCESS] 包含 try_files 配置"
            else
                log_warning "缺少 try_files 配置，需要 Magento 2 优化"
            fi
            
            if grep -q "fastcgi_pass" "$nginx_config"; then
                echo "[SUCCESS] PHP-FPM 配置存在"
            else
                log_warning "缺少 PHP-FPM 配置"
            fi
        fi
    else
        log_error "Nginx 站点配置不存在: $nginx_config"
    fi
    
    # 检查 MySQL 配置
    echo ""
    echo "MySQL 配置检查:"
    echo "----------------------------------------"
    local mysql_version=$(mysql --version | awk '{print $3}' | cut -d. -f1,2)
    echo "MySQL 版本: $mysql_version"
    
    if [[ "$mysql_version" == "8.0" || "$mysql_version" == "8.4" ]]; then
        log_success "MySQL 版本兼容 Magento 2"
    else
        log_warning "MySQL 版本可能不兼容 Magento 2，建议使用 MySQL 8.0+"
    fi
    
    # 检查 Composer
    echo ""
    echo "Composer 检查:"
    echo "----------------------------------------"
    if command -v composer >/dev/null 2>&1; then
        local composer_version=$(composer --version | awk '{print $3}')
        echo "[SUCCESS] Composer 版本: $composer_version"
    else
        log_error "Composer 未安装"
    fi
    
    # 检查内存限制和执行时间（优先检查FPM配置）
    echo ""
    echo "系统资源检查:"
    echo "----------------------------------------"
    
    # 检查FPM配置
    local fpm_ini="/etc/php/8.3/fpm/php.ini"
    if [[ -f "$fpm_ini" ]]; then
        local memory_limit=$(grep "^memory_limit" "$fpm_ini" | cut -d'=' -f2 | tr -d ' ')
        local max_execution_time=$(grep "^max_execution_time" "$fpm_ini" | cut -d'=' -f2 | tr -d ' ')
        echo "PHP 内存限制: $memory_limit (FPM配置)"
        echo "PHP 执行时间限制: ${max_execution_time}s (FPM配置)"
    else
        # 回退到CLI配置
        local memory_limit=$(php -r "echo ini_get('memory_limit');")
        local max_execution_time=$(php -r "echo ini_get('max_execution_time');")
        echo "PHP 内存限制: $memory_limit (CLI配置)"
        echo "PHP 执行时间限制: ${max_execution_time}s (CLI配置)"
    fi
    
    # 检查磁盘空间
    local disk_usage=$(df -h "$site_path" | awk 'NR==2 {print $5}' | sed 's/%//')
    echo "磁盘使用率: ${disk_usage}%"
    
    if [[ "$disk_usage" -lt 80 ]]; then
        log_success "磁盘空间充足"
    else
        log_warning "磁盘空间不足，建议清理"
    fi
    
    echo ""
    echo "兼容性总结:"
    echo "=========================================="
    if [[ ${#missing_extensions[@]} -eq 0 ]] && [[ "$php_version" == "8.3" || "$php_version" == "8.2" || "$php_version" == "8.1" ]]; then
        log_success "系统环境兼容 Magento 2"
        log_info "可以运行 'convert magento2' 进行转换"
    else
        log_warning "系统环境需要优化才能完全兼容 Magento 2"
        log_info "建议先解决上述问题后再进行转换"
    fi
}

# 转换为 Magento 2 配置
convert_to_magento2() {
    local site_input="${1:-$(pwd)}"
    local site_path=""
    
    # 判断输入是路径还是站点名称
    if [[ "$site_input" =~ ^/ ]]; then
        # 如果是绝对路径，直接使用
        site_path="$site_input"
    else
        # 如果是站点名称，构建标准路径
        site_path="/var/www/$site_input"
    fi
    
    # 检查是否在 Magento 目录中
    if [[ ! -f "$site_path/bin/magento" ]]; then
        log_error "未在 Magento 目录中，请指定正确的路径或站点名称"
        log_info "用法: saltgoat magetools convert magento2 [site_name|path]"
        log_info "示例: saltgoat magetools convert magento2 tank"
        log_info "示例: saltgoat magetools convert magento2 /var/www/tank"
        return 1
    fi
    
    log_highlight "转换站点 Nginx 配置为 Magento 2: $site_path"
    
    # 先检查兼容性
    log_info "检查系统兼容性..."
    check_magento2_compatibility "$site_path"
    
    # 直接优化 Nginx 配置为 Magento 2
    log_info "优化 Nginx 配置为 Magento 2..."
    optimize_nginx_for_magento2 "$site_path"
    
    log_success "Magento 2 Nginx 配置转换完成！"
    log_info "注意: 此命令仅转换 Nginx 配置"
    log_info "如需其他 Magento 2 操作，请手动运行："
    echo "  cd $site_path"
    echo "  php bin/magento cache:clean"
    echo "  php bin/magento setup:di:compile"
    echo "  php bin/magento setup:static-content:deploy -f"
    echo "  php bin/magento indexer:reindex"
    echo "  saltgoat magetools permissions fix $site_path"
}

# 优化 Nginx 配置为 Magento 2
optimize_nginx_for_magento2() {
    local site_path="$1"
    local site_name=$(basename "$site_path")
    
    log_info "优化 Nginx 配置为 Magento 2..."
    
    # 检查站点配置文件是否存在
    if [[ ! -f "/etc/nginx/sites-enabled/$site_name" ]]; then
        log_error "站点配置文件不存在: /etc/nginx/sites-enabled/$site_name"
        log_info "请先使用 'saltgoat nginx create $site_name <domain>' 创建站点"
        return 1
    fi
    
    # 备份原配置到 sites-available 目录
    sudo cp "/etc/nginx/sites-enabled/$site_name" "/etc/nginx/sites-available/$site_name.backup.$(date +%Y%m%d_%H%M%S)"
    
    # 从原配置中提取域名信息
    local server_name=$(grep "server_name" "/etc/nginx/sites-enabled/$site_name" | head -1 | sed 's/.*server_name[[:space:]]*//; s/;.*//')
    
    if [[ -z "$server_name" ]]; then
        log_error "无法从原配置中提取域名信息"
        return 1
    fi
    
    log_info "检测到域名: $server_name"
    
    # 检查是否有 SSL 配置
    local has_ssl=false
    local backup_file=$(ls -t /etc/nginx/sites-available/$site_name.backup.* 2>/dev/null | head -1)
    if [[ -n "$backup_file" ]] && grep -q "ssl_certificate" "$backup_file"; then
        has_ssl=true
        log_info "检测到 SSL 配置，将保持 HTTPS 设置"
    fi
    
    # 创建简化的 Magento 2 Nginx 配置（使用 nginx.conf.sample）
    # 注意：nginx.conf.sample 需要 fastcgi_backend upstream 定义
    if [[ "$has_ssl" == "true" ]]; then
        # 如果有 SSL，创建 HTTP 重定向和 HTTPS 配置
        sudo tee "/etc/nginx/sites-enabled/$site_name" >/dev/null <<EOF
upstream fastcgi_backend {
  server  unix:/run/php/php8.3-fpm.sock;
}

server {
    listen 80;
    server_name $server_name;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name $server_name;
    set \$MAGE_ROOT $site_path;
    include $site_path/nginx.conf.sample;
    
    # SSL 配置
    ssl_certificate /etc/letsencrypt/live/$site_name/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$site_name/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
}
EOF
    else
        # 如果没有 SSL，只创建 HTTP 配置
        sudo tee "/etc/nginx/sites-enabled/$site_name" >/dev/null <<EOF
upstream fastcgi_backend {
  server  unix:/run/php/php8.3-fpm.sock;
}

server {
    listen 80;
    server_name $server_name;
    set \$MAGE_ROOT $site_path;
    include $site_path/nginx.conf.sample;
}
EOF
    fi
    log_info "已创建 Magento 2 配置（包含 fastcgi_backend upstream）"
    
    # 测试 Nginx 配置
    if sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf; then
        sudo systemctl reload nginx
        log_success "Nginx 配置已更新为 Magento 2 简化配置（使用 nginx.conf.sample）"
        log_info "配置特点:"
        log_info "  - 使用官方 nginx.conf.sample"
        log_info "  - 包含 fastcgi_backend upstream 定义"
        log_info "  - 自动提取原域名配置"
    else
        log_error "Nginx 配置有误，请检查"
        # 恢复备份
        local backup_file=$(ls -t /etc/nginx/sites-available/$site_name.backup.* 2>/dev/null | head -1)
        if [[ -n "$backup_file" ]]; then
            sudo cp "$backup_file" "/etc/nginx/sites-enabled/$site_name"
            log_info "已恢复备份配置"
        fi
        return 1
    fi
}

# 优化 PHP 配置为 Magento 2
optimize_php_for_magento2() {
    log_info "优化 PHP 配置为 Magento 2..."
    
    # 备份原配置
    sudo cp /etc/php/8.3/fpm/php.ini /etc/php/8.3/fpm/php.ini.backup.$(date +%Y%m%d_%H%M%S)
    
    # 优化 PHP 配置
    sudo sed -i 's/memory_limit = .*/memory_limit = 2G/' /etc/php/8.3/fpm/php.ini
    sudo sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php/8.3/fpm/php.ini
    sudo sed -i 's/max_input_time = .*/max_input_time = 300/' /etc/php/8.3/fpm/php.ini
    sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' /etc/php/8.3/fpm/php.ini
    sudo sed -i 's/post_max_size = .*/post_max_size = 64M/' /etc/php/8.3/fpm/php.ini
    sudo sed -i 's/max_input_vars = .*/max_input_vars = 3000/' /etc/php/8.3/fpm/php.ini
    
    # 重启 PHP-FPM
    sudo systemctl restart php8.3-fpm
    
    log_success "PHP 配置已优化为 Magento 2"
}

# 优化 MySQL 配置为 Magento 2
optimize_mysql_for_magento2() {
    log_info "优化 MySQL 配置为 Magento 2..."
    
    # 检查是否已经有 Magento 优化配置
    if grep -q "# Magento 2 优化配置" /etc/mysql/mysql.conf.d/lemp.cnf; then
        log_info "MySQL 配置已经包含 Magento 2 优化，跳过优化步骤"
        return 0
    fi
    
    # 备份原配置
    sudo cp /etc/mysql/mysql.conf.d/lemp.cnf /etc/mysql/mysql.conf.d/lemp.cnf.backup.$(date +%Y%m%d_%H%M%S)
    
    # 添加 Magento 2 优化配置（使用 Percona 8.4+ 兼容参数）
    sudo tee -a /etc/mysql/mysql.conf.d/lemp.cnf >/dev/null <<EOF

# Magento 2 优化配置 (Percona 8.4+ 兼容)
# 基本设置
innodb_buffer_pool_size = 1G
innodb_log_buffer_size = 16M
innodb_flush_log_at_trx_commit = 2
innodb_thread_concurrency = 16

# 连接设置
max_connections = 500
max_connect_errors = 10000

# 临时表
tmp_table_size = 64M
max_heap_table_size = 64M

# 其他优化
table_open_cache = 4000
thread_cache_size = 16
EOF
    
    # 重启 MySQL
    if sudo systemctl restart mysql; then
        log_success "MySQL 配置已优化为 Magento 2"
    else
        log_error "MySQL 重启失败，请检查配置"
        log_info "恢复备份配置..."
        sudo cp /etc/mysql/mysql.conf.d/lemp.cnf.backup.$(date +%Y%m%d_%H%M%S) /etc/mysql/mysql.conf.d/lemp.cnf
        sudo systemctl restart mysql
        return 1
    fi
}
