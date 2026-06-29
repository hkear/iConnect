# GLIBC 兼容性异常记录

> 记录人：Kimi Code CLI  
> 记录时间：2026-06-29  
> 关联：README.md / deploy/build-all.sh / dist/packages/*

## 问题概述

项目 README 与安装脚本声明支持 **Ubuntu 20.04+ / Debian 11+**，但实际发布的 x86_64 二进制文件依赖 **GLIBC 2.39**，导致在 Ubuntu 20.04/22.04 等系统上无法直接运行。

## 实际检测结果

从 `dist/packages/` 的发布包中解压出的 ELF 二进制，解析出的最高 GLIBC 版本符号如下：

| 二进制文件 | 来源包 | 最高 GLIBC 依赖 |
|-----------|--------|----------------|
| `iconnectd` | `iconnect-server-v1.1.1.tar.gz` / `iconnect-client-v1.1.1-x86_64.tar.gz` | **2.39** |
| `iconnect-cli` | 同上 | **2.39** |
| `iconnect-web` | `iconnect-server-v1.1.1.tar.gz` | **2.34** |

完整扫描到的 GLIBC 版本符号（以 `iconnectd` 为例）：

```
2.2.5, 2.3, 2.3.2, 2.3.4, 2.4, 2.7, 2.9, 2.10, 2.12, 2.14,
2.15, 2.16, 2.17, 2.18, 2.25, 2.28, 2.29, 2.30, 2.32, 2.33,
2.34, 2.39
```

## 文档声明与实际的不一致

| 来源 | 声明内容 | 隐含 GLIBC |
|------|---------|-----------|
| `README.md` 服务端安装节 | "适用：Ubuntu 20.04+ / Debian 11+" | ≥ 2.31 |
| `deploy/install-server.sh` 注释 | "适用：Ubuntu 20.04+ / Debian 11+" | ≥ 2.31 |
| `deploy/install-client.sh` 注释 | "支持：OpenWrt / Debian / Ubuntu / CentOS" | 未明确版本 |
| `deploy/build-all.sh` 注释 | "在全新 Ubuntu 22.04/24.04 上运行" | 构建环境偏新 |

**实际发布包需要 GLIBC 2.39**，与 README 中 Ubuntu 20.04+ 的声明直接冲突。

## 根因分析

1. **动态链接 glibc**：项目使用默认的 `cargo build --release`，未启用 `x86_64-unknown-linux-musl` 静态编译，也未做 GLIBC 版本锁定。
2. **构建环境过新**：`build-all.sh` 在 Ubuntu 24.04（GLIBC 2.39）上执行后，链接器把高版本 GLIBC 符号带入最终二进制。
3. **无 CI/CD 锁定**：仓库中没有 `.github/workflows` 或 Dockerfile 来固定构建镜像版本。
4. **无 musl 配置**：`.cargo/config.toml`、构建脚本、CI 中均未配置 musl 目标。

## 可降级到的理论下限

- **按文档目标**：构建机切换到 **Ubuntu 20.04（GLIBC 2.31）**，预计可把二进制依赖降到 **2.31** 左右。
- **继续往下降**：需改用旧版 CentOS 7 / Ubuntu 18.04 构建，或全面迁移到 `x86_64-unknown-linux-musl` 静态链接。
- **最彻底方案**：musl 静态编译后几乎不依赖系统 GLIBC，可兼容绝大多数 Linux 发行版。

> 注意：Rust 工具链版本固定在 `1.95`，需确认该工具链在目标旧系统上可正常安装；同时依赖库（tokio、rustls、ring、openssl、jemalloc 等）可能引入额外限制，需要实测验证。

## 建议修复方案（优先级从高到低）

### 方案 A：固定构建环境到 Ubuntu 20.04（推荐）

- 修改 `deploy/build-all.sh`，要求/默认在 Ubuntu 20.04 容器或虚拟机中构建。
- 重新发布 `dist/packages/` 中的 x86_64 安装包。
- 优点：改动最小，与现有 README 声明一致。

### 方案 B：增加 musl 静态构建产物

- 在 `build-all.sh` 中加入 `rustup target add x86_64-unknown-linux-musl`。
- 使用 `cargo build --release --target x86_64-unknown-linux-musl` 生成静态二进制。
- 优点：兼容性最好，一份二进制可在多数 Linux 上运行。
- 注意：musl 下某些依赖（如 jemalloc、TUN 设备相关库）可能需要额外适配或关闭。

### 方案 C：同步文档与实际

- 如果暂时不想改构建流程，把 README 与安装脚本中的 "Ubuntu 20.04+" 改为 "Ubuntu 24.04+"。
- 这是临时措施，不建议长期使用。

## 修复记录

- **方案**: 全面迁移到 `x86_64-unknown-linux-musl` / `aarch64-unknown-linux-musl` 静态链接。
- **改动**:
  - 新增 `.cargo/config.toml`，配置 musl-gcc 链接器与 `-C target-feature=+crt-static`。
  - 新增 `deploy/Dockerfile.build`，固定 Ubuntu 22.04 + musl.cc 交叉工具链 + Rust 1.95 构建环境。
  - 重写 `deploy/build-all.sh`，默认产出 `x86_64` / `aarch64` 双架构 musl 静态二进制与安装包。
  - 更新 `README.md` 平台支持、包名与构建说明。
- **预期效果**: 发布包不再依赖系统 GLIBC，可在 Ubuntu 20.04/22.04/24.04、Debian 11/12、OpenWrt 等多数 Linux 发行版上直接运行。

## 后续待办

- [ ] 使用 `deploy/Dockerfile.build` 完整跑通构建，确认 x86_64 / aarch64 二进制均能成功产出。
- [ ] 用 `readelf -V` / `ldd` 验证二进制无 GLIBC 依赖，仅静态链接。
- [ ] 在 Ubuntu 20.04、Debian 11、OpenWrt aarch64 等目标环境实际运行安装包验证。
- [ ] 更新 `README_en.md` 中对应的平台支持说明。

## 快速复现检测命令

在 Linux 环境下：

```bash
tar xzf dist/packages/iconnect-client-v1.1.1-x86_64.tar.gz
readelf -V bin/iconnectd | grep GLIBC | sort -V | uniq | tail -5
```

或在 Windows/Git Bash 下用 Python 扫描：

```python
import re
from pathlib import Path
data = Path('bin/iconnectd').read_bytes()
print(max(re.findall(rb'GLIBC_([0-9.]+)', data), key=lambda x: tuple(map(int, x.split(b'.')))))
```
