#!/bin/bash
# SaltGoat 发布脚本
# scripts/release.sh

set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 获取版本号
VERSION=$(grep 'SCRIPT_VERSION=' saltgoat | cut -d'"' -f2)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}    SaltGoat Release Script${NC}"
echo -e "${BLUE}==========================================${NC}"
echo -e "${GREEN}版本: $VERSION${NC}"
echo ""

# 检查Git状态
if command -v git >/dev/null 2>&1; then
    if [[ -d ".git" ]]; then
        echo -e "${YELLOW}检查Git状态...${NC}"
        if ! git diff --quiet; then
            echo -e "${RED}错误: 有未提交的更改${NC}"
            echo "请先提交所有更改:"
            echo "  git add ."
            echo "  git commit -m 'Release v$VERSION'"
            exit 1
        fi
        
        # 创建标签
        echo -e "${YELLOW}创建Git标签 v$VERSION...${NC}"
        git tag -a "v$VERSION" -m "Release v$VERSION"
        echo -e "${GREEN}✅ Git标签创建成功${NC}"
    else
        echo -e "${YELLOW}警告: 当前目录不是Git仓库${NC}"
    fi
else
    echo -e "${YELLOW}警告: Git未安装，跳过版本控制${NC}"
fi

# 创建发布包
echo -e "${YELLOW}创建发布包...${NC}"
RELEASE_DIR="/tmp/saltgoat-$VERSION"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# 复制文件
cp -r saltgoat lib core services monitoring salt scripts templates "$RELEASE_DIR/"
cp README.md CHANGELOG.md env.example "$RELEASE_DIR/"

# 创建安装脚本
cat > "$RELEASE_DIR/install.sh" << 'EOF'
#!/bin/bash
# SaltGoat 安装脚本

set -e

echo "=========================================="
echo "    SaltGoat Installation"
echo "=========================================="

# 检查系统
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo "错误: 此脚本仅支持Linux系统"
    exit 1
fi

# 检查Ubuntu版本
if ! command -v lsb_release >/dev/null 2>&1; then
    echo "错误: 请安装lsb-release包"
    exit 1
fi

UBUNTU_VERSION=$(lsb_release -rs)
if [[ "$UBUNTU_VERSION" != "24.04" ]]; then
    echo "警告: 此脚本专为Ubuntu 24.04设计，当前版本: $UBUNTU_VERSION"
    read -p "是否继续? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 安装到系统
echo "安装SaltGoat到系统路径..."
sudo cp saltgoat /usr/local/bin/
sudo chmod +x /usr/local/bin/saltgoat

# 设置别名
echo "设置别名..."
if ! grep -q "saltgoat" ~/.bashrc; then
    cat >> ~/.bashrc << 'ALIAS_EOF'

# SaltGoat 别名
alias sg='/usr/local/bin/saltgoat'
alias goat='/usr/local/bin/saltgoat'
alias salt='/usr/local/bin/saltgoat'
alias lemp='/usr/local/bin/saltgoat'
ALIAS_EOF
fi

echo "✅ SaltGoat安装完成!"
echo ""
echo "使用方法:"
echo "  sg help"
echo "  goat status"
echo "  salt versions"
echo "  lemp install all"
EOF

chmod +x "$RELEASE_DIR/install.sh"

echo -e "${GREEN}✅ 发布目录创建完成: $RELEASE_DIR${NC}"
echo ""
echo -e "${BLUE}发布目录内容:${NC}"
echo "  - SaltGoat 主程序"
echo "  - 所有服务模块"
echo "  - Salt 状态文件"
echo "  - 监控和脚本"
echo "  - 安装脚本"
echo "  - 文档和配置"
echo ""
echo -e "${YELLOW}使用方法:${NC}"
echo "  1. 进入目录: cd $RELEASE_DIR"
echo "  2. 安装: ./install.sh"
echo "  3. 使用: saltgoat help"