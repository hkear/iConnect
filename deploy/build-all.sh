#!/bin/bash
# ============================================================
#  iConnect 完整构建脚本
#  在全新 Ubuntu 22.04/24.04 上运行
#  用法: sudo bash build-all.sh
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║       iConnect 完整构建脚本              ║"
echo "  ║       v1.0.0 - One-Click Build           ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# === 1. Install system deps ===
echo -e "${GREEN}[1/6]${NC} 安装系统依赖..."
apt-get update -qq
apt-get install -y -qq \
    build-essential curl pkg-config libssl-dev \
    libclang-dev cmake protobuf-compiler unzip \
    fontconfig fonts-dejavu-core \
    2>&1 | tail -3

# Node.js via nvm or apt
if ! command -v node &>/dev/null; then
    echo "  安装 Node.js 22.x..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - 2>&1 | tail -2
    apt-get install -y -qq nodejs 2>&1 | tail -2
fi

# pnpm via npm
if ! command -v pnpm &>/dev/null; then
    npm install -g pnpm 2>&1 | tail -2
fi

echo -e "       ${GREEN}✓${NC} 系统依赖就绪"
echo "       node: $(node --version 2>/dev/null || echo N/A)"
echo "       npm:  $(npm --version 2>/dev/null || echo N/A)"
echo "       pnpm: $(pnpm --version 2>/dev/null || echo N/A)"
echo "       rustc: $(rustc --version 2>/dev/null || echo N/A)"

# === 2. Install Rust ===
if ! command -v rustc &>/dev/null; then
    echo -e "${GREEN}[2/6]${NC} 安装 Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable 2>&1 | tail -2
    export PATH="$HOME/.cargo/bin:$PATH"
    source "$HOME/.cargo/env" 2>/dev/null || true
fi
echo -e "       ${GREEN}✓${NC} Rust: $(rustc --version)"

# === 3. Build Frontend ===
echo -e "${GREEN}[3/6]${NC} 构建前端..."
cd "$(dirname "$0")/../iconnect-web"

# Build frontend-lib
cd frontend-lib
pnpm config set registry https://registry.npmjs.org/ 2>/dev/null || true
pnpm install --no-frozen-lockfile 2>&1 | tail -3
pnpm build 2>&1 | tail -3 || echo "  frontend-lib build skipped (dev mode)"

# Build main frontend
cd ../frontend
pnpm config set registry https://registry.npmjs.org/ 2>/dev/null || true
pnpm install --no-frozen-lockfile 2>&1 | tail -3
npx vite build 2>&1 | tail -5

echo -e "       ${GREEN}✓${NC} 前端构建完成"
ls -la dist/ 2>/dev/null | head -3

# === 4. Build iconnectd (Core) ===
echo -e "${GREEN}[4/6]${NC} 编译 iconnectd (Core)..."
cd "$(dirname "$0")/.."
cargo build --release -p iconnectd 2>&1 | tail -3
echo -e "       ${GREEN}✓${NC} iconnectd: $(ls -lh target/release/iconnectd | awk '{print $5}')"

# === 5. Build iconnect-web (with embed frontend) ===
echo -e "${GREEN}[5/6]${NC} 编译 iconnect-web (含内嵌前端)..."
cargo build --release -p iconnect-web --features embed 2>&1 | tail -3
echo -e "       ${GREEN}✓${NC} iconnect-web: $(ls -lh target/release/iconnect-web | awk '{print $5}')"

# === 6. Package ===
echo -e "${GREEN}[6/6]${NC} 打包安装文件..."

PKG_DIR="$(dirname "$0")/../dist/packages"
mkdir -p "$PKG_DIR"

# Server
SERVER_DIR=/tmp/iconnect-server-pkg
rm -rf "$SERVER_DIR"
mkdir -p "$SERVER_DIR/bin"
cp target/release/iconnectd "$SERVER_DIR/bin/"
cp target/release/iconnect-web "$SERVER_DIR/bin/"
cp target/release/iconnect-cli "$SERVER_DIR/bin/" 2>/dev/null || true
cp deploy/install-server.sh "$SERVER_DIR/install.sh"
chmod +x "$SERVER_DIR/bin/"* "$SERVER_DIR/install.sh"
cd "$SERVER_DIR" && tar czf "$PKG_DIR/iconnect-server-v1.0.0-x86_64.tar.gz" .
echo -e "       ${GREEN}✓${NC} Server: $(ls -lh "$PKG_DIR/iconnect-server-v1.0.0-x86_64.tar.gz" | awk '{print $5}')"

echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║       构建完成!                          ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  安装包: ${BOLD}${PKG_DIR}${NC}"
ls -lh "$PKG_DIR"/*.tar.gz 2>/dev/null
echo ""
echo -e "  二进制文件: ${BOLD}target/release/${NC}"
ls -lh target/release/iconnect* 2>/dev/null
