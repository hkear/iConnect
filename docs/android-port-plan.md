# iConnect 安卓端改造:可行性方案与工作量报告

日期:2026-08-06
范围:基于当前仓库(main 分支,iconnectd v1.1.2 / 上游 EasyTier v2.6.4)评估将 iConnect 客户端移植到 Android 的可行性。

---

## 一、可行性结论:高度可行(内核已就绪,缺应用壳)

iConnect 内核(`iconnectd/src`,即 EasyTier v2.6.4 定制版)**已内建完整的 Android 支持路径**(`cfg(mobile)` 分支),Android 端无需修改转发内核,只需:

1. 用 NDK 交叉编译内核为 Android 目标;
2. 写一个 Android 原生壳(VpnService + 前台服务)获取 tun fd 并注入内核;
3. 提供配置界面(原生设置页或 WebView 内嵌 `iconnect-web` 前端)。

官方 EasyTier 已用同一条路径发布了 Android GUI(Tauri + `tauri-plugin-vpnservice`),生态验证过该方案可行。

---

## 二、代码现状(证据)

### 2.1 内核已内建 mobile/Android 分支

| 位置 | 内容 |
|------|------|
| `iconnectd/build/main.rs:137-146` | `cfg_aliases! mobile = android \| ios \| (macos+macos-ne) \| ohos` |
| `iconnectd/src/instance/virtual_nic.rs:582-620` | `create_dev_for_mobile(tun_fd: RawFd)`:用 `config.raw_fd(tun_fd)` + `close_fd_on_drop(false)` 包装**外部传入**的 tun fd,不自己创建 `/dev/net/tun` |
| `iconnectd/src/instance/virtual_nic.rs:1401-1425` | `run_for_mobile(tun_fd)`:`#[cfg(mobile)]`,跑转发主循环,**不调用** `assign_ipv4/ipv6_to_tun_device`(IP/路由由原生侧 VPNService 配置) |
| `iconnectd/src/instance/instance.rs:1566-1598` | `setup_nic_ctx_for_mobile(...)`:fd<=0 时安全跳过,重建 NicCtx |
| `iconnectd/src/launcher.rs:114-141` | `run_routine_for_mobile`:从 mpsc channel 收 tun fd 并喂给 `setup_nic_ctx_for_mobile` |
| `iconnectd/src/instance_manager.rs:305` | `set_tun_fd(instance_id, fd)`:**预留的 fd 注入入口**(当前仓库无调用方,供 GUI/FFI 层使用) |
| `iconnectd/src/common/ifcfg/mod.rs:159-165` | Android 不属于 linux/macos/windows/freebsd → `IfConfiger = DummyIfConfiger`(空实现):内核不碰 IP/路由配置 |
| `iconnectd/src/common/machine_id.rs:117-118` | Android 无 HOME,机器 ID 目录需显式指定 |
| `iconnectd/src/instance/instance.rs:120-130` | Android/iOS/ohOS 不支持 ICMP proxy,失败不致命 |

### 2.2 依赖对 Android 的适配情况

| 依赖 | Android 下行为 |
|------|----------------|
| `tun-easytier`(rust-tun fork,`Cargo.toml:105-107`) | 支持 `raw_fd` 包装,官方 Android 在用 |
| `nix` / `netlink-*` / `dbus` / `machine-uid` / `service-manager` | 均为 `cfg(target_os = "linux")` 等平台限定,Android(target_os="android")**不会编译** —— 无冲突 |
| `kcp-sys`(bindgen C) | 需 NDK clang + 头文件路径(build 脚本已支持 musl 交叉,可类比) |
| `openssl`(vendored,可选 feature) | 可用;默认 feature 不启用 |
| `smoltcp` / `quinn` / `rustls` | 纯 Rust,跨平台无问题 |

### 2.3 现有构建体系

- `deploy/build-all.sh` 只产 musl 静态二进制(x86_64/aarch64-linux-musl),**不含 Android target**;
- 无 JNI/ndk crate 依赖,内核不直接碰 JNI —— Android 壳需要自建 FFI 或复用官方 `tauri-plugin-vpnservice` 的 fd 传递通道。

### 2.4 目录关系

实际编译的源码是 `iconnectd/src`(workspace members 只有 `iconnectd`、`iconnect-web`);`iconnectd/easytier/` 是上游 v2.6.4 的保留拷贝,不参与构建。Android 改造只动 `iconnectd/src` + 新增应用壳。

