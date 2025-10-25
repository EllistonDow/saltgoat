#!/bin/bash

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
    local php_version
    php_version="$(php -v | head -1 | awk '{print $2}' | cut -d. -f1,2)"
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
