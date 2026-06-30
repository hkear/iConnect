#!/bin/bash
# ============================================================
<<<<<<< HEAD
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
=======
#  iConnect 完整构建脚本（musl 静态链接版）
#  产出：x86_64 / aarch64 静态二进制，不依赖系统 GLIBC
#  推荐用法:
#    1) Docker 内构建（推荐，环境固定）:
#       docker build -f deploy/Dockerfile.build -t iconnect-builder .
#       docker run --rm -v "$PWD":/workspace -w /workspace iconnect-builder bash deploy/build-all.sh
#    2) 本机构建（Ubuntu 22.04+，需自行安装 musl 交叉工具链）:
#       sudo bash deploy/build-all.sh
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║       iConnect 完整构建脚本              ║"
echo "  ║       musl static build                  ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# === 0. 读取版本号与 Rust 工具链 ===
VERSION=$(grep -E '^version\s*=' "$PROJECT_ROOT/iconnectd/Cargo.toml" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$VERSION" ]; then
    echo -e "${RED}[错误] 无法从 iconnectd/Cargo.toml 读取版本号${NC}"
    exit 1
fi
echo -e "       ${GREEN}✓${NC} 版本号: ${BOLD}${VERSION}${NC}"

RUST_TOOLCHAIN=$(grep -E '^channel\s*=' "$PROJECT_ROOT/rust-toolchain.toml" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
RUST_TOOLCHAIN=${RUST_TOOLCHAIN:-stable}

# === 1. 检查/安装 musl 工具链与 Rust target ===
echo -e "${GREEN}[1/7]${NC} 检查 musl 交叉编译环境..."

ensure_rustup_target() {
    local target="$1"
    if ! command -v rustup &>/dev/null; then
        return 0
    fi
    if ! rustup target list --installed --toolchain "$RUST_TOOLCHAIN" 2>/dev/null | grep -q "^${target}\$"; then
        echo "  安装 Rust target: $target (toolchain $RUST_TOOLCHAIN)"
        rustup target add --toolchain "$RUST_TOOLCHAIN" "$target"
    fi
}

find_musl_toolchain() {
    local prefix="$1"
    # 优先查找 Dockerfile 中安装的目录
    if [ -x "/opt/musl/${prefix}-cross/bin/${prefix}-gcc" ]; then
        echo "/opt/musl/${prefix}-cross/bin"
        return 0
    fi
    # 其次查找 PATH 中可执行文件
    if command -v "${prefix}-gcc" &>/dev/null; then
        dirname "$(command -v "${prefix}-gcc")"
        return 0
    fi
    return 1
}

ensure_musl_toolchain() {
    local prefix="$1"
    local install_dir="/opt/musl/${prefix}-cross"
    if [ -x "${install_dir}/bin/${prefix}-gcc" ]; then
        return 0
    fi
    if command -v "${prefix}-gcc" &>/dev/null; then
        return 0
    fi
    echo "  未找到 ${prefix} musl 工具链，尝试从 musl.cc 下载..."
    mkdir -p /opt/musl
    curl -fsSL "https://musl.cc/${prefix}-cross.tgz" | tar -xzf - -C /opt/musl
}

ensure_musl_toolchain x86_64-linux-musl
ensure_musl_toolchain aarch64-linux-musl

MUSL_X86_DIR=$(find_musl_toolchain x86_64-linux-musl)
MUSL_AARCH64_DIR=$(find_musl_toolchain aarch64-linux-musl)

export PATH="${MUSL_X86_DIR}:${MUSL_AARCH64_DIR}:$PATH"

export CC_x86_64_unknown_linux_musl="${MUSL_X86_DIR}/x86_64-linux-musl-gcc"
export CXX_x86_64_unknown_linux_musl="${MUSL_X86_DIR}/x86_64-linux-musl-g++"
export AR_x86_64_unknown_linux_musl="${MUSL_X86_DIR}/x86_64-linux-musl-ar"
export CC_aarch64_unknown_linux_musl="${MUSL_AARCH64_DIR}/aarch64-linux-musl-gcc"
export CXX_aarch64_unknown_linux_musl="${MUSL_AARCH64_DIR}/aarch64-linux-musl-g++"
export AR_aarch64_unknown_linux_musl="${MUSL_AARCH64_DIR}/aarch64-linux-musl-ar"

# 让 bindgen 在 musl 交叉编译时能定位到 gcc 与 musl 头文件（kcp-sys 等依赖需要）
MUSL_X86_SYSROOT="$(dirname "$MUSL_X86_DIR")/x86_64-linux-musl"
MUSL_AARCH64_SYSROOT="$(dirname "$MUSL_AARCH64_DIR")/aarch64-linux-musl"
MUSL_X86_GCC_INC="${MUSL_X86_DIR}/../lib/gcc/x86_64-linux-musl/11.2.1/include"
MUSL_AARCH64_GCC_INC="${MUSL_AARCH64_DIR}/../lib/gcc/aarch64-linux-musl/11.2.1/include"
export BINDGEN_EXTRA_CLANG_ARGS_X86_64_UNKNOWN_LINUX_MUSL="--sysroot=${MUSL_X86_SYSROOT} -I${MUSL_X86_GCC_INC} -I${MUSL_X86_SYSROOT}/include"
export BINDGEN_EXTRA_CLANG_ARGS_AARCH64_UNKNOWN_LINUX_MUSL="--sysroot=${MUSL_AARCH64_SYSROOT} -I${MUSL_AARCH64_GCC_INC} -I${MUSL_AARCH64_SYSROOT}/include"

ensure_rustup_target x86_64-unknown-linux-musl
ensure_rustup_target aarch64-unknown-linux-musl

echo -e "       ${GREEN}✓${NC} musl 工具链就绪"
echo "       x86_64:   ${MUSL_X86_DIR}"
echo "       aarch64:  ${MUSL_AARCH64_DIR}"
echo "       rustc:    $(rustc --version)"

# === 2. 安装系统依赖 ===
echo -e "${GREEN}[2/7]${NC} 安装系统依赖..."
if command -v apt-get &>/dev/null; then
    apt-get update -qq || true
    apt-get install -y -qq \
        build-essential curl pkg-config libssl-dev \
        libclang-dev cmake protobuf-compiler unzip \
        fontconfig fonts-dejavu-core \
        2>&1 | tail -3 || true
fi
>>>>>>> master

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
<<<<<<< HEAD
echo "       rustc: $(rustc --version 2>/dev/null || echo N/A)"

# === 2. Install Rust ===
if ! command -v rustc &>/dev/null; then
    echo -e "${GREEN}[2/6]${NC} 安装 Rust..."
=======

# === 3. 安装 Rust（如果尚未安装） ===
echo -e "${GREEN}[3/7]${NC} 检查 Rust..."
if ! command -v rustc &>/dev/null; then
    echo "  安装 Rust..."
>>>>>>> master
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable 2>&1 | tail -2
    export PATH="$HOME/.cargo/bin:$PATH"
    source "$HOME/.cargo/env" 2>/dev/null || true
fi
<<<<<<< HEAD
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
=======
# 重新确认 target 已安装（Rust 刚装完的情况）
ensure_rustup_target x86_64-unknown-linux-musl
ensure_rustup_target aarch64-unknown-linux-musl
echo -e "       ${GREEN}✓${NC} Rust: $(rustc --version)"

# === 4. 构建前端 ===
echo -e "${GREEN}[4/7]${NC} 构建前端..."
cd "$PROJECT_ROOT/iconnect-web"

pnpm config set registry https://registry.npmjs.org/ 2>/dev/null || true
pnpm install --no-frozen-lockfile 2>&1 | tail -5
pnpm approve-builds --all 2>&1 | tail -5 || true
pnpm rebuild 2>&1 | tail -5 || true
pnpm -C frontend-lib exec vite build 2>&1 | tail -5 || echo "  frontend-lib build skipped (dev mode)"
pnpm -C frontend exec vite build 2>&1 | tail -5

echo -e "       ${GREEN}✓${NC} 前端构建完成"

# 根据目标架构设置 kcp-sys bindgen 需要的额外头文件路径
set_kcp_extra_headers() {
    local target="$1"
    case "$target" in
        x86_64-unknown-linux-musl)
            export KCP_SYS_EXTRA_HEADER_PATH="${MUSL_X86_DIR}/../lib/gcc/x86_64-linux-musl/11.2.1/include:${MUSL_X86_SYSROOT}/include"
            ;;
        aarch64-unknown-linux-musl)
            export KCP_SYS_EXTRA_HEADER_PATH="${MUSL_AARCH64_DIR}/../lib/gcc/aarch64-linux-musl/11.2.1/include:${MUSL_AARCH64_SYSROOT}/include"
            ;;
    esac
}

