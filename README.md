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

## 安装指南

### 一、服务端 + Web 管理端（x86_64）

<<<<<<< HEAD
**适用**: Ubuntu 20.04+ / Debian 11+，有公网 IP 的服务器
=======
**适用**: 绝大多数 Linux x86_64 发行版（二进制使用 musl 静态链接，不依赖系统 GLIBC）
>>>>>>> master

**防火墙要求**: 开放 TCP 1993（组网）、1994（Web）

```bash
# 1. 下载服务端安装包并解压
<<<<<<< HEAD
tar xzf iconnect-server-v1.1.1.tar.gz
=======
tar xzf iconnect-server-v1.1.1-x86_64.tar.gz
>>>>>>> master

# 2. 交互式安装（可自定义组网名称、密钥、端口）
sudo bash install.sh

# 3. 安装完成后自动启动，输出连接信息
```

**安装后服务**:

| 服务 | 端口 | systemd |
|------|------|---------|
| iconnectd (Core) | 1993 | `systemctl start/stop iconnectd` |
| iconnect-web | 1996 (内部) | `systemctl start/stop iconnect-web` |
| iconnect-proxy | 1994 (前端) | `systemctl start/stop iconnect-proxy` |

**Web 管理端**:

```
地址: http://服务器IP:1994
账户: admin
密码: admin888
```

首次登录后请修改密码。注册已关闭。忘记密码执行 `python3 /opt/iconnect/reset-pwd.py`。

**手动部署 Web**（如果 install.sh 未包含）:

```bash
# 上传 proxy.py 和 reset-pwd.py 到 /opt/iconnect/
# 安装 Python 依赖
pip3 install argon2-cffi --break-system-packages

# 创建 systemd 服务
cat > /etc/systemd/system/iconnect-proxy.service << 'EOF'
[Unit]
Description=iConnect Web Proxy
After=network.target iconnect-web.service
[Service]
Type=simple
ExecStart=python3 /opt/iconnect/proxy.py 1994
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now iconnect-proxy
```

### 二、客户端 x86_64（Linux 服务器 / 虚拟机）

```bash
# 1. 下载客户端安装包并解压
tar xzf iconnect-client-v1.1.1-x86_64.tar.gz

# 2. 命令行模式安装（非交互）
sudo bash install.sh 服务器IP 1993 组网名称 组网密钥

# 或交互模式
sudo bash install.sh
```

安装后 `systemctl start/stop iconnectd` 管理客户端。虚拟 IP 由 DHCP 自动分配。

<<<<<<< HEAD
### 三、客户端 aarch64（OpenWrt 路由器）

```bash
# 1. 下载客户端安装包并解压（在 OpenWrt 上执行）
=======
### 三、客户端 aarch64（OpenWrt / ARM64 Linux）

```bash
# 1. 下载客户端安装包并解压（在 OpenWrt / ARM64 Linux 上执行）
>>>>>>> master
tar xzf iconnect-client-v1.1.1-aarch64.tar.gz

# 2. 命令行模式安装
sh install.sh 服务器IP 1993 组网名称 组网密钥

# 或交互模式
sh install.sh
```

安装后 `/etc/init.d/iconnect start/stop` 管理客户端。

### 四、防火墙配置

| 端口 | 协议 | 方向 | 说明 |
|------|------|------|------|
| 1993 | TCP | 入站 | Core 组网，客户端连接 |
| 1994 | TCP | 入站 | Web 管理面板 |

```bash
# UFW
sudo ufw allow 1993/tcp
sudo ufw allow 1994/tcp

# firewalld
sudo firewall-cmd --add-port=1993/tcp --permanent
sudo firewall-cmd --add-port=1994/tcp --permanent
sudo firewall-cmd --reload
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
<<<<<<< HEAD
├── deploy/                  # 部署脚本与配置
│   ├── install-server.sh     # 服务端一键安装
│   ├── install-client.sh     # 客户端一键安装
│   ├── build-all.sh          # 源码构建脚本
=======
├── .cargo/
│   └── config.toml           # musl 静态链接器配置
├── deploy/                   # 部署脚本与配置
│   ├── install-server.sh     # 服务端一键安装
│   ├── install-client.sh     # 客户端一键安装
│   ├── build-all.sh          # 源码构建脚本（musl 静态）
│   ├── Dockerfile.build      # 固定构建环境镜像
>>>>>>> master
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
<<<<<<< HEAD
- **跨平台**：Linux x86_64 / OpenWrt aarch64
=======
- **跨平台**：Linux x86_64 / OpenWrt aarch64，均使用 musl 静态链接
>>>>>>> master
- **Web 控制端**：Dashboard 设备数量、Device List 设备状态
- **设备数据注入**：Web 面板显示真实 CLI peer list 数据
- **轻量化**：适配 OpenWrt 低配置路由器

## 平台支持

| 平台 | 架构 | 状态 |
|------|------|------|
<<<<<<< HEAD
| Ubuntu / Debian | x86_64 | 服务端 + 客户端 |
| OpenWrt | aarch64 | 客户端 |
| 其他 Linux | x86_64 | 客户端 |
=======
| Linux x86_64（musl 静态链接） | x86_64 | 服务端 + 客户端 |
| Linux ARM64 / OpenWrt（musl 静态链接） | aarch64 | 客户端 |
| 其他 Linux x86_64 | x86_64 | 客户端 |
>>>>>>> master

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
