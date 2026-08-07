//! Android JNI 入口层:iConnect 内核的移动端集成(同进程模式)
//!
//! Java 侧对应类:`com.iconnect.android.NativeCore`,声明为 `external` native 方法:
//! ```java
//! class NativeCore {
//!     static native void start(String configPath);
//!     static native void setTunFd(int fd);
//!     static native void stop();
//!     static native boolean isRunning();
//! }
//! ```
//!
//! 工作方式:
//! 1. `start` 在独立线程上创建 tokio runtime,加载 TOML 配置文件并启动网络实例;
//!    实例启动后(Android 编译目标下 `launcher.rs` 的 mobile 分支自动生效)
//!    通过 `run_routine_for_mobile` 监听 tun fd channel,等待注入。
//! 2. `setTunFd` 把 Android VpnService 创建出的 tun fd 交给内核
//!    (复用 `InstanceManager::set_tun_fd`,虚拟 IP/路由由 VpnService.Builder 配置)。
//! 3. `stop` 删除网络实例,`manager.wait()` 返回后 runtime 线程退出。

use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};

use jni::objects::{JClass, JString};
use jni::sys::jint;
use jni::JNIEnv;
use uuid::Uuid;

use crate::common::config::load_config_from_file;
use crate::common::global_ctx::GlobalCtxEvent;
use crate::common::log;
use crate::instance_manager::NetworkInstanceManager;

/// 运行中的内核上下文(全进程唯一,单实例模式)
struct Ctx {
    manager: Arc<NetworkInstanceManager>,
    instance_id: Uuid,
}

static CTX: OnceLock<Mutex<Option<Ctx>>> = OnceLock::new();
static LAST_ERROR: OnceLock<Mutex<Option<String>>> = OnceLock::new();
/// 内核实例启动前收到的 tun fd 缓存(ctx 就绪后自动注入)
static PENDING_FD: OnceLock<Mutex<Option<i32>>> = OnceLock::new();
/// DHCP 分配的虚拟 IP(DhcpIpv4Changed 事件捕获)
static ASSIGNED_IP: OnceLock<Mutex<Option<String>>> = OnceLock::new();

fn ctx() -> &'static Mutex<Option<Ctx>> {
    CTX.get_or_init(|| Mutex::new(None))
}

fn pending_fd() -> &'static Mutex<Option<i32>> {
    PENDING_FD.get_or_init(|| Mutex::new(None))
}

fn set_error(msg: String) {
    *LAST_ERROR.get_or_init(|| Mutex::new(None)).lock().unwrap() = Some(msg);
}

/// 调试用文件日志:写入配置同目录 debug.log(不依赖 tracing/logcat,
/// 用于诊断 Android 上内核启动问题)。
static DEBUG_LOG: OnceLock<PathBuf> = OnceLock::new();

fn debug_log(msg: &str) {
    let Some(path) = DEBUG_LOG.get() else { return };
    use std::io::Write;
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
    {
        let _ = writeln!(f, "{} {}", chrono::Local::now().format("%H:%M:%S"), msg);
    }
}

