#!/bin/bash
# SaltGoat 代码审查脚本
# scripts/code-review.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# 显示帮助信息
show_help() {
    echo "SaltGoat 代码审查工具"
    echo ""
    echo "用法: $0 [选项] [文件/目录]"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -a, --all      审查所有 Shell 脚本"
    echo "  -f, --format   格式化代码"
    echo "  -c, --check    只检查不修复"
    echo "  -v, --verbose  详细输出"
    echo ""
    echo "脚本会在 Shell 检查后自动运行 docs Lint (scripts/check-docs.py)"
    echo ""
    echo "示例:"
    echo "  $0                    # 审查当前目录所有脚本"
    echo "  $0 saltgoat           # 审查主脚本"
    echo "  $0 services/          # 审查 services 目录"
    echo "  $0 -f saltgoat        # 格式化主脚本"
    echo "  $0 -a                 # 审查所有脚本"
}

# 检查工具是否安装
check_tools() {
    local missing_tools=()
    
    if ! command -v shellcheck &> /dev/null; then
        missing_tools+=("shellcheck")
    fi
    
    if ! command -v shfmt &> /dev/null; then
        missing_tools+=("shfmt")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "缺少以下工具: ${missing_tools[*]}"
        log_info "请运行: sudo apt install shellcheck shfmt"
        exit 1
    fi
}

# ShellCheck 静态分析
run_shellcheck() {
    local file="$1"
    local verbose="$2"
    
    log_info "运行 ShellCheck 分析: $file"
    
    if [[ "$verbose" == "true" ]]; then
        shellcheck "$file"
    else
        shellcheck "$file" 2>/dev/null || {
            log_error "ShellCheck 发现问题:"
            shellcheck "$file"
            return 1
        }
    fi
    
    log_success "ShellCheck 通过: $file"
    return 0
}

# shfmt 代码格式化
run_shfmt() {
    local file="$1"
    local check_only="$2"
    
    log_info "运行 shfmt 格式化: $file"
    
    if [[ "$check_only" == "true" ]]; then
        # 只检查格式，不修改文件
        if shfmt -d "$file" | grep -q .; then
            log_warning "代码格式需要调整: $file"
            shfmt -d "$file"
            return 1
        else
            log_success "代码格式正确: $file"
            return 0
        fi
    else
        # 格式化文件
        shfmt -w "$file"
        log_success "代码已格式化: $file"
        return 0
    fi
}

# 检查文件权限
check_permissions() {
    local file="$1"
    
    if [[ ! -x "$file" ]] && [[ "$file" == *.sh ]]; then
        log_warning "脚本文件没有执行权限: $file"
        return 1
    fi
    
    return 0
}

# 检查文件编码
check_encoding() {
    local file="$1"
    
    if file "$file" | grep -q "with BOM"; then
        log_warning "文件包含 BOM: $file"
        return 1
    fi
    
    return 0
}

# 检查行尾
check_line_endings() {
    local file="$1"
    
    if file "$file" | grep -q "CRLF"; then
        log_warning "文件使用 Windows 行尾 (CRLF): $file"
        return 1
    fi
    
    return 0
}

# 检查 Shebang
check_shebang() {
    local file="$1"
    
    if [[ "$file" == *.sh ]] && ! head -1 "$file" | grep -q "^#!/"; then
        log_warning "Shell 脚本缺少 Shebang: $file"
        return 1
    fi
    
    return 0
}

run_docs_check() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local checker="${script_dir}/check-docs.py"

    if [[ ! -f "$checker" ]]; then
        log_warning "未找到文档检查脚本: ${checker}"
        return 0
    fi

    log_info "运行文档检查: docs/*.md"
    if python3 "$checker"; then
        log_success "文档检查通过"
        return 0
    else
        log_error "文档检查失败"
        return 1
    fi
}

# 综合审查单个文件
review_file() {
    local file="$1"
    local format="$2"
    local check_only="$3"
    local verbose="$4"
    
    log_info "开始审查文件: $file"
    echo "=========================================="
    
    local issues=0
    
    # 基础检查
    check_permissions "$file" || ((issues++))
    check_encoding "$file" || ((issues++))
    check_line_endings "$file" || ((issues++))
    check_shebang "$file" || ((issues++))
    
    # ShellCheck 分析
    if ! run_shellcheck "$file" "$verbose"; then
        ((issues++))
    fi
    
    # shfmt 格式化
    if [[ "$format" == "true" ]]; then
        if ! run_shfmt "$file" "$check_only"; then
            ((issues++))
        fi
    fi
    
    echo "=========================================="
    
    if [[ $issues -eq 0 ]]; then
        log_success "文件审查通过: $file"
        return 0
    else
        log_error "文件审查发现问题 ($issues 个): $file"
        return 1
    fi
}

# 查找所有 Shell 脚本
find_shell_scripts() {
    find . -name "*.sh" -type f | grep -v ".git" | sort
}

# 主函数
main() {
    local format="false"
    local check_only="false"
    local verbose="false"
    local target=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -a|--all)
                target="all"
                shift
                ;;
            -f|--format)
                format="true"
                shift
                ;;
            -c|--check)
                check_only="true"
                shift
                ;;
            -v|--verbose)
                verbose="true"
                shift
                ;;
            -*)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                target="$1"
                shift
                ;;
        esac
    done
    
    # 检查工具
    check_tools
    
    # 确定审查目标
    if [[ -z "$target" ]]; then
        target="."
    fi
    
    local files=()
    
    if [[ "$target" == "all" ]]; then
        mapfile -t files < <(find_shell_scripts)
    elif [[ -d "$target" ]]; then
        mapfile -t files < <(find "$target" -name "*.sh" -type f | grep -v ".git" | sort)
    elif [[ -f "$target" ]]; then
        files=("$target")
    else
        log_error "目标不存在: $target"
        exit 1
    fi
    
    if [[ ${#files[@]} -eq 0 ]]; then
        log_warning "没有找到 Shell 脚本文件"
        exit 0
    fi
    
    log_info "找到 ${#files[@]} 个 Shell 脚本文件"
    
    # 审查所有文件
    local total_issues=0
    local failed_files=()
    
    for file in "${files[@]}"; do
        if ! review_file "$file" "$format" "$check_only" "$verbose"; then
            ((total_issues++))
            failed_files+=("$file")
        fi
        echo ""
    done

    if ! run_docs_check; then
        ((total_issues++))
        failed_files+=("docs (check-docs.py)")
        echo ""
    fi
    
    # 总结
    echo "=========================================="
    log_info "审查完成"
    echo "总文件数: ${#files[@]}"
    echo "通过文件: $((${#files[@]} - total_issues))"
    echo "失败文件: $total_issues"
    
    if [[ $total_issues -gt 0 ]]; then
        log_error "以下文件需要修复:"
        for file in "${failed_files[@]}"; do
            echo "  - $file"
        done
        exit 1
    else
        log_success "所有文件审查通过！"
        exit 0
    fi
}

# 运行主函数
main "$@"
