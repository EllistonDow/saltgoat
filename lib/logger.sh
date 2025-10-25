#!/bin/bash
# SaltGoat 日志函数库
# lib/logger.sh

# 颜色定义
# shellcheck disable=SC2034  # 多个颜色常量供其他模块引用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_highlight() {
    echo -e "${CYAN}[HIGHLIGHT]${NC} $1"
}

log_note() {
    echo -e "${YELLOW}[NOTE]${NC} $1"
}

# 显示横幅
show_banner() {
    echo "=========================================="
    echo "    SaltGoat"
    echo "=========================================="
}
