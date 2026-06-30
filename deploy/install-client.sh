#!/bin/sh
# ============================================================
#  iConnect Client 一键安装脚本
#  支持: OpenWrt / Debian / Ubuntu / CentOS
#
#  用法:
#    交互模式:  sh install.sh
#    命令行模式: sh install.sh <SERVER_IP> [SERVER_PORT] [NETWORK_NAME] [NETWORK_SECRET]
#    示例:       sh install.sh 121.4.21.208 1993 mynet mykey
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'
[ -z "$TERM" ] || [ "$TERM" = "dumb" ] && { RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''; BOLD=''; }

echo "${CYAN}${BOLD}"
echo "  iConnect Client v1.1.1 -- 异地组网客户端"
echo "${NC}"

[ "$(id -u)" -ne 0 ] && { echo "${RED}[错误] 请使用 root 运行${NC}"; exit 1; }

# ============================================================
#  参数解析：支持命令行直接传参，跳过交互
# ============================================================
if [ -n "$1" ]; then
    SERVER_ADDR="$1"
    SERVER_PORT="${2:-1993}"
    NETWORK_NAME="${3:-iconnect}"
    NETWORK_SECRET="$4"
    NONINTERACTIVE=true
else
    NONINTERACTIVE=false
fi

# ============================================================
#  检测系统
# ============================================================
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)   BIN_ARCH="x86_64" ;;
    aarch64|arm64)  BIN_ARCH="aarch64" ;;
    armv7l|armv7)   BIN_ARCH="armv7" ;;
    mips)           BIN_ARCH="mips" ;;
    mipsel)         BIN_ARCH="mipsel" ;;
    *) echo "${RED}[错误] 不支持的架构: ${ARCH}${NC}"; exit 1 ;;
esac

if [ -f /etc/openwrt_release ]; then
    OS_TYPE="openwrt"
else
    OS_TYPE="linux"
fi
echo "${GREEN}[✓]${NC} 架构: ${ARCH} | 系统: ${OS_TYPE}"

# ============================================================
#  交互模式：引导配置
# ============================================================
if [ "$NONINTERACTIVE" = false ]; then
    echo ""
    read -p "  服务器地址: " SERVER_ADDR
    [ -z "$SERVER_ADDR" ] && { echo "${RED}[错误] 服务器地址不能为空${NC}"; exit 1; }
    read -p "  服务器端口 [1993]: " SERVER_PORT; SERVER_PORT=${SERVER_PORT:-1993}
    read -p "  组网名称 [iconnect]: " NETWORK_NAME; NETWORK_NAME=${NETWORK_NAME:-iconnect}
    read -p "  组网密钥: " NETWORK_SECRET
    [ -z "$NETWORK_SECRET" ] && { echo "${RED}[错误] 密钥不能为空${NC}"; exit 1; }
fi

# ============================================================
#  查找二进制文件
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_PATH=""

# 查找顺序: bin/iconnectd → ./iconnectd → ../*/bin/iconnectd
for dir in "$SCRIPT_DIR/bin" "$SCRIPT_DIR" "$SCRIPT_DIR/bin-${BIN_ARCH}"; do
    if [ -f "$dir/iconnectd" ]; then
        BIN_PATH="$dir/iconnectd"
        break
    fi
done

if [ -z "$BIN_PATH" ]; then
    echo "${RED}[错误] 找不到 iconnectd (架构: ${BIN_ARCH})${NC}"
    echo "请确认安装包结构正确:  bin/iconnectd 应与 install.sh 在同一目录"
    echo "当前目录: $SCRIPT_DIR"
    echo "查找路径:"
    echo "  $SCRIPT_DIR/bin/iconnectd"
    echo "  $SCRIPT_DIR/iconnectd"
    ls -la "$SCRIPT_DIR/" 2>/dev/null || true
    ls -la "$SCRIPT_DIR/bin/" 2>/dev/null || true
    exit 1
fi
echo "${GREEN}[✓]${NC} 二进制: $BIN_PATH"

