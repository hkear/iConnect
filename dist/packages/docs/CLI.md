# iConnect CLI 命令行使用手册

## 概述

| 命令 | 说明 |
|------|------|
| `iconnectd` | 核心守护进程，服务端/客户端通用 |
| `iconnect-cli` | 管理 CLI，查看状态、节点、路由 |

---

## 一、服务端模式

```bash
iconnectd \
  --network-name mynet \
  --network-secret my-secret-key \
  --ipv4 10.144.0.1 \
  --dhcp \
  --listeners tcp://0.0.0.0:1993 \
  --default-protocol tcp \
  --disable-p2p \
  --disable-udp-hole-punching \
  --disable-tcp-hole-punching \
  --disable-sym-hole-punching \
  --disable-upnp \
  --latency-first \
  --multi-thread \
  --relay-all-peer-rpc
```

## 二、客户端模式

```bash
iconnectd \
  --network-name mynet \
  --network-secret my-secret-key \
  --disable-p2p \
  --disable-udp-hole-punching \
  --disable-tcp-hole-punching \
  --disable-upnp \
  --no-listener \
  --dhcp \
  --default-protocol tcp \
  --peers tcp://服务器IP:1993
```

## 三、完整参数列表

### 网络配置

| 参数 | 环境变量 | 说明 | 默认值 |
|------|----------|------|--------|
| `--network-name` | `ET_NETWORK_NAME` | 组网名称 | `default` |
| `--network-secret` | `ET_NETWORK_SECRET` | 组网密钥 | 无 |
| `--ipv4` | `ET_IPV4` | 指定虚拟 IPv4 | DHCP 自动 |
| `--dhcp` | `ET_DHCP` | 启用 DHCP 自动分配 IP | `false` |
| `--peers` / `-p` | `ET_PEERS` | 对端节点 URL，逗号分隔 | 无 |
| `--listeners` | `ET_LISTENERS` | 本地监听地址 | `tcp://0.0.0.0:11010` |
| `--no-listener` | `ET_NO_LISTENER` | 不监听任何端口（纯客户端） | `false` |

### 连接与协议

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--default-protocol` | 协议 (tcp/udp/ws/wss) | `tcp` |
| `--disable-p2p` | 禁用 P2P，全部走 Core 中转 | `false` |
| `--disable-ipv6` | 禁用 IPv6 | `false` |
| `--mtu` | TUN 设备 MTU | `1360` |

### 中心化模式必禁用

| 参数 | 说明 |
|------|------|
| `--disable-udp-hole-punching` | 禁用 UDP 打洞 |
| `--disable-tcp-hole-punching` | 禁用 TCP 打洞 |
| `--disable-sym-hole-punching` | 禁用对称 NAT 打洞 |
| `--disable-upnp` | 禁用 UPnP 端口映射 |

### 性能与优化

| 参数 | 说明 | 默认 |
|------|------|------|
| `--latency-first` | 延迟优先路由 | `true` |
| `--multi-thread` | 多线程（服务端推荐开启） | `false` |
| `--enable-kcp-proxy` | KCP 传输优化 | `true` |
| `--enable-quic-proxy` | QUIC 传输优化 | `true` |

### 运行模式

| 参数 | 说明 |
|------|------|
| `-d` / `--daemon` | 后台守护进程 |
| `-c` / `--config-file` | 指定 TOML 配置文件 |
| `--no-tun` | 不创建 TUN 虚拟网卡 |
| `--rpc-portal` | RPC 管理接口地址 |

## 四、iconnect-cli 管理命令

```bash
iconnect-cli node info        # 本节点信息
iconnect-cli peer list        # 对等节点列表
iconnect-cli route list       # 路由表
iconnect-cli route dump       # 导出路由表（JSON）
```

## 五、使用场景

### 公网服务器 + 异地 OpenWrt 组网

**服务器 (1.2.3.4):**
```bash
iconnectd --network-name office --network-secret MySecret123 \
  --ipv4 10.144.0.1 --dhcp --listeners tcp://0.0.0.0:1993 \
  --disable-p2p --disable-udp-hole-punching --disable-upnp \
  --default-protocol tcp --multi-thread
```

**OpenWrt 路由器:**
```bash
iconnectd --network-name office --network-secret MySecret123 \
  --disable-p2p --no-listener --dhcp \
  --default-protocol tcp --peers tcp://1.2.3.4:1993
```

### 多设备全互联

```
           Core Server (10.144.0.1)
          /         |         \
   Client A     Client B     Client C
  (10.144.0.2) (10.144.0.3) (10.144.0.4)

全部流量经 Core 转发，无需 P2P
```

## 六、故障排查

| 问题 | 解决方法 |
|------|----------|
| 连接超时 | 检查防火墙，确认服务器 IP 可达 |
| TUN 创建失败 | 需 root 权限，确认 `/dev/net/tun` 存在 |
| IP 不互通 | 检查两端 `network-name` 和 `network-secret` 一致 |
| DHCP 无 IP | 客户端加 `--dhcp`，服务端加 `--dhcp` |
| 日志 | `journalctl -u iconnectd -f` 或 `RUST_LOG=debug iconnectd ...` |
