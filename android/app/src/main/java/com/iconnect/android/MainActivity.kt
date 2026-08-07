package com.iconnect.android

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast

/**
 * iConnect Android 客户端主界面:配置表单 + 连接/断开控制。
 */
class MainActivity : Activity() {

    private lateinit var etServerIp: EditText
    private lateinit var etServerPort: EditText
    private lateinit var etNetworkName: EditText
    private lateinit var etNetworkSecret: EditText
    private lateinit var etVirtualIp: EditText
    private lateinit var etProxyCidrs: EditText
    private lateinit var btnConnect: Button
    private lateinit var tvStatus: TextView

    private val handler = Handler(Looper.getMainLooper())
    private val statusRunnable = object : Runnable {
        override fun run() {
            refreshStatus()
            handler.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        etServerIp = findViewById(R.id.etServerIp)
        etServerPort = findViewById(R.id.etServerPort)
        etNetworkName = findViewById(R.id.etNetworkName)
        etNetworkSecret = findViewById(R.id.etNetworkSecret)
        etVirtualIp = findViewById(R.id.etVirtualIp)
        etProxyCidrs = findViewById(R.id.etProxyCidrs)
        btnConnect = findViewById(R.id.btnConnect)
        tvStatus = findViewById(R.id.tvStatus)

        val saved = ConfigStore.load(this)
        etServerIp.setText(saved.serverIp)
        etServerPort.setText(saved.serverPort)
        etNetworkName.setText(saved.networkName)
        etNetworkSecret.setText(saved.networkSecret)
        etVirtualIp.setText(saved.virtualIp)
        etProxyCidrs.setText(saved.proxyCidrs)

        btnConnect.setOnClickListener {
            if (NativeCore.isRunning()) {
                disconnect()
            } else {
                connect()
            }
        }
        refreshStatus()
    }

    private fun connect() {
        val cfg = AppConfig(
            serverIp = etServerIp.text.toString().trim(),
            serverPort = etServerPort.text.toString().trim().ifEmpty { "1993" },
            networkName = etNetworkName.text.toString().trim(),
            networkSecret = etNetworkSecret.text.toString(),
            // 留空 = DHCP 自动从服务器获取(不要用默认 IP,会污染组网)
            virtualIp = etVirtualIp.text.toString().trim(),
            proxyCidrs = etProxyCidrs.text.toString().trim(),
        )
        if (cfg.serverIp.isBlank() || cfg.networkName.isBlank()) {
            Toast.makeText(this, "请填写服务器 IP 和组网名称", Toast.LENGTH_SHORT).show()
            return
        }
        ConfigStore.save(this, cfg)

        // VPN 授权流程:系统会弹出 VPN 确认框
        val prepareIntent = VpnService.prepare(this)
        if (prepareIntent != null) {
            startActivityForResult(prepareIntent, REQ_VPN_PREPARE)
        } else {
            startVpn()
        }
    }

    private fun startVpn() {
        val intent = Intent(this, IConnectVpnService::class.java)
            .setAction(IConnectVpnService.ACTION_CONNECT)
        startService(intent)
        Toast.makeText(this, "正在连接…", Toast.LENGTH_SHORT).show()
        refreshStatus()
    }

    private fun disconnect() {
        // 双保险:直接停内核 + 停止服务(onDestroy 也会停,系统移除 VPN)
        NativeCore.stop()
        stopService(Intent(this, IConnectVpnService::class.java))
        Toast.makeText(this, "已断开", Toast.LENGTH_SHORT).show()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_VPN_PREPARE) {
            if (resultCode == RESULT_OK) {
                startVpn()
            } else {
                Toast.makeText(this, "未授予 VPN 权限", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun refreshStatus() {
        val status = try {
            NativeCore.getStatus()
        } catch (e: Throwable) {
            "error:JNI 调用失败: ${e.message}"
        }
        val ip = if (status == "running") {
            try {
                NativeCore.getAssignedIp()
            } catch (e: Throwable) {
                ""
            }
        } else {
            ""
        }
        tvStatus.text = when {
            status == "running" ->
                if (ip.isNotEmpty()) "状态:已连接\n虚拟 IP:$ip" else "状态:已连接"
            status.startsWith("error:") ->
                "状态:未连接\n原因:${status.removePrefix("error:")}"
            else -> getString(R.string.status_disconnected)
        }
        btnConnect.text = if (status == "running") "断开连接" else "连接"
    }

    override fun onResume() {
        super.onResume()
        refreshStatus()
        handler.post(statusRunnable)
    }

    override fun onPause() {
        super.onPause()
        handler.removeCallbacks(statusRunnable)
    }

    companion object {
        private const val REQ_VPN_PREPARE = 100
    }
}