---

## 三、改造方案

### 方案 A(推荐):原生 Kotlin 壳 + cdylib/JNI 注入 fd

```
Android App (Kotlin)
├── VpnService 子类            # VpnService.Builder 建 tun、配地址/路由/DNS/MTU,拿 fd
├── Foreground Service          # 常驻通知,绑定内核生命周期(连接/断开/网络切换)
├── 配置界面                     # 原生设置页(服务器IP/端口/组网名/密钥)或 WebView 内嵌 iconnect-web
└── iconnectd.so (aarch64-linux-android 等)   # 编译为 cdylib,暴露 start/stop/set_tun_fd
```

内核接入:
1. 将 `iconnectd` 编译为 `cdylib`(需新增 `#[no_mangle]` FFI 薄层,包住 `InstanceManager::set_tun_fd` + 配置加载);
2. JNI 调用把 `VpnService` 的 fd 整数传入 Rust;
3. 内核在 `run_for_mobile` 路径下跑,IP/路由/DNS 由 `VpnService.Builder` 配置,与官方 Android GUI 一致。

### 方案 B:复用官方 Tauri 插件(快速验证)

参考上游 `tauri-plugin-vpnservice`(android/ + ios/ 原生 + guest-js),用 Tauri 壳 + WebView UI。优点:官方已踩坑 fd 桥接;缺点:引入 Tauri 技术栈,包体大,不如原生壳贴合 iConnect 现有 Vue 前端。

### 方案 C:可执行文件 + Termux(不推荐)

直接在 Termux 里跑 `iconnectd` 二进制,无法用 VPNService 非 root 接管流量,体验差,仅作调试用。

### 构建管线

- `cargo-ndk` 或手工 NDK(r26+)交叉编译:`aarch64-linux-android` / `armv7-linux-androideabi` / `x86_64-linux-android` / `i686-linux-android`;
- 上游官方有 `android.nix`(NDK 26.1.10909125)可参考;
- Android 上用配置文件方式传参(免命令行),复用现有 `TomlConfigLoader`。

---

## 四、工作量评估(单人,熟悉 Rust + Android 前提)

| 阶段 | 内容 | 工作量 |
|------|------|--------|
| 1. 构建打通 | NDK 交叉编译 iconnectd → .so(处理 kcp-sys/openssl 头文件、cdylib 改造、最小 JNI 冒烟) | 2-3 人日 |
| 2. 应用壳 | VpnService + 前台服务 + fd 注入 + 生命周期/断线重连/网络切换 | 3-5 人日 |
| 3. 配置与 UI | 设置页(或 WebView 内嵌 iconnect-web)、保存多组配置、连接状态展示 | 3-5 人日 |
| 4. 联调测试 | 真机(含低版本 Android)+ OpenWrt/服务端组网联调、后台限制/电池优化适配、打包发布 | 3-5 人日 |
| **合计** | | **约 2-4 周** |

### 主要风险与对策

1. **kcp-sys 等 C 依赖交叉编译**:用 NDK clang,参考现有 musl 的 `BINDGEN_EXTRA_CLANG_ARGS` 处理;
2. **后台被杀**:必须前台服务 + 通知;Android 12+ 前台服务启动限制需处理;
3. **fd 生命周期**:VPNService 重建时 fd 会变,内核 `setup_nic_ctx_for_mobile` 已支持重复注入(循环收 channel),壳侧负责在 onRevoke 时重建;
4. **未验证项**:本仓库从未真正以 android target 编译过(无 CI 产物),需在阶段 1 实测;官方 android.nix 在**上游**仓库,本仓库若已删则需从上游取。

---

## 五、结论

- **可行性:高**。内核转发、加密、路由、DHCP 全部复用现有 mobile 分支,零内核改造。
- **主工作量在 Android 应用壳**(VpnService + 生命周期 + UI),约 2-4 周。
- 建议先做阶段 1 验证 `aarch64-linux-android` 编译通过,再决定 A/B 方案。

---

## 六、阶段 1 进展(2026-08-06 已完成)

### 结果:✅ 编译与链接全部打通

```
target/aarch64-linux-android/debug/iconnectd
ELF 64-bit LSB pie executable, ARM aarch64, dynamically linked, for Android 24, built by NDK r26d
```

