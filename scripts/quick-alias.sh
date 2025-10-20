#!/bin/bash
# SaltGoat 快速别名设置
# scripts/quick-alias.sh

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}SaltGoat 快速别名设置${NC}"
echo ""

# 检查是否已安装到系统
if [[ ! -f "/usr/local/bin/saltgoat" ]]; then
    echo -e "${RED}错误: SaltGoat 未安装到系统路径${NC}"
    echo "请先运行: saltgoat system install"
    exit 1
fi

# 设置常用别名
echo -e "${GREEN}设置常用别名...${NC}"

# 添加到 .bashrc
cat >> ~/.bashrc << 'EOF'

# SaltGoat 别名
alias sg='/usr/local/bin/saltgoat'
alias goat='/usr/local/bin/saltgoat'
alias salt='/usr/local/bin/saltgoat'
alias lemp='/usr/local/bin/saltgoat'
EOF

# 在当前会话中立即生效
alias sg='/usr/local/bin/saltgoat'
alias goat='/usr/local/bin/saltgoat'
alias salt='/usr/local/bin/saltgoat'
alias lemp='/usr/local/bin/saltgoat'

echo -e "${GREEN}✅ 别名设置完成！${NC}"
echo ""
echo -e "${BLUE}可用的别名:${NC}"
echo "  sg     - 短别名"
echo "  goat   - 动物别名"
echo "  salt   - Salt 别名"
echo "  lemp   - LEMP 别名"
echo ""
echo -e "${BLUE}使用方法:${NC}"
echo "  sg help"
echo "  goat status"
echo "  salt versions"
echo "  lemp install all"
echo ""
echo -e "${BLUE}提示:${NC}"
echo "  - 别名已添加到 ~/.bashrc，新终端会话会自动生效"
echo "  - 当前会话中别名已立即生效"
echo "  - 要删除别名，请编辑 ~/.bashrc 文件"
