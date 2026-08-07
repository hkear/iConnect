package com.iconnect.android

import android.content.Context
import android.content.SharedPreferences

/**
 * iConnect 连接配置:UI 表单 <-> SharedPreferences <-> TOML 配置文件。
 */
data class AppConfig(
    val serverIp: String,
    val serverPort: String,
    val networkName: String,
    val networkSecret: String,
    val virtualIp: String,
    val proxyCidrs: String,
) {
    companion object {
        // 默认配置:不内置任何真实服务器/凭据,由用户在界面填写(发布安全)
        fun default() = AppConfig(
            serverIp = "",
            serverPort = "1993",
            networkName = "",
            networkSecret = "",
            virtualIp = "",
            proxyCidrs = "",
        )
    }
}

object ConfigStore {
    private const val PREFS = "iconnect_config"
    private const val K_SERVER_IP = "server_ip"
    private const val K_SERVER_PORT = "server_port"
    private const val K_NETWORK_NAME = "network_name"
    private const val K_NETWORK_SECRET = "network_secret"
    private const val K_VIRTUAL_IP = "virtual_ip"
    private const val K_PROXY_CIDRS = "proxy_cidrs"

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(ctx: Context): AppConfig {
        val d = AppConfig.default()
        return with(prefs(ctx)) {
            AppConfig(
                serverIp = getString(K_SERVER_IP, d.serverIp) ?: d.serverIp,
                serverPort = getString(K_SERVER_PORT, d.serverPort) ?: d.serverPort,
                networkName = getString(K_NETWORK_NAME, d.networkName) ?: d.networkName,
                networkSecret = getString(K_NETWORK_SECRET, d.networkSecret) ?: d.networkSecret,
                virtualIp = getString(K_VIRTUAL_IP, d.virtualIp) ?: d.virtualIp,
                proxyCidrs = getString(K_PROXY_CIDRS, d.proxyCidrs) ?: d.proxyCidrs,
            )
        }
    }

    fun save(ctx: Context, cfg: AppConfig) = with(prefs(ctx).edit()) {
        putString(K_SERVER_IP, cfg.serverIp)
        putString(K_SERVER_PORT, cfg.serverPort)
        putString(K_NETWORK_NAME, cfg.networkName)
        putString(K_NETWORK_SECRET, cfg.networkSecret)
        putString(K_VIRTUAL_IP, cfg.virtualIp)
        putString(K_PROXY_CIDRS, cfg.proxyCidrs)
        apply()
    }
}

/**
 * 生成内核 TOML 配置(与 iconnectd/common/config.rs 的 Config 结构对应,
 * 字段参考 config.rs 测试样例 full_example_test)。
 */
object TomlBuilder {
    /** TOML 字符串值转义(双引号/反斜杠)。 */
    private fun esc(s: String): String =
        s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")

    fun build(cfg: AppConfig): String {
        val sb = StringBuilder()
        sb.append("instance_name = \"android\"\n")
        if (cfg.virtualIp.isNotBlank()) {
            // 用户指定虚拟 IP:静态模式
            sb.append("ipv4 = \"").append(esc(cfg.virtualIp.trim())).append("\"\n")
        } else {
            // 自动获取:DHCP 模式(由内核在 peer 连接后分配)
            sb.append("dhcp = true\n")
        }
        sb.append("listeners = []\n")
        val routes = cfg.proxyCidrs.split(',', '，')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        if (routes.isNotEmpty()) {
            sb.append("routes = [ ")
            sb.append(routes.joinToString(", ") { "\"$it\"" })
            sb.append(" ]\n")
        }
        sb.append("\n[network_identity]\n")
        sb.append("network_name = \"").append(esc(cfg.networkName.trim())).append("\"\n")
        sb.append("network_secret = \"").append(esc(cfg.networkSecret)).append("\"\n")
        sb.append("\n[[peer]]\n")
        sb.append("uri = \"tcp://").append(esc(cfg.serverIp.trim()))
            .append(":").append(esc(cfg.serverPort.trim())).append("\"\n")
        sb.append("\n[flags]\n")
        sb.append("default_protocol = \"tcp\"\n")
        sb.append("disable_p2p = true\n")
        sb.append("disable_udp_hole_punching = true\n")
        sb.append("disable_tcp_hole_punching = true\n")
        sb.append("disable_sym_hole_punching = true\n")
        sb.append("disable_upnp = true\n")
        // 注意:no_listener 不是 FlagsInConfig 字段(会导致内核 serde panic),
        // 不监听由顶层 listeners = [] 保证
        return sb.toString()
    }
}
