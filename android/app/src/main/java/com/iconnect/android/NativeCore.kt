package com.iconnect.android

/**
 * iConnect 内核 JNI 绑定。
 * 对应 Rust 侧 iconnectd/src/android.rs(符号 Java_com_iconnect_android_NativeCore_*)。
 */
object NativeCore {
    init {
        System.loadLibrary("iconnectd")
    }

    /** 启动内核,加载 [configPath] 指向的 TOML 配置。 */
    external fun start(configPath: String)

    /** 注入 VpnService 的 tun fd(>0 生效)。 */
    external fun setTunFd(fd: Int)

    /** 停止内核。 */
    external fun stop()

    /** 内核是否在运行。 */
    external fun isRunning(): Boolean

    /**
     * 状态描述:
     * - "running" 运行中
     * - "error:<msg>" 失败原因
     * - "idle" 未运行且无错误
     */
    external fun getStatus(): String

    /** 内核分配到的虚拟 IP(DHCP 或配置),未获取到时为空串。 */
    external fun getAssignedIp(): String
}