cargo check 与 cargo build 均通过(完整默认 features 减去 kcp),仅 4 个无害警告(unused import/variable,mobile 分支遗留)。

### 环境搭建记录(Windows)

| 组件 | 版本/路径 | 说明 |
|------|-----------|------|
| rustup + Rust | 1.95.0(项目 rust-toolchain.toml 指定) | 安装于 `C:\Users\Kay\.cargo` |
| Android targets | aarch64 / armv7 / i686 / x86_64-linux-android | `rustup target add` |
| NDK | r26d → `%LOCALAPPDATA%\Android\Sdk\android-ndk-r26d` | 与上游 android.nix(NDK 26.x)对齐 |
| protoc | 25.3 → `%LOCALAPPDATA%\Android\tools\bin` | prost-build 必需,`PROTOC` 环境变量 |
| 复用脚本 | `deploy/build-android.sh` | check / debug / release 三种模式 |

### 踩坑记录(重要)

1. **NDK `.cmd` 包装器破坏链接参数**:rustc 调用 `aarch64-linux-android21-clang.cmd` 时,cmd 的 `%*` 二次解析导致 `--version-script` 等参数报"此时不应有"错误。
   **解决**:`.cargo/config.toml` 新增 `[target.aarch64-linux-android]`,linker 直接用原生 `clang.exe` + `-C link-arg` 传 `-target aarch64-linux-android24` 与 `--sysroot`。
2. **API level 21 缺符号**:`getifaddrs/freeifaddrs` 是 Android API 24+ 才有,链接报 undefined symbol。
   **解决**:minSdk 定为 **24(Android 7.0)**,`--target=aarch64-linux-android24`。
3. **prost 找不到 protoc**:PATH 不够,需显式 `PROTOC` 环境变量。
4. **feature 裁剪陷阱**:`--no-default-features --features tun,socks5` 时 `use_new_nic_ctx` 因 magic-dns 未启用签名不一致报 E0061 —— 不是 Android 问题,启用完整 features 即消失。

### 遗留问题

- **kcp feature 未启用**:`kcp-sys`(bindgen C 库)需要 libclang.dll,本机无。Android 主链路走 TCP(默认协议),KCP 传输优化可后补(下载 LLVM libclang 或跳过)。
- debug 二进制 488MB 未 strip;release 构建未跑(预计 20-40 分钟)。
- 二进制未在真机/模拟器实测运行(VPNService 壳尚未实现,阶段 2)。

---

## 七、阶段 2 进展:JNI 集成层(2026-08-06 已完成技术核心)

### 结果:✅ 内核 cdylib + JNI 导出,真机验证通过

**改动**:
1. `iconnectd/Cargo.toml`:`[lib] crate-type = ["cdylib", "rlib"]`;新增 `[target.'cfg(target_os = "android")'.dependencies] jni = "0.21"(default-features = false)`
2. `iconnectd/src/android.rs`(**新文件**):JNI 入口层,Java 类 `com.iconnect.android.NativeCore`
3. `iconnectd/src/lib.rs`:`#[cfg(target_os = "android")] pub mod android;`

**JNI 接口**(4 个):
| 函数 | Java 签名 | 说明 |
|------|-----------|------|
| `Java_com_iconnect_android_NativeCore_start` | `static native void start(String configPath)` | 独立线程 + tokio runtime,`load_config_from_file` → `run_network_instance` → `manager.wait()` 保持存活 |
| `Java_com_iconnect_android_NativeCore_setTunFd` | `static native void setTunFd(int fd)` | 复用 `InstanceManager::set_tun_fd` 注入 VpnService fd |
| `Java_com_iconnect_android_NativeCore_stop` | `static native void stop()` | `delete_network_instance` 停止 |
| `Java_com_iconnect_android_NativeCore_isRunning` | `static native boolean isRunning()` | 状态查询 |

**编译产出**(验证通过):
```
target/aarch64-linux-android/debug/libiconnectd.so  (ELF shared object, Android 24)
llvm-nm -D: 4 个 Java_com_iconnect_android_NativeCore_* 符号全部导出
```

**真机验证**(adb,设备 56251FDCR002JF):
- `iconnectd --version` → `iconnectd 1.1.2` 正常输出
- `iconnectd --network-name smoketest --no-tun --no-listener --peers tcp://127.0.0.1:1` → 配置解析、实例创建(instance id)、peer 连接尝试、日志系统全部正常

