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
        "help"|"--help"|"-h")
            show_magetools_help
            ;;
        *)
            log_error "用法: saltgoat magetools <command> [options]"
            log_info "命令:"
            log_info "  install <tool>       - 安装Magento工具 (n98-magerun2, magerun, etc.)"
            log_info "  cache clear          - 清理缓存"
            log_info "  cache status         - 检查缓存状态"
            log_info "  cache warm           - 预热缓存"
            log_info "  index reindex        - 重建索引"
            log_info "  index status         - 检查索引状态"
            log_info "  deploy               - 部署Magento"
            log_info "  backup               - 备份Magento"
            log_info "  restore <backup>     - 恢复Magento"
            log_info "  performance          - 性能分析"
            log_info "  security             - 安全扫描"
            log_info "  update               - 更新Magento"
            log_info "  help                 - 查看帮助"
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
            echo "  ✅ env.php 权限正确: $env_perms"
        else
            echo "  ⚠️  env.php 权限异常: $env_perms (应为644)"
        fi
    fi
    echo ""
    
    # 检查敏感文件
    log_info "敏感文件检查:"
    local sensitive_files=("app/etc/env.php" "composer.json" "composer.lock")
    for file in "${sensitive_files[@]}"; do
        if [[ -f "$file" ]]; then
            echo "  ✅ $file 存在"
        else
            echo "  ❌ $file 缺失"
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
    echo "  install grunt        - 安装Grunt构建工具"
    echo "  install gulp         - 安装Gulp构建工具"
    echo "  install webpack      - 安装Webpack打包工具"
    echo "  install nodejs       - 安装Node.js运行环境"
    echo "  install eslint       - 安装ESLint代码检查工具"
    echo "  install prettier     - 安装Prettier代码格式化工具"
    echo "  install sass         - 安装Sass CSS预处理器"
    echo ""
    echo "📋 项目模板:"
    echo "  template create <name> - 创建Magento项目模板"
    echo "  template list          - 列出可用模板"
    echo ""
    echo "🗂️  缓存管理:"
    echo "  cache clear          - 清理所有缓存"
    echo "  cache status         - 检查缓存状态"
    echo "  cache warm           - 预热缓存"
    echo ""
    echo "📊 索引管理:"
    echo "  index reindex        - 重建所有索引"
    echo "  index status         - 检查索引状态"
    echo ""
    echo "🚀 部署管理:"
    echo "  deploy               - 部署到生产环境"
    echo ""
    echo "💾 备份恢复:"
    echo "  backup               - 创建完整备份"
    echo "  restore <backup>     - 从备份恢复"
    echo ""
    echo "📈 性能分析:"
    echo "  performance          - 分析性能状况"
    echo ""
    echo "🔒 安全扫描:"
    echo "  security             - 扫描安全问题"
    echo ""
    echo "🔄 更新管理:"
    echo "  update               - 更新Magento"
    echo ""
    echo "示例:"
    echo "  saltgoat magetools install n98-magerun2"
    echo "  saltgoat magetools cache clear"
    echo "  saltgoat magetools index reindex"
    echo "  saltgoat magetools backup"
    echo "  saltgoat magetools performance"
}
