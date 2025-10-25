#!/bin/bash
# SaltGoat 别名设置脚本
# scripts/setup-aliases.sh

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 显示帮助信息
show_help() {
    echo -e "${BLUE}SaltGoat 别名设置脚本${NC}"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -a, --add <alias>     添加新别名"
    echo "  -r, --remove <alias>  删除别名"
    echo "  -l, --list           列出所有别名"
    echo "  -s, --set <alias>    设置默认别名"
    echo "  -c, --clear          清除所有别名"
    echo "  -h, --help           显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 --add sg          添加 'sg' 别名"
    echo "  $0 --add goat        添加 'goat' 别名"
    echo "  $0 --set sg          设置 'sg' 为默认别名"
    echo "  $0 --list            列出所有别名"
    echo "  $0 --remove sg       删除 'sg' 别名"
}

# 检查别名是否存在
alias_exists() {
    local alias_name="$1"
    grep -q "alias $alias_name='/usr/local/bin/saltgoat'" ~/.bashrc 2>/dev/null
}

# 检查别名冲突
check_alias_conflict() {
    local alias_name="$1"
    
    # 检查是否是系统命令
    if command -v "$alias_name" >/dev/null 2>&1; then
        echo -e "${RED}错误: '$alias_name' 是系统命令，不能用作别名${NC}"
        return 1
    fi
    
    # 检查是否是用户名
    if id "$alias_name" >/dev/null 2>&1; then
        echo -e "${YELLOW}警告: '$alias_name' 是系统用户名，建议使用其他别名${NC}"
        echo -e "${BLUE}建议的替代别名:${NC}"
        echo "  - ${alias_name}goat"
        echo "  - ${alias_name}sg"
        echo "  - ${alias_name}lemp"
        return 1
    fi
    
    # 检查是否是保留字
    case "$alias_name" in
        "if"|"then"|"else"|"fi"|"for"|"while"|"do"|"done"|"case"|"esac"|"function"|"return"|"exit")
            echo -e "${RED}错误: '$alias_name' 是 Shell 保留字，不能用作别名${NC}"
            return 1
            ;;
    esac
    
    return 0
}

# 添加别名
add_alias() {
    local alias_name="$1"
    
    if [[ -z "$alias_name" ]]; then
        echo -e "${RED}错误: 请提供别名名称${NC}"
        return 1
    fi
    
    # 检查别名冲突
    if ! check_alias_conflict "$alias_name"; then
        return 1
    fi
    
    if alias_exists "$alias_name"; then
        echo -e "${YELLOW}警告: 别名 '$alias_name' 已存在${NC}"
        return 1
    fi
    
    echo "alias $alias_name='/usr/local/bin/saltgoat'" >> ~/.bashrc
    echo -e "${GREEN}成功添加别名: $alias_name${NC}"
    
    # 在当前会话中立即生效
    eval "alias $alias_name='/usr/local/bin/saltgoat'"
    echo -e "${BLUE}提示: 别名已在当前会话中生效${NC}"
}

# 删除别名
remove_alias() {
    local alias_name="$1"
    
    if [[ -z "$alias_name" ]]; then
        echo -e "${RED}错误: 请提供别名名称${NC}"
        return 1
    fi
    
    if ! alias_exists "$alias_name"; then
        echo -e "${YELLOW}警告: 别名 '$alias_name' 不存在${NC}"
        return 1
    fi
    
    # 删除别名行
    sed -i "/alias $alias_name='\/usr\/local\/bin\/saltgoat'/d" ~/.bashrc
    echo -e "${GREEN}成功删除别名: $alias_name${NC}"
    
    # 在当前会话中立即生效
    unalias "$alias_name" 2>/dev/null || true
    echo -e "${BLUE}提示: 别名已在当前会话中删除${NC}"
}

# 列出所有别名
list_aliases() {
    echo -e "${BLUE}SaltGoat 别名列表:${NC}"
    echo ""
    
    local aliases
    aliases=$(grep "alias.*='/usr/local/bin/saltgoat'" ~/.bashrc 2>/dev/null | sed "s/alias //" | sed "s/='\/usr\/local\/bin\/saltgoat'//")
    
    if [[ -z "$aliases" ]]; then
        echo -e "${YELLOW}没有找到任何别名${NC}"
        return 1
    fi
    
    echo -e "${GREEN}当前别名:${NC}"
    for alias in $aliases; do
        echo "  - $alias"
    done
    
    echo ""
    echo -e "${BLUE}使用方法:${NC}"
    for alias in $aliases; do
        echo "  $alias help"
    done
}

# 设置默认别名
set_default_alias() {
    local alias_name="$1"
    
    if [[ -z "$alias_name" ]]; then
        echo -e "${RED}错误: 请提供别名名称${NC}"
        return 1
    fi
    
    # 清除所有现有别名
    clear_aliases
    
    # 添加新别名
    add_alias "$alias_name"
    
    echo -e "${GREEN}成功设置默认别名: $alias_name${NC}"
}

# 清除所有别名
clear_aliases() {
    # 删除所有 SaltGoat 别名
    sed -i "/alias.*='\/usr\/local\/bin\/saltgoat'/d" ~/.bashrc
    echo -e "${GREEN}成功清除所有别名${NC}"
}

# 主函数
main() {
    case "$1" in
        -a|--add)
            add_alias "$2"
            ;;
        -r|--remove)
            remove_alias "$2"
            ;;
        -l|--list)
            list_aliases
            ;;
        -s|--set)
            set_default_alias "$2"
            ;;
        -c|--clear)
            clear_aliases
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo -e "${RED}错误: 未知选项 '$1'${NC}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
