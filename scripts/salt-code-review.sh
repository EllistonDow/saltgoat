#!/bin/bash
# SaltGoat Salt 项目代码审查脚本
# scripts/salt-code-review.sh

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
    echo "SaltGoat Salt 项目代码审查工具"
    echo ""
    echo "用法: $0 [选项] [文件/目录]"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -a, --all      审查所有文件"
    echo "  -s, --salt     只审查 Salt 相关文件"
    echo "  -b, --bash     只审查 Bash 脚本"
    echo "  -f, --format   格式化代码"
    echo "  -c, --check    只检查不修复"
    echo "  -v, --verbose  详细输出"
    echo ""
    echo "脚本会在完成 Salt / Bash 检查后自动运行 docs Lint (scripts/check-docs.py)"
    echo ""
    echo "示例:"
    echo "  $0                    # 审查当前目录所有文件"
    echo "  $0 saltgoat           # 审查主脚本"
    echo "  $0 salt/              # 审查 Salt 状态文件"
    echo "  $0 -s                 # 只审查 Salt 文件"
    echo "  $0 -b                 # 只审查 Bash 脚本"
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
    
    if ! command -v salt-call &> /dev/null; then
        missing_tools+=("salt-call")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "缺少以下工具: ${missing_tools[*]}"
        log_info "请运行: sudo apt install shellcheck shfmt"
        exit 1
    fi
}