# ============================================================
#  安装确认
# ============================================================
echo ""
echo "  服务器:   ${SERVER_ADDR}:${SERVER_PORT}"
echo "  组网名称: ${NETWORK_NAME}"
echo "  组网密钥: ${NETWORK_SECRET}"

if [ "$NONINTERACTIVE" = false ]; then
    read -p "  确认安装? [Y/n]: " CONFIRM
    [ "$CONFIRM" = "n" ] || [ "$CONFIRM" = "N" ] && { echo "已取消"; exit 0; }
fi

# ============================================================
#  停止旧进程
# ============================================================
killall iconnectd 2>/dev/null || true
sleep 1

# ============================================================
#  安装二进制
# ============================================================
INSTALL_DIR="/usr/bin"
mkdir -p /etc/iconnect
cp "$BIN_PATH" "$INSTALL_DIR/iconnectd"
chmod +x "$INSTALL_DIR/iconnectd"
echo "${GREEN}[✓]${NC} iconnectd → $INSTALL_DIR/iconnectd"

CLI_PATH=""
for d in "$SCRIPT_DIR/bin" "$SCRIPT_DIR"; do
    [ -f "$d/iconnect-cli" ] && CLI_PATH="$d/iconnect-cli" && break
done
if [ -n "$CLI_PATH" ]; then
    cp "$CLI_PATH" "$INSTALL_DIR/iconnect-cli"
    chmod +x "$INSTALL_DIR/iconnect-cli"
    echo "${GREEN}[✓]${NC} iconnect-cli → $INSTALL_DIR/iconnect-cli"
fi

# ============================================================
#  创建自启服务
# ============================================================
if [ "$OS_TYPE" = "openwrt" ]; then
    cat > /etc/init.d/iconnect << INITEND
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
NAME=iconnectd
PROG=/usr/bin/iconnectd
start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/iconnectd \\
        --network-name ${NETWORK_NAME} \\
        --network-secret '${NETWORK_SECRET}' \\
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
INITEND
    chmod +x /etc/init.d/iconnect
    /etc/init.d/iconnect enable 2>/dev/null || true
    echo "${GREEN}[✓]${NC} OpenWrt init.d 服务"
else
    cat > /etc/systemd/system/iconnectd.service << SVCEND
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
SVCEND
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable iconnectd 2>/dev/null || true
    echo "${GREEN}[✓]${NC} systemd 服务"
fi

# ============================================================
#  启动
# ============================================================
echo "${GREEN}[✓]${NC} 启动客户端..."
/usr/bin/iconnectd \
    --network-name "$NETWORK_NAME" --network-secret "$NETWORK_SECRET" \
    --disable-p2p --no-listener --dhcp \
    --disable-udp-hole-punching --disable-tcp-hole-punching --disable-upnp \
    --default-protocol tcp \
    --peers "tcp://${SERVER_ADDR}:${SERVER_PORT}" \
    > /tmp/iconnectd.log 2>&1 &
sleep 5

# ============================================================
#  验证
# ============================================================
TUN_IP=$(ip addr show tun0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)

echo ""
echo "${GREEN}${BOLD}  iConnect Client 安装完成!${NC}"
if pgrep iconnectd >/dev/null 2>&1; then
    echo "  状态:   ${GREEN}● 运行中${NC} (PID: $(pgrep iconnectd))"
else
    echo "  状态:   ${RED}○ 未运行${NC}, 日志: /tmp/iconnectd.log"
fi
[ -n "$TUN_IP" ] && echo "  虚拟IP: ${GREEN}${TUN_IP}${NC}" || echo "  虚拟IP: ${YELLOW}等待 DHCP...${NC}"
echo "  服务器: ${SERVER_ADDR}:${SERVER_PORT}"
echo ""
echo "  管理:"
if [ "$OS_TYPE" = "openwrt" ]; then
    echo "    /etc/init.d/iconnect start/stop/status"
else
    echo "    systemctl start/stop/status iconnectd"
    echo "    journalctl -u iconnectd -f"
fi
echo "    tail -f /tmp/iconnectd.log"
