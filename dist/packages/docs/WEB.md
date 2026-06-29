# iConnect Web 控制端使用手册

## 访问与账户

```
地址: http://服务器IP:1994
账户: admin
密码: admin888
```

**首次登录后请立即修改密码。** 注册功能已关闭。

忘记密码时，SSH 到服务器执行：

```bash
python3 /opt/iconnect/reset-pwd.py
```

## 架构

```
浏览器 ──HTTP──▶ Python 代理 (1994)
                 ├── /api/v1/summary  → 注入真实设备数量
                 ├── /api/v1/machines → 注入真实设备列表
                 ├── /api/*           → iconnect-web API (1996)
                 └── 其他             → iconnect-web 前端 (1995)
```

## 功能页面

| 页面 | 说明 |
|------|------|
| Dashboard | 显示设备总数（来自 CLI peer list） |
| Device List | 显示在线设备列表 |
| Device 详情 | 设备信息和网络配置 |

## 设备数据显示

Web 面板从 `iconnect-cli peer list` 实时获取设备数据并注入到 API 响应中。Dashboard 的设备数量和 Device List 的设备列表均反映真实的网络连接状态。

## 管理接口

| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/api/v1/auth/login` | 登录 |
| `POST` | `/api/v1/auth/register` | 注册（已关闭） |
| `PUT` | `/api/v1/auth/password` | 修改密码（需登录） |
| `GET` | `/api/v1/summary` | 设备总数 |
| `GET` | `/api/v1/machines` | 设备列表 |

## 服务管理

```bash
# 启动/停止
systemctl start/stop iconnect-web
systemctl start/stop iconnect-proxy

# 查看状态
systemctl status iconnect-web
systemctl status iconnect-proxy

# 日志
tail -f /var/log/iconnect-web.log
tail -f /var/log/iconnect-proxy.log
```

## 端口说明

| 端口 | 服务 | 用途 |
|------|------|------|
| 1994 | Python 代理 | 前端入口，注入设备数据 |
| 1995 | iconnect-web | 前端静态文件 |
| 1996 | iconnect-web | REST API |

## 数据库

```
路径: /var/lib/iconnect/iconnect.db
类型: SQLite
```

### 相关表

| 表 | 说明 |
|----|------|
| users | 用户账户和密码哈希（Argon2ID） |
| users_groups | 用户-权限组关联 |
| groups | 权限组（users / admins） |
| permissions | 权限定义（sessions / devices） |

### 手动管理用户

```bash
# 查看所有用户
sqlite3 /var/lib/iconnect/iconnect.db "SELECT id, username FROM users;"

# 重置密码为 admin888
python3 /opt/iconnect/reset-pwd.py

# 删除用户
sqlite3 /var/lib/iconnect/iconnect.db "DELETE FROM users WHERE username='xxx';"
```

## 部署结构

```
/opt/iconnect/
├── iconnectd              # Core 守护进程
├── iconnect-web           # Web 管理端（含内嵌前端）
├── iconnect-cli           # 命令行工具
├── proxy.py               # 1994 代理
└── reset-pwd.py           # 密码重置脚本

/etc/systemd/system/
├── iconnectd.service
├── iconnect-web.service
└── iconnect-proxy.service

/var/lib/iconnect/
└── iconnect.db            # SQLite 数据库
```
