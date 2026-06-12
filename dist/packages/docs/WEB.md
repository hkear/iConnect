# iConnect Web 控制端使用手册

## 概述

Web 控制端提供可视化的设备管理、网络配置和状态监控。基于 Vue 3 + PrimeVue，支持桌面和移动端。

```
浏览器 ──HTTP──▶ iconnect-web ──RPC──▶ iconnectd (Core)
                 ├── RESTful API
                 ├── 用户认证
                 ├── SQLite 持久化
                 └── 内嵌 Vue SPA 前端
```

## 一、启动

```bash
/opt/iconnect/iconnect-web \
  --db /var/lib/iconnect/iconnect.db \
  --api-server-port 11211 \
  --web-server-port 1994
```

### 参数

| 参数 | 环境变量 | 说明 | 默认值 |
|------|----------|------|--------|
| `-d` / `--db` | `IC_WEB_DB` | SQLite 数据库路径 | `et.db` |
| `-a` / `--api-server-port` | `IC_API_SERVER_PORT` | REST API 端口 | `11211` |
| `-l` / `--web-server-port` | `IC_WEB_SERVER_PORT` | Web 前端端口 | 无 |
| `-c` / `--config-server-port` | `IC_CONFIG_SERVER_PORT` | 设备配置下发端口 | `22020` |

## 二、访问与登录

浏览器打开 `http://<服务器IP>:1994`，首次使用先注册管理员账户。

## 三、功能页面

| 页面 | 路径 | 功能 |
|------|------|------|
| 仪表盘 | `/dashboard` | 设备总数、在线状态概览 |
| 设备列表 | `/deviceList` | 卡片式设备展示，排序/搜索/详情 |
| 设备管理 | `/deviceList/device/:id` | 远程配置、网络实例管理 |
| 配置生成器 | `/config_generator` | Web 表单生成 TOML 配置 |
| 网络拓扑 | (NetworkChart) | 节点连接关系可视化 |
| ACL 管理 | (AclManager) | 访问控制规则编辑 |

## 四、设备审批

iConnect 特有的设备接入审批流程：

1. 新设备发起连接 → 自动注册为**待审批**
2. 管理员在设备列表看到待审批卡片
3. 点击**批准**可分配 IP 和别名
4. 点击**拒绝**禁止接入

### API 接口

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/api/v1/devices` | 列出所有设备及状态 |
| `GET` | `/api/v1/devices/pending` | 列出待审批设备 |
| `POST` | `/api/v1/devices/:id/approve` | 审批，Body: `{"assigned_ip":"10.144.0.x","alias":"别名"}` |
| `POST` | `/api/v1/devices/:id/reject` | 拒绝 |
| `POST` | `/api/v1/devices/:id/kick` | 强制下线 |

## 五、其他 REST API

### 认证

| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/api/v1/auth/login` | 登录 |
| `POST` | `/api/v1/auth/register` | 注册 |
| `GET` | `/api/v1/auth/logout` | 登出 |

### 设备与配置管理

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/api/v1/machines` | 设备列表 |
| `POST` | `/api/v1/machines/:id/networks` | 部署网络配置到设备 |
| `GET` | `/api/v1/machines/:id/networks/info` | 设备网络运行信息 |
| `POST` | `/api/v1/generate-config` | 生成 TOML 配置 |
| `POST` | `/api/v1/parse-config` | 解析 TOML 配置 |

## 六、nginx 反代示例

```nginx
server {
    listen 443 ssl;
    server_name iconnect.example.com;

    ssl_certificate /etc/ssl/iconnect.crt;
    ssl_certificate_key /etc/ssl/iconnect.key;

    location / {
        proxy_pass http://127.0.0.1:1994;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## 七、安全建议

1. 生产环境通过 nginx 反代配置 HTTPS
2. 修改默认 Web 端口（1994）
3. 防火墙仅允许可信 IP 访问 Web 端口
4. 定期更新 `network_secret` 并重新分发
