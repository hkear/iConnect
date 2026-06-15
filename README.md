# iConnect — 异地内网组网系统

纯中心化转发的异地虚拟局域网组网工具。所有设备流量经由 Core 服务端中转，无需 P2P 打洞，适配多层 NAT / 弱网 / 端口封锁环境。

## 架构

```
Core Server (公网 IP, TCP 单端口)
   │
   ├── Client A (OpenWrt 路由器, 异地内网)
   ├── Client B (Linux 服务器, 异地内网)
   └── Client C (OpenWrt 路由器, 异地内网)

全部流量: Client A → Core → Client B, 禁止 Client 之间直连
```

## 快速开始

### 服务端（公网服务器）

```bash
# 方式一：一键安装
tar xzf iconnect-server-v1.0.0.tar.gz
sudo bash install.sh

# 方式二：直接运行
iconnectd \
  --network-name mynet --network-secret mykey \
  --ipv4 10.144.0.1 --dhcp \
  --listeners tcp://0.0.0.0:1993 \
  --default-protocol tcp \
  --disable-p2p --disable-udp-hole-punching --disable-upnp \
  --latency-first --multi-thread --relay-all-peer-rpc
```

### 客户端（OpenWrt / Linux）

```bash
# 一键安装
tar xzf iconnect-client-v1.0.0-*.tar.gz
sh install.sh

# 或直接运行
iconnectd \
  --network-name mynet --network-secret mykey \
  --disable-p2p --no-listener --dhcp \
  --default-protocol tcp \
  --peers tcp://服务器IP:1993
```

## Web 控制端

```
地址: http://服务器IP:1994
账户: admin
密码: admin888
```

- 首次登录后请立即修改密码
- 注册功能已关闭，仅允许管理员账户
- 如需重置密码，SSH 到服务器执行: `python3 /opt/iconnect/reset-pwd.py`

## 端口说明

| 端口 | 服务 | 说明 |
|------|------|------|
| 1993 | Core 组网 | 客户端连接端口 |
| 1994 | Web 前端 | 管理面板 |

## 目录结构

```
iconnect/
├── README.md
├── deploy/                  # 部署脚本与配置
│   ├── install-server.sh     # 服务端一键安装
│   ├── install-client.sh     # 客户端一键安装
│   ├── build-all.sh          # 源码构建脚本
│   ├── proxy.py              # Web 代理（注入设备数据）
│   ├── reset-pwd.py          # 密码重置脚本
│   └── iconnect.db           # 数据库模板
├── dist/packages/            # 编译好的安装包
├── iconnectd/                # Core 源码 (Rust)
└── iconnect-web/             # Web 管理端源码 (Rust + Vue)
```

## 核心特性

- **纯中心化转发**：100% 流量经 Core 中转，无 P2P
- **单端口**：仅需开放 1 个 TCP 端口（1993）
- **适配弱网**：无需 NAT 打洞，穿透多层路由
- **DHCP 自动分配 IP**：客户端连上即获虚拟 IP
- **跨平台**：Linux x86_64 / OpenWrt aarch64
- **Web 控制端**：Dashboard 设备数量、Device List 设备状态
- **设备数据注入**：Web 面板显示真实 CLI peer list 数据
- **轻量化**：适配 OpenWrt 低配置路由器

## 平台支持

| 平台 | 架构 | 状态 |
|------|------|------|
| Ubuntu / Debian | x86_64 | 服务端 + 客户端 |
| OpenWrt | aarch64 | 客户端 |
| 其他 Linux | x86_64 | 客户端 |

## 管理命令

```bash
# 服务管理
systemctl start/stop/status iconnectd
systemctl start/stop/status iconnect-web

# 查看日志
journalctl -u iconnectd -f
tail -f /var/log/iconnectd.log

# 重置密码
python3 /opt/iconnect/reset-pwd.py

# 设备状态
iconnect-cli peer list
iconnect-cli route list
```

## 文档

- [CLI 命令行手册](dist/packages/docs/CLI.md)
- [Web 控制端手册](dist/packages/docs/WEB.md)

## 许可证

基于 EasyTier v2.6.4 二次开发，继承原项目 MPL-2.0 许可证。
