#!/bin/sh
# ============================================================
#  iConnect Client 一键安装脚本
#  适用: OpenWrt / Debian / Ubuntu
#  用法: sh install.sh
#  解压后直接运行，文件结构与脚本路径匹配
# ============================================================
set -e

# === 颜色（OpenWrt ash 兼容） ===
if [ -z "$TERM" ] || [ "$TERM" = "dumb" ]; then
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''; BOLD=''
else
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
    BOLD='\033[1m'
fi

echo "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║       iConnect Client 安装向导           ║"
echo "  ║       v1.0.0 - 异地组网客户端            ║"
echo "  ╚══════════════════════════════════════════╝"
echo "${NC}"

[ "$(id -u)" -ne 0 ] && { echo "${RED}[错误] 请使用 root 运行${NC}"; exit 1; }

# === 检测架构 ===
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)   BIN_ARCH="x86_64"; BIN_DIR="bin" ;;
    aarch64|arm64)  BIN_ARCH="aarch64"; BIN_DIR="bin" ;;
    armv7l|armv7)   BIN_ARCH="armv7"; BIN_DIR="bin" ;;
    mips)           BIN_ARCH="mips"; BIN_DIR="bin" ;;
    mipsel)         BIN_ARCH="mipsel"; BIN_DIR="bin" ;;
    *) echo "${RED}[错误] 不支持的架构: ${ARCH}${NC}"; exit 1 ;;
esac
echo "${GREEN}[✓]${NC} 架构: ${BOLD}${ARCH}${NC}"

# === 检测系统 ===
if [ -f /etc/openwrt_release ]; then
    OS_TYPE="openwrt"
    echo "${GREEN}[✓]${NC} 系统: ${BOLD}OpenWrt${NC}"
elif [ -f /etc/os-release ]; then
    . /etc/os-release 2>/dev/null
    OS_TYPE="linux"
    echo "${GREEN}[✓]${NC} 系统: ${BOLD}${ID:-linux}${NC}"
else
    OS_TYPE="linux"
fi

# === 第一步：服务器连接 ===
echo ""
echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${BOLD}  第一步：连接配置${NC}"
echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

read -p "  服务器地址 (IP或域名): " SERVER_ADDR
[ -z "$SERVER_ADDR" ] && { echo "${RED}[错误] 服务器地址不能为空${NC}"; exit 1; }

read -p "  服务器端口 [1993]: " SERVER_PORT; SERVER_PORT=${SERVER_PORT:-1993}
read -p "  组网名称 [iconnect]: " NETWORK_NAME; NETWORK_NAME=${NETWORK_NAME:-iconnect}
read -p "  组网密钥: " NETWORK_SECRET
[ -z "$NETWORK_SECRET" ] && { echo "${RED}[错误] 密钥不能为空${NC}"; exit 1; }

# === 第二步：安装确认 ===
echo ""
echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${BOLD}  第二步：安装确认${NC}"
echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

INSTALL_DIR="/usr/bin"
CONFIG_DIR="/etc/iconnect"
echo "  安装目录: ${BOLD}${INSTALL_DIR}${NC}"
echo "  配置目录: ${BOLD}${CONFIG_DIR}${NC}"
read -p "  确认安装? [Y/n]: " CONFIRM
[ "$CONFIRM" = "n" ] || [ "$CONFIRM" = "N" ] && { echo "已取消"; exit 0; }

# === 第三步：安装文件 ===
echo ""
echo "${GREEN}[1/4]${NC} 安装二进制..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "$SCRIPT_DIR/$BIN_DIR/iconnectd" ]; then
    cp "$SCRIPT_DIR/$BIN_DIR/iconnectd" "$INSTALL_DIR/iconnectd"
else
    echo "${RED}[错误] 找不到 bin/iconnectd, 架构 ${BIN_ARCH} 可能不支持${NC}"
    exit 1
fi
chmod +x "$INSTALL_DIR/iconnectd"
echo "       ${GREEN}✓${NC} iconnectd (${BIN_ARCH})"

