#!/bin/bash
# 优化管理模块
# core/optimize.sh

# Magento 优化
optimize_magento() {
    log_info "开始优化 Magento 配置..."
    
    # 应用 Magento 优化状态
    salt-call --local state.apply optional.magento-optimization
    
    log_success "Magento 优化完成"
}