# === 5. 构建 iconnectd (Core) ===
echo -e "${GREEN}[5/7]${NC} 编译 iconnectd (Core)..."
cd "$PROJECT_ROOT"

echo "  -> x86_64-unknown-linux-musl"
set_kcp_extra_headers x86_64-unknown-linux-musl
cargo build --release -p iconnectd --target x86_64-unknown-linux-musl 2>&1 | tail -5
echo -e "       ${GREEN}✓${NC} iconnectd x86_64: $(ls -lh target/x86_64-unknown-linux-musl/release/iconnectd | awk '{print $5}')"

echo "  -> aarch64-unknown-linux-musl"
set_kcp_extra_headers aarch64-unknown-linux-musl
cargo build --release -p iconnectd --target aarch64-unknown-linux-musl 2>&1 | tail -5
echo -e "       ${GREEN}✓${NC} iconnectd aarch64: $(ls -lh target/aarch64-unknown-linux-musl/release/iconnectd | awk '{print $5}')"

# === 6. 构建 iconnect-web (with embed frontend) ===
echo -e "${GREEN}[6/7]${NC} 编译 iconnect-web (含内嵌前端)..."
cd "$PROJECT_ROOT"

# iconnect-web 目前主要随服务端发布在 x86_64 上
# 如需在 aarch64 服务器上运行，可取消下行的 --target 限制
set_kcp_extra_headers x86_64-unknown-linux-musl
cargo build --release -p iconnect-web --features embed --target x86_64-unknown-linux-musl 2>&1 | tail -5
echo -e "       ${GREEN}✓${NC} iconnect-web x86_64: $(ls -lh target/x86_64-unknown-linux-musl/release/iconnect-web | awk '{print $5}')"

