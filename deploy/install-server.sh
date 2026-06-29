#!/bin/bash
# ============================================================
#  iConnect Server 一键安装脚本
#  适用: Ubuntu 20.04+ / Debian 11+
#  用法: sudo bash install.sh
#  解压后直接运行，文件结构与脚本路径匹配
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║       iConnect Server 安装向导           ║"
echo "  ║       v1.0.0 - 异地组网中心节点           ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

[ "$(id -u)" -ne 0 ] && { echo -e "${RED}[错误] 请使用 root 或 sudo 运行${NC}"; exit 1; }

# === 检测系统 ===
if [ -f /etc/os-release ]; then . /etc/os-release; OS=$ID; else OS="unknown"; fi
echo -e "${GREEN}[✓]${NC} 系统: ${BOLD}${OS}${NC}"

# === 第一步：组网配置 ===
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  第一步：组网配置${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

read -p "  组网名称 [iconnect]: " NETWORK_NAME; NETWORK_NAME=${NETWORK_NAME:-iconnect}
read -p "  组网密钥 (留空自动生成32位): " NETWORK_SECRET
if [ -z "$NETWORK_SECRET" ]; then
    NETWORK_SECRET=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
    echo -e "  ${GREEN}[✓]${NC} 已生成密钥: ${BOLD}${NETWORK_SECRET}${NC}"
fi
read -p "  虚拟网络地址 [10.144.0.0/24]: " VIRTUAL_NET; VIRTUAL_NET=${VIRTUAL_NET:-10.144.0.0/24}
SERVER_IP="${VIRTUAL_NET%.*}.1"
read -p "  组网端口 [1993]: " LISTEN_PORT; LISTEN_PORT=${LISTEN_PORT:-1993}

# === 第二步：安装确认 ===
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  第二步：安装确认${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
INSTALL_DIR="/opt/iconnect"
CONFIG_DIR="/etc/iconnect"
echo -e "  安装目录: ${BOLD}${INSTALL_DIR}${NC}"
echo -e "  配置目录: ${BOLD}${CONFIG_DIR}${NC}"
read -p "  确认安装? [Y/n]: " CONFIRM
[ "$CONFIRM" = "n" ] || [ "$CONFIRM" = "N" ] && { echo "已取消"; exit 0; }

# === 安装二进制 ===
echo -e "\n${GREEN}[1/5]${NC} 安装二进制文件..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"

for bin in iconnectd iconnect-web iconnect-cli; do
    if [ -f "$SCRIPT_DIR/bin/$bin" ]; then
        cp "$SCRIPT_DIR/bin/$bin" "$INSTALL_DIR/$bin"
        chmod +x "$INSTALL_DIR/$bin"
        ln -sf "$INSTALL_DIR/$bin" "/usr/local/bin/$bin" 2>/dev/null || true
        echo -e "       ${GREEN}✓${NC} $bin"
    fi
done

# === 生成 systemd 服务（直接用 CLI 参数） ===
echo -e "${GREEN}[2/5]${NC} 创建 systemd 服务..."

cat > /etc/systemd/system/iconnectd.service << SERVICE_EOF
[Unit]
Description=iConnect Core Service
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/iconnectd \\
  --network-name ${NETWORK_NAME} \\
  --network-secret ${NETWORK_SECRET} \\
  --ipv4 ${SERVER_IP} \\
  --dhcp \\
  --listeners tcp://0.0.0.0:${LISTEN_PORT} \\
  --default-protocol tcp \\
  --disable-p2p \\
  --disable-udp-hole-punching \\
  --disable-tcp-hole-punching \\
  --disable-sym-hole-punching \\
  --disable-upnp \\
  --latency-first \\
  --multi-thread \\
  --relay-all-peer-rpc
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE_EOF

if [ -f "$INSTALL_DIR/iconnect-web" ]; then
    cat > /etc/systemd/system/iconnect-web.service << 'WEBSVC_EOF'
[Unit]
Description=iConnect Web Management
After=network.target iconnectd.service

[Service]
Type=simple
ExecStart=/opt/iconnect/iconnect-web --db /var/lib/iconnect/iconnect.db --api-server-port 11211 --web-server-port 1994
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
WEBSVC_EOF
fi

systemctl daemon-reload
systemctl enable iconnectd 2>/dev/null || true
[ -f "$INSTALL_DIR/iconnect-web" ] && systemctl enable iconnect-web 2>/dev/null || true
echo -e "       ${GREEN}✓${NC} 服务已创建"

# === 防火墙 ===
echo -e "${GREEN}[3/5]${NC} 配置防火墙..."
for port in $LISTEN_PORT 1994; do
    if command -v ufw &>/dev/null; then ufw allow ${port}/tcp 2>/dev/null || true; fi
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --add-port=${port}/tcp --permanent 2>/dev/null || true
    fi
done
command -v firewall-cmd &>/dev/null && firewall-cmd --reload 2>/dev/null || true
echo -e "       ${GREEN}✓${NC} 端口已放行"

# === 启动 ===
echo -e "${GREEN}[4/5]${NC} 启动服务..."
systemctl restart iconnectd 2>/dev/null || {
    nohup "$INSTALL_DIR/iconnectd" \
        --network-name "$NETWORK_NAME" --network-secret "$NETWORK_SECRET" \
        --ipv4 "$SERVER_IP" --dhcp --listeners "tcp://0.0.0.0:${LISTEN_PORT}" \
        --default-protocol tcp --disable-p2p --disable-udp-hole-punching \
        --disable-tcp-hole-punching --disable-sym-hole-punching --disable-upnp \
        --latency-first --multi-thread --relay-all-peer-rpc \
        > /var/log/iconnectd.log 2>&1 &
}
sleep 4

# === 验证并输出 ===
echo -e "${GREEN}[5/5]${NC} 验证安装..."

PUBLIC_IP=$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || curl -s --connect-timeout 3 icanhazip.com 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(ip addr show 2>/dev/null | grep 'inet ' | grep -v 127.0.0.1 | head -1 | awk '{print $2}' | cut -d/ -f1)

echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║     iConnect Server 安装完成!            ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${BOLD}服务状态:${NC}"
pgrep -x iconnectd >/dev/null 2>&1 && echo -e "    Core:  ${GREEN}● 运行中${NC} (PID: $(pgrep -x iconnectd))" || echo -e "    Core:  ${RED}○ 未运行${NC}"
echo ""
echo -e "  ${BOLD}连接信息:${NC}"
echo "    组网名称: ${NETWORK_NAME}"
echo "    组网密钥: ${NETWORK_SECRET}"
echo "    虚拟网段: ${VIRTUAL_NET}"
echo "    服务端 IP: ${SERVER_IP}"
echo "    公网地址: ${PUBLIC_IP}:${LISTEN_PORT}"
echo ""
echo -e "  ${BOLD}客户端连接命令:${NC}"
echo -e "    ${CYAN}iconnectd \\"
echo "      --network-name ${NETWORK_NAME} \\"
echo "      --network-secret ${NETWORK_SECRET} \\"
echo "      --disable-p2p --no-listener --dhcp \\"
echo "      --default-protocol tcp \\"
echo -e "      --peers tcp://${PUBLIC_IP}:${LISTEN_PORT}${NC}"
echo ""
echo -e "  ${BOLD}管理命令:${NC}"
echo "    systemctl start/stop/status iconnectd"
echo "    journalctl -u iconnectd -f"
echo ""
echo -e "  ${YELLOW}提示: 请确保防火墙已开放端口 ${LISTEN_PORT}(组网)${NC}"