if [ -f "$SCRIPT_DIR/$BIN_DIR/iconnect-cli" ]; then
    cp "$SCRIPT_DIR/$BIN_DIR/iconnect-cli" "$INSTALL_DIR/iconnect-cli"
    chmod +x "$INSTALL_DIR/iconnect-cli"
fi

mkdir -p "$CONFIG_DIR"

# === 第四步：创建服务 ===
echo "${GREEN}[2/4]${NC} 创建开机自启..."

if [ "$OS_TYPE" = "openwrt" ]; then
    cat > /etc/init.d/iconnect << INIT_SCRIPT
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

NAME=iconnectd
PROG=/usr/bin/iconnectd

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/iconnectd \\
        --network-name ${NETWORK_NAME} \\
        --network-secret ${NETWORK_SECRET} \\
        --disable-p2p --no-listener --dhcp \\
        --disable-udp-hole-punching --disable-tcp-hole-punching --disable-upnp \\
        --default-protocol tcp \\
        --peers tcp://${SERVER_ADDR}:${SERVER_PORT}
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() { killall iconnectd 2>/dev/null || true; }
reload_service() { stop; start; }
INIT_SCRIPT
    chmod +x /etc/init.d/iconnect
    /etc/init.d/iconnect enable 2>/dev/null || true
    echo "       ${GREEN}✓${NC} OpenWrt init.d 服务"
else
    cat > /etc/systemd/system/iconnectd.service << SYSTEMD_EOF
[Unit]
Description=iConnect Client Service
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/iconnectd \\
  --network-name ${NETWORK_NAME} \\
  --network-secret ${NETWORK_SECRET} \\
  --disable-p2p --no-listener --dhcp \\
  --disable-udp-hole-punching --disable-tcp-hole-punching --disable-upnp \\
  --default-protocol tcp \\
  --peers tcp://${SERVER_ADDR}:${SERVER_PORT}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable iconnectd 2>/dev/null || true
    echo "       ${GREEN}✓${NC} systemd 服务"
fi

# === 第五步：启动 ===
echo "${GREEN}[3/4]${NC} 启动客户端..."
killall iconnectd 2>/dev/null || true; sleep 1

/usr/bin/iconnectd \
    --network-name "$NETWORK_NAME" --network-secret "$NETWORK_SECRET" \
    --disable-p2p --no-listener --dhcp \
    --disable-udp-hole-punching --disable-tcp-hole-punching --disable-upnp \
    --default-protocol tcp \
    --peers "tcp://${SERVER_ADDR}:${SERVER_PORT}" \
    > /tmp/iconnectd.log 2>&1 &
sleep 5

# === 验证 ===
echo "${GREEN}[4/4]${NC} 验证..."

TUN_IP=$(ip addr show tun0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)

echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║     iConnect Client 安装完成!            ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

if pgrep iconnectd >/dev/null 2>&1; then
    echo -e "  ${BOLD}状态:${NC}   ${GREEN}● 运行中${NC} (PID: $(pgrep iconnectd))"
else
    echo -e "  ${BOLD}状态:${NC}   ${RED}○ 未运行${NC}, 日志: /tmp/iconnectd.log"
fi
[ -n "$TUN_IP" ] && echo -e "  ${BOLD}虚拟IP:${NC} ${GREEN}${TUN_IP}${NC}" || echo -e "  ${BOLD}虚拟IP:${NC} ${YELLOW}等待 DHCP...${NC}"

echo ""
echo -e "  ${BOLD}服务器:${NC}   ${SERVER_ADDR}:${SERVER_PORT}"
echo -e "  ${BOLD}管理:${NC}"
if [ "$OS_TYPE" = "openwrt" ]; then
    echo "    /etc/init.d/iconnect start/stop/status"
else
    echo "    systemctl start/stop/status iconnectd"
fi
echo "    tail -f /tmp/iconnectd.log"