/// Java: `static native void start(String configPath);`
///
/// 启动内核:加载 `configPath` 指向的 TOML 配置并创建网络实例。
/// 阻塞线程直到实例停止(`manager.wait()`),保证 tokio runtime 存活。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_iconnect_android_NativeCore_start(
    mut env: JNIEnv,
    _class: JClass,
    config_path: JString,
) {
    let path: String = match env.get_string(&config_path) {
        Ok(s) => s.into(),
        Err(e) => {
            eprintln!("[iconnect] failed to read config path from JNI: {e}");
            return;
        }
    };
    log::info!(path, "Android core start requested");

    // 初始化调试日志路径(配置同目录)
    let _ = DEBUG_LOG.set(PathBuf::from(&path).with_file_name("debug.log"));
    debug_log(&format!("start requested, config={path}"));

    // 如果已有实例在跑,先停掉
    stop_internal();

    std::thread::spawn(move || {
        debug_log("thread spawned, building tokio runtime");
        // panic hook:把 panic 信息写入 debug.log(Android 上 stderr 不可见)
        let prev = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            let msg = info.to_string();
            eprintln!("[iconnect] PANIC: {msg}");
            if let Some(path) = DEBUG_LOG.get() {
                use std::io::Write;
                if let Ok(mut f) = std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(path)
                {
                    let _ = writeln!(
                        f,
                        "{} PANIC: {msg}",
                        chrono::Local::now().format("%H:%M:%S")
                    );
                }
            }
            prev(info);
        }));
        let rt = match tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
        {
            Ok(rt) => rt,
            Err(e) => {
                eprintln!("[iconnect] failed to build tokio runtime: {e}");
                debug_log(&format!("runtime build failed: {e}"));
                set_error(format!("failed to build tokio runtime: {e}"));
                return;
            }
        };
        debug_log("tokio runtime built");

        let run_result = rt.block_on(async move {
            // Android 上日志输出到 logcat(替代 console stdout,logcat 不可见)
            use tracing_subscriber::layer::SubscriberExt;
            let sub_result = tracing::subscriber::set_global_default(
                tracing_subscriber::registry()
                    .with(tracing_android::layer("iconnectd").expect("android log layer"))
                    .with(tracing::level_filters::LevelFilter::INFO),
            );
            debug_log(&format!(
                "set_global_default: {}",
                if sub_result.is_ok() { "ok" } else { "already-set/err" }
            ));

            let manager = Arc::new(NetworkInstanceManager::new());

            // 加载配置并启动实例,拿到 instance_id
            let start_result: Result<Uuid, anyhow::Error> = async {
                debug_log("loading config from file");
                let (cfg, control) = load_config_from_file(&PathBuf::from(&path), None, true)
                    .await
                    .map_err(|e| anyhow::anyhow!("load config failed: {e}"))?;
                debug_log("config loaded, running network instance");
                let instance_id = manager
                    .run_network_instance(cfg, true, control)
                    .map_err(|e| anyhow::anyhow!("run instance failed: {e}"))?;
                debug_log(&format!("instance started, id={instance_id}"));
                Ok(instance_id)
            }
            .await;

            match start_result {
                Ok(instance_id) => {
                    *ctx().lock().unwrap() = Some(Ctx {
                        manager: manager.clone(),
                        instance_id,
                    });
                    log::info!(%instance_id, "Android core instance started, waiting for tun fd");
                    debug_log(&format!("ctx set, waiting for instance stop (id={instance_id})"));

                    // 订阅实例事件,捕获 DHCP 分配的虚拟 IP
                    if let Some(mut rx) = manager.subscribe_instance_events(&instance_id) {
                        tokio::spawn(async move {
                            while let Ok(ev) = rx.recv().await {
                                if let GlobalCtxEvent::DhcpIpv4Changed(_, Some(new_ip)) = ev {
                                    // new_ip 是 cidr::Ipv4Inet,to_string() 带 /24 后缀;
                                    // 只取纯 IP 地址供 VpnService.addAddress 使用
                                    let s = new_ip.address().to_string();
                                    *ASSIGNED_IP
                                        .get_or_init(|| Mutex::new(None))
                                        .lock()
                                        .unwrap() = Some(s.clone());
                                    debug_log(&format!("dhcp ip assigned: {s}"));
                                }
                            }
                        });
                    }

                    // 注入启动前缓存下来的 tun fd(Java 侧 start 后立即 setTunFd 会早于 ctx 就绪)
                    if let Some(fd) = pending_fd().lock().unwrap().take() {
                        match manager.set_tun_fd(&instance_id, fd) {
                            Ok(()) => {
                                log::info!(fd, "cached tun fd injected after instance start");
                                debug_log(&format!("cached tun fd {fd} injected"));
                            }
                            Err(e) => {
                                log::error!(%e, "failed to inject cached tun fd");
                                debug_log(&format!("cached fd inject FAILED: {e}"));
                                set_error(format!("failed to inject cached tun fd: {e}"));
                            }
                        }
                    }

                    // 保持 runtime 存活,直到实例停止或 stop() 触发删除
                    let _ = manager.wait().await;
                    log::info!("Android core instance exited, cleaning up");
                    debug_log("manager.wait returned, clearing ctx");
                    *ctx().lock().unwrap() = None;
                }
                Err(e) => {
                    log::error!(%e, "Android core failed to start");
                    debug_log(&format!("start FAILED: {e}"));
                    set_error(e.to_string());
                }
            }
        });
        let _ = run_result;
    });
}