**关键机制确认**(无需改内核):
- `launcher.rs:173-176`:`#[cfg(mobile)] run_routine_for_mobile` 在 android target 下自动启用,实例启动后即等待 tun fd
- `instance_manager.rs:110-128 run_network_instance` 返回 `instance_id`,直接用于 `set_tun_fd`

**踩坑**:Rust 1.95 要求 `#[unsafe(no_mangle)]`(不再是 `#[no_mangle]`)。

### 剩余(下一轮)

- **Android 工程骨架**:需装 JDK 17 + Gradle + SDK build-tools/platforms(本机均缺失,大下载)
- VpnService 子类 + 前台服务 + fd 传递
- 配置 UI(设置页/TOML 生成)
- APK 构建 + 真机联调(含服务端/OpenWrt 组网)

---

## 八、阶段 2 完成:Android 应用壳 + APK(2026-08-06)

### 结果:✅ APK 构建成功,真机安装启动验证通过

**新增 `android/` 工程**(纯 Android framework + Kotlin,零第三方依赖):

| 文件 | 内容 |
|------|------|
| `android/app/src/main/java/com/iconnect/android/NativeCore.kt` | JNI 绑定(loadLibrary("iconnectd")) |
| `.../ConfigHelper.kt` | AppConfig + SharedPreferences + TOML 生成(字段对齐 config.rs) |
| `.../IConnectVpnService.kt` | VpnService 子类:Builder 配 IP/路由/MTU → establish() → detachFd → NativeCore.start + setTunFd → 前台通知 |
| `.../MainActivity.kt` | 配置表单(服务器/端口/组网名/密钥/虚拟IP/代理网段)+ 连接/断开 + VpnService.prepare 授权流 |
| `app/build.gradle.kts` | compileSdk 34 / minSdk 24 / targetSdk 34,AGP 8.2.2 + Kotlin 1.9.24 + Gradle 8.7 |
| `jniLibs/arm64-v8a/libiconnectd.so` | 预编译内核(debug) |

**构建环境**(Windows):
- JDK 17.0.20(Temurin)→ `%LOCALAPPDATA%\Android\tools\jdk-17.0.20+8`
- Gradle 8.7 → `%LOCALAPPDATA%\Android\tools\gradle-8.7`(构建:设置 JAVA_HOME/GRADLE_HOME 后 `gradle assembleDebug`)
- platform-34(ext7)、build-tools 34.0.0(`build-tools_r34-windows.zip` 解压目录名是 `android-14`,**需改名 `34.0.0`**)

**真机验证**(Pixel 10 / Android 17 / 局域网 192.168.x.x):
- APK(482MB,debug 未 strip)安装成功、MainActivity 启动成功
- JNI 库加载无崩溃(进程存活,logcat 无 FATAL/UnsatisfiedLinkError)
- 内核可执行文件在设备上以**服务端模式**运行成功(listener tcp://0.0.0.0:1993 正常监听)

### 踩坑(重要)

1. **`foregroundServiceType="vpn"` 不存在!** Android 官方 FGS 类型没有 vpn。Android 14+ 的 VPN 应用正确做法:
   ```xml
   android:foregroundServiceType="specialUse"
   + <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="vpn"/>
   + FOREGROUND_SERVICE_SPECIAL_USE 权限
   ```
   (platform-34/35 的 attrs 均无 vpn flag,AAPT 直接报错)
2. **git-bash 中 `$LOCALAPPDATA` 含反斜杠**,放进 PATH 会被转义失效,必须用 `/c/Users/...` unix 路径
3. **build-tools_r34-windows.zip 解压目录名是 `android-14`**,AGP 默认找 `34.0.0`,需改名

### 待用户手动验证(UI 全流程)

VPN 授权弹窗无法自动化,需真机手动:
1. 打开 iConnect App,填写服务器 IP、端口 1993、组网名、密钥、虚拟 IP(留空自动获取)
2. 点"连接" → 同意系统 VPN 授权
3. 观察状态变"已连接";`adb logcat | grep -i iconnect` 或服务端 `peer list` 验证节点入网
4. 与服务端/其他节点 ping 通(虚拟网段 10.144.0.x)

**可选优化**:release 构建(需 llvm-strip 精简 .so,当前 482MB 主要是 debug 符号)。

