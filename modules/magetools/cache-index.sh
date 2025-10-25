#!/bin/bash

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