/// Java: `static native void setTunFd(int fd);`
///
/// 注入 VpnService 创建的 tun fd(>0 生效;<=0 表示撤销,内核侧跳过)。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_iconnect_android_NativeCore_setTunFd(
    _env: JNIEnv,
    _class: JClass,
    fd: jint,
) {
    let instance_id = ctx().lock().unwrap().as_ref().map(|c| c.instance_id);
    match instance_id {
        Some(instance_id) => {
            let guard = ctx().lock().unwrap();
            let Some(ctx) = guard.as_ref() else {
                return;
            };
            match ctx.manager.set_tun_fd(&instance_id, fd) {
                Ok(()) => log::info!(fd, "tun fd injected"),
                Err(e) => {
                    log::error!(%e, "failed to inject tun fd");
                    set_error(format!("failed to inject tun fd: {e}"));
                }
            }
        }
        None => {
            // 内核实例还没启动完成:缓存 fd,启动后自动注入
            log::warn!(fd, "core not started yet, caching tun fd");
            debug_log(&format!("caching tun fd {fd} (core not ready)"));
            *pending_fd().lock().unwrap() = Some(fd);
        }
    }
}

/// Java: `static native void stop();`
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_iconnect_android_NativeCore_stop(_env: JNIEnv, _class: JClass) {
    stop_internal();
}

fn stop_internal() {
    let maybe = ctx().lock().unwrap().take();
    if let Some(c) = maybe {
        log::info!(instance_id = %c.instance_id, "stopping Android core");
        let _ = c
            .manager
            .delete_network_instance(vec![c.instance_id])
            .map_err(|e| log::error!(%e, "failed to delete instance"));
    }
}

/// Java: `static native boolean isRunning();`
///
/// 返回内核是否正在运行(供 UI 显示连接状态)。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_iconnect_android_NativeCore_isRunning(
    _env: JNIEnv,
    _class: JClass,
) -> jint {
    u8::from(ctx().lock().unwrap().is_some()) as jint
}

/// Java: `static native String getAssignedIp();`
///
/// 返回 DHCP 分配(或配置指定)的虚拟 IP,未获取到时返回空串。
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_iconnect_android_NativeCore_getAssignedIp<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
) -> JString<'local> {
    let ip = ASSIGNED_IP
        .get_or_init(|| Mutex::new(None))
        .lock()
        .unwrap()
        .clone()
        .unwrap_or_default();
    match env.new_string(&ip) {
        Ok(js) => js,
        Err(_) => env
            .new_string("")
            .expect("jni string alloc failed"),
    }
}

/// Java: `static native String getStatus();`
///
/// 返回状态描述,供 UI 显示连接状态与失败原因:
/// - `"running"`:内核运行中
/// - `"error:<msg>"`:上次启动/注入失败原因
/// - `"idle"`:未运行且无错误
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_iconnect_android_NativeCore_getStatus<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
) -> JString<'local> {
    let running = ctx().lock().unwrap().is_some();
    let err = LAST_ERROR.get_or_init(|| Mutex::new(None)).lock().unwrap().clone();
    let s = if running {
        "running".to_string()
    } else if let Some(e) = err {
        format!("error:{e}")
    } else {
        "idle".to_string()
    };
    match env.new_string(&s) {
        Ok(js) => js,
        Err(_) => env
            .new_string("error:jni string alloc failed")
            .expect("jni string alloc failed"),
    }
}