# 检查 Salt 状态文件语法
check_salt_syntax() {
    local file="$1"
    local verbose="$2"
    
    log_info "检查 Salt 状态文件语法: $file"
    
    # 检查 .sls 文件语法
    if [[ "$file" == *.sls ]]; then
        if [[ $EUID -ne 0 ]]; then
            log_warning "非 root 环境，跳过 Salt state.show_sls 校验: $file"
            return 0
        fi
        if [[ "$file" == */pillar/*.sls ]]; then
            return 0
        fi
        if salt-call --local state.show_sls "${file%.sls}" --out=null 2>/dev/null; then
            log_success "Salt 状态文件语法正确: $file"
            return 0
        else
            log_error "Salt 状态文件语法错误: $file"
            if [[ "$verbose" == "true" ]]; then
                salt-call --local state.show_sls "${file%.sls}" 2>&1 | head -20
            fi
            return 1
        fi
    fi
    
    return 0
}

# 检查 Salt Pillar 文件
check_pillar_syntax() {
    local file="$1"
    
    if [[ "$file" == */pillar/*.sls ]]; then
        log_info "检查 Pillar 文件: $file"
        if [[ ! -r "$file" ]]; then
            log_warning "Pillar 文件无法读取（可能权限受限），跳过检查: $file"
            return 0
        fi
        if grep -q "{%" "$file" || grep -q "{{" "$file"; then
            log_warning "检测到 Jinja 模板，跳过 YAML 语法检查: $file"
            return 0
        fi
        
        # 检查 YAML 语法
        if command -v python3 &> /dev/null; then
            if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
                log_success "Pillar 文件语法正确: $file"
                return 0
            else
                log_error "Pillar 文件 YAML 语法错误: $file"
                return 1
            fi
        fi
    fi
    
    return 0
}

# 检查 Salt 最佳实践
check_salt_best_practices() {
    local file="$1"

    local issues=0
    local allow_sudo_files=("./core/install.sh" "./core/system.sh")

    # 检查是否使用 salt-call --local
    if grep -q "salt-call" "$file" && ! grep -q "salt-call --local" "$file"; then
        log_warning "建议使用 'salt-call --local' 而不是 'salt-call': $file"
        ((issues++))
    fi
    
    # 检查是否使用 cmd.run 而不是直接命令
    if grep -q "sudo " "$file" && grep -q "salt-call" "$file"; then
        local skip_sudo_warning="false"
        for allow in "${allow_sudo_files[@]}"; do
            if [[ "$file" == "$allow" ]]; then
                skip_sudo_warning="true"
                break
            fi
        done
        if [[ "$skip_sudo_warning" == "false" ]]; then
            log_warning "在 Salt 脚本中避免使用 sudo，优先使用 Salt 模块: $file"
            ((issues++))
        fi
    fi
    
    # 检查错误处理
    if grep -q "salt-call" "$file" && ! grep -q "2>/dev/null" "$file"; then
        log_warning "Salt 命令调用建议添加错误处理: $file"
        ((issues++))
    fi
    
    # 检查硬编码路径
    if grep -q "/var/www\|/etc/nginx\|/etc/mysql" "$file"; then
        log_warning "建议使用 Salt 变量而不是硬编码路径: $file"
        ((issues++))
    fi
    
    if [[ "${STRICT_SALT_CHECKS:-0}" == "1" ]]; then
        return $issues
    fi

    return 0
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
        if shfmt -d "$file" | grep -q .; then
            log_warning "代码格式需要调整: $file"
            shfmt -d "$file"
            return 1
        else
            log_success "代码格式正确: $file"
            return 0
        fi
    else
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

# 检查 Salt 模块使用
check_salt_modules() {
    local file="$1"
    
    local issues=0
    
    # 检查是否使用了推荐的 Salt 模块
    if grep -q "cmd.run.*mkdir" "$file"; then
        log_warning "建议使用 'file.mkdir' 而不是 'cmd.run mkdir': $file"
        ((issues++))
    fi
    
    if grep -q "cmd.run.*chown" "$file"; then
        log_warning "建议使用 'file.chown' 而不是 'cmd.run chown': $file"
        ((issues++))
    fi
    
    if grep -q "cmd.run.*chmod" "$file"; then
        log_warning "建议使用 'file.set_mode' 而不是 'cmd.run chmod': $file"
        ((issues++))
    fi
    
    if grep -q "cmd.run.*cp " "$file"; then
        log_warning "建议使用 'file.copy' 而不是 'cmd.run cp': $file"
        ((issues++))
    fi

    if [[ "${STRICT_SALT_CHECKS:-0}" == "1" ]]; then
        return $issues
    fi

    return 0
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
    
    # 根据文件类型进行不同检查
    if [[ "$file" == *.sh ]]; then
        # Bash 脚本检查
        if ! run_shellcheck "$file" "$verbose"; then
            ((issues++))
        fi
        
        # Salt 最佳实践检查
        check_salt_best_practices "$file" || ((issues += $?))
        
        # Salt 模块使用检查
        check_salt_modules "$file" || ((issues += $?))
        
        # 格式化
        if [[ "$format" == "true" ]]; then
            if ! run_shfmt "$file" "$check_only"; then
                ((issues++))
            fi
        fi
        
    elif [[ "$file" == *.sls ]]; then
        # Salt 状态文件检查
        check_salt_syntax "$file" "$verbose" || ((issues++))
        check_pillar_syntax "$file" || ((issues++))
        
    elif [[ "$file" == *.yml ]] || [[ "$file" == *.yaml ]]; then
        # YAML 文件检查
        check_pillar_syntax "$file" || ((issues++))
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

# 查找 Salt 相关文件
find_salt_files() {
    find . -name "*.sls" -o -name "*.yml" -o -name "*.yaml" | grep -v ".git" | sort
}

# 查找 Bash 脚本
find_bash_files() {
    find . -name "*.sh" -type f | grep -v ".git" | sort
}

# 查找所有相关文件
find_all_files() {
    find . \( -name "*.sh" -o -name "*.sls" -o -name "*.yml" -o -name "*.yaml" \) -type f | grep -v ".git" | sort
}

# 主函数
main() {
    local format="false"
    local check_only="false"
    local verbose="false"
    local target=""
    local file_type="all"
    
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
            -s|--salt)
                file_type="salt"
                shift
                ;;
            -b|--bash)
                file_type="bash"
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
        case $file_type in
            "salt")
                mapfile -t files < <(find_salt_files)
                ;;
            "bash")
                mapfile -t files < <(find_bash_files)
                ;;
            *)
                mapfile -t files < <(find_all_files)
                ;;
        esac
    elif [[ -d "$target" ]]; then
        case $file_type in
            "salt")
                mapfile -t files < <(find "$target" \( -name "*.sls" -o -name "*.yml" -o -name "*.yaml" \) -type f | grep -v ".git" | sort)
                ;;
            "bash")
                mapfile -t files < <(find "$target" -name "*.sh" -type f | grep -v ".git" | sort)
                ;;
            *)
                mapfile -t files < <(find "$target" \( -name "*.sh" -o -name "*.sls" -o -name "*.yml" -o -name "*.yaml" \) -type f | grep -v ".git" | sort)
                ;;
        esac
    elif [[ -f "$target" ]]; then
        files=("$target")
    else
        log_error "目标不存在: $target"
        exit 1
    fi
    
    if [[ ${#files[@]} -eq 0 ]]; then
        log_warning "没有找到相关文件"
        exit 0
    fi
    
    log_info "找到 ${#files[@]} 个文件"
    
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
    log_info "Salt 项目审查完成"
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
