package com.iconnect.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor

/**
 * iConnect VPN 服务:
 * 1. 用 VpnService.Builder 创建 tun 接口并配置虚拟 IP / 路由 / MTU;
 * 2. 生成内核 TOML 配置,调用 NativeCore.start + NativeCore.setTunFd 启动内核;
 * 3. 前台通知保持进程存活;onRevoke/stop 时停止内核。
 */
class IConnectVpnService : VpnService() {
    companion object {
        const val ACTION_CONNECT = "com.iconnect.android.CONNECT"
        const val ACTION_DISCONNECT = "com.iconnect.android.DISCONNECT"
        private const val NOTIF_ID = 1
        private const val CHANNEL_ID = "iconnect_vpn"
        private const val MTU = 1360
        /** 占位 IP(测试连接阶段使用,与服务端网段一致,避免污染组网)。 */
        private const val PLACEHOLDER_IP = "10.0.0.200"
        private const val VIRTUAL_PREFIX = 24
    }

    private var fd: ParcelFileDescriptor? = null
    private var active = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> connect()
            ACTION_DISCONNECT -> disconnect()
            else -> {
                // 不自动重连:避免系统重启服务后 VPN 图标残留
            }
        }
        return START_NOT_STICKY
    }

    private fun connect() {
        active = true
        val cfg = ConfigStore.load(this)
        if (cfg.serverIp.isBlank() || cfg.networkName.isBlank()) {
            stopSelf()
            return
        }

        val toml = TomlBuilder.build(cfg)
        val configFile = java.io.File(filesDir, "iconnect.toml")
        configFile.writeText(toml)

        // 两阶段连接:
        // - 静态 IP:直接建 VPN(真实 IP)→ 启动内核 → 注入 fd
        // - DHCP 自动:先启动内核拿 IP;超时则用占位 IP 先连(测试连接),拿到真实 IP 后重建
        val staticIp = cfg.virtualIp.trim()
        if (staticIp.isNotEmpty()) {
            val established = establishVpn(staticIp, cfg)
            if (established == null) return
            startKernel(configFile.absolutePath, established)
        } else {
            NativeCore.stop()
            NativeCore.start(configFile.absolutePath)
            android.widget.Toast.makeText(
                this, "正在连接并获取虚拟 IP…", android.widget.Toast.LENGTH_SHORT
            ).show()
            pollForDhcpIp(0, cfg, placeholderUsed = false)
        }
    }

    /**
     * DHCP 自动获取 IP:
     * 1. 先等内核分配 IP(约 12 秒);
     * 2. 超时则先用占位 IP 建立 VPN(测试连接),内核完整运行后 DHCP 仍会分配;
     * 3. 拿到真实 IP 后重建 VPN(用真实 IP),并 Toast 显示。
     */
    private fun pollForDhcpIp(attempt: Int, cfg: AppConfig, placeholderUsed: Boolean) {
        if (!active) return
        val ip = try {
            NativeCore.getAssignedIp()
        } catch (e: Throwable) {
            ""
        }
        if (ip.isNotEmpty() && ip.contains('.')) {
            // 防御:JNI 可能返回带 /24 后缀的地址,只取纯 IP
            val cleanIp = ip.substringBefore("/")
            if (placeholderUsed) {
                rebuildVpn(cleanIp, cfg)
            } else {
                // 内核已在 connect() 启动(DHCP 已分配 IP),直接建 VPN + 注入 fd,
                // 绝不重启内核(重启会重新 DHCP,IP 变化导致数据面不通)
                val established = establishVpn(cleanIp, cfg) ?: return
                attachFd(established)
                android.widget.Toast.makeText(
                    this, "连接成功,虚拟 IP:$cleanIp", android.widget.Toast.LENGTH_SHORT
                ).show()
            }
            return
        }
        if (!placeholderUsed && attempt == 24) {
            // 12 秒 DHCP 未就绪:占位先连,继续等真实 IP(同样不重启内核)
            val placeholder = PLACEHOLDER_IP
            val established = establishVpn(placeholder, cfg) ?: return
            attachFd(established)
            android.widget.Toast.makeText(
                this, "已用临时地址连接,正在获取真实 IP…", android.widget.Toast.LENGTH_LONG
            ).show()
            pollForDhcpIp(attempt + 1, cfg, placeholderUsed = true)
            return
        }
        if (attempt > 60) { // 总超时 ~30 秒
            android.widget.Toast.makeText(
                this, "获取虚拟 IP 超时,请检查服务器配置", android.widget.Toast.LENGTH_LONG
            ).show()
            NativeCore.stop()
            stopSelf()
            return
        }
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            pollForDhcpIp(attempt + 1, cfg, placeholderUsed)
        }, 500)
    }

    /** 用真实 IP 重建 VPN(替换占位地址)。内核已在运行,直接换 fd 即可。 */
    private fun rebuildVpn(ip: String, cfg: AppConfig) {
        fd?.close()
        fd = null
        val established = establishVpn(ip, cfg) ?: return
        attachFd(established)
        android.widget.Toast.makeText(
            this, "连接成功,虚拟 IP:$ip", android.widget.Toast.LENGTH_SHORT
        ).show()
    }

    /** 注入 tun fd 并进入前台(内核已在运行)。 */
    private fun attachFd(established: ParcelFileDescriptor) {
        val tunFd = established.detachFd()
        NativeCore.setTunFd(tunFd)
        fd = established
        startForeground(NOTIF_ID, buildNotification())
    }

    /** 建立 VPN 接口(用指定 IP),返回 ParcelFileDescriptor,失败时 null。 */
    private fun establishVpn(ip: String, cfg: AppConfig): ParcelFileDescriptor? {
        val builder = Builder()
        builder.setSession("iConnect")
            .setMtu(MTU)
        builder.addAddress(ip, VIRTUAL_PREFIX)
        // 虚拟网段路由:从分配的 IP 推导 /24(适配任意服务端网段)
        val octets = ip.split(".")
        if (octets.size == 4) {
            builder.addRoute("${octets[0]}.${octets[1]}.${octets[2]}.0", VIRTUAL_PREFIX)
        }

        // 附加代理网段(子网代理):让组网内其他节点通过本机访问对应局域网
        cfg.proxyCidrs.split(',', '，').map { it.trim() }.filter { it.isNotEmpty() }.forEach { cidr ->
            val parts = cidr.split("/")
            if (parts.size == 2) {
                val prefix = parts[1].toIntOrNull()
                if (prefix != null) {
                    builder.addRoute(parts[0], prefix)
                }
            }
        }

        val established = try {
            builder.establish()
        } catch (e: Exception) {
            android.widget.Toast.makeText(
                this, "VPN 建立失败: ${e.message}", android.widget.Toast.LENGTH_LONG
            ).show()
            stopSelf()
            return null
        }
        if (established == null) {
            android.widget.Toast.makeText(
                this, "VPN 建立失败(VpnService.establish 返回空)", android.widget.Toast.LENGTH_LONG
            ).show()
            stopSelf()
            return null
        }
        return established
    }

    /** 启动内核(仅静态模式使用:内核未启动,需要 stop+start 保证干净)+ 注入 fd。 */
    private fun startKernel(configPath: String, established: ParcelFileDescriptor) {
        NativeCore.stop() // 确保干净状态
        NativeCore.start(configPath)
        attachFd(established)
    }

    private fun disconnect() {
        active = false
        NativeCore.stop()
        fd?.close()
        fd = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onRevoke() {
        // 用户关闭 VPN:停止内核
        disconnect()
    }

    override fun onDestroy() {
        NativeCore.stop()
        fd?.close()
        fd = null
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "iConnect VPN", NotificationManager.IMPORTANCE_LOW
            )
            nm.createNotificationChannel(channel)
        }
        val disconnectIntent = Intent(this, IConnectVpnService::class.java)
            .setAction(ACTION_DISCONNECT)
        val pi = PendingIntent.getService(
            this, 0, disconnectIntent, PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("iConnect")
            .setContentText("虚拟组网已连接")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }
}