# === 7. 打包安装文件 ===
echo -e "${GREEN}[7/7]${NC} 打包安装文件..."

PKG_DIR="$PROJECT_ROOT/dist/packages"
mkdir -p "$PKG_DIR"

# Server (x86_64 only, includes iconnect-web)
SERVER_DIR=/tmp/iconnect-server-pkg
rm -rf "$SERVER_DIR"
mkdir -p "$SERVER_DIR/bin"
cp target/x86_64-unknown-linux-musl/release/iconnectd "$SERVER_DIR/bin/"
cp target/x86_64-unknown-linux-musl/release/iconnect-web "$SERVER_DIR/bin/"
cp target/x86_64-unknown-linux-musl/release/iconnect-cli "$SERVER_DIR/bin/" 2>/dev/null || true
cp "$SCRIPT_DIR/install-server.sh" "$SERVER_DIR/install.sh"
chmod +x "$SERVER_DIR/bin/"* "$SERVER_DIR/install.sh"
cd "$SERVER_DIR" && tar czf "$PKG_DIR/iconnect-server-v${VERSION}-x86_64.tar.gz" .
echo -e "       ${GREEN}✓${NC} Server x86_64: $(ls -lh "$PKG_DIR/iconnect-server-v${VERSION}-x86_64.tar.gz" | awk '{print $5}')"

# Client x86_64
CLIENT_X86_DIR=/tmp/iconnect-client-x86-pkg
rm -rf "$CLIENT_X86_DIR"
mkdir -p "$CLIENT_X86_DIR/bin"
cp target/x86_64-unknown-linux-musl/release/iconnectd "$CLIENT_X86_DIR/bin/"
cp target/x86_64-unknown-linux-musl/release/iconnect-cli "$CLIENT_X86_DIR/bin/" 2>/dev/null || true
cp "$SCRIPT_DIR/install-client.sh" "$CLIENT_X86_DIR/install.sh"
chmod +x "$CLIENT_X86_DIR/bin/"* "$CLIENT_X86_DIR/install.sh"
cd "$CLIENT_X86_DIR" && tar czf "$PKG_DIR/iconnect-client-v${VERSION}-x86_64.tar.gz" .
echo -e "       ${GREEN}✓${NC} Client x86_64: $(ls -lh "$PKG_DIR/iconnect-client-v${VERSION}-x86_64.tar.gz" | awk '{print $5}')"

# Client aarch64
CLIENT_AARCH64_DIR=/tmp/iconnect-client-aarch64-pkg
rm -rf "$CLIENT_AARCH64_DIR"
mkdir -p "$CLIENT_AARCH64_DIR/bin"
cp target/aarch64-unknown-linux-musl/release/iconnectd "$CLIENT_AARCH64_DIR/bin/"
cp target/aarch64-unknown-linux-musl/release/iconnect-cli "$CLIENT_AARCH64_DIR/bin/" 2>/dev/null || true
cp "$SCRIPT_DIR/install-client.sh" "$CLIENT_AARCH64_DIR/install.sh"
chmod +x "$CLIENT_AARCH64_DIR/bin/"* "$CLIENT_AARCH64_DIR/install.sh"
cd "$CLIENT_AARCH64_DIR" && tar czf "$PKG_DIR/iconnect-client-v${VERSION}-aarch64.tar.gz" .
echo -e "       ${GREEN}✓${NC} Client aarch64: $(ls -lh "$PKG_DIR/iconnect-client-v${VERSION}-aarch64.tar.gz" | awk '{print $5}')"
>>>>>>> master

echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║       构建完成!                          ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  安装包: ${BOLD}${PKG_DIR}${NC}"
ls -lh "$PKG_DIR"/*.tar.gz 2>/dev/null
echo ""
<<<<<<< HEAD
echo -e "  二进制文件: ${BOLD}target/release/${NC}"
ls -lh target/release/iconnect* 2>/dev/null
=======
echo -e "  二进制文件: ${BOLD}target/*-unknown-linux-musl/release/${NC}"
ls -lh target/x86_64-unknown-linux-musl/release/iconnect* 2>/dev/null
ls -lh target/aarch64-unknown-linux-musl/release/iconnect* 2>/dev/null
>>>>>>> master
