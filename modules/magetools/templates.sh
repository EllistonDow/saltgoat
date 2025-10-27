#!/bin/bash

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
    echo "基础模板:"
    echo "  basic     - 基础Magento项目"
    echo "    - 标准Magento结构"
    echo "    - 基础配置文件"
    echo "    - 开发环境设置"
    echo ""
    echo "高级模板:"
    echo "  advanced  - 高级Magento项目"
    echo "    - 包含前端构建工具"
    echo "    - ESLint + Prettier配置"
    echo "    - Sass预处理器"
    echo "    - Webpack配置"
    echo ""
    echo "自定义模板:"
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
    cd "$project_dir" || return 1
    
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
saltgoat magetools performance
saltgoat magetools maintenance <site> daily
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
    cd "$project_dir" || return 1
    
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
    
    read -r -p "请输入项目名称: " project_name
    read -r -p "选择功能 (用空格分隔，如: 1 2 3): " selected_features
    
    log_info "创建自定义项目: $project_name"
    log_info "选择的功能: $selected_features"
    
    # 这里可以实现自定义逻辑
    log_success "自定义模板功能开发中..."
}
