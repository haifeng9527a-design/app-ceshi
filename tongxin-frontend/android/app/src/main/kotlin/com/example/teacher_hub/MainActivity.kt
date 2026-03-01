package com.example.teacher_hub

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 主 Activity：支持锁屏显示来电，并捕获个推通知点击冷启动时的 payload。
 */
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 捕获启动 intent 中的个推 payload（应用被杀死后点击来电通知拉起）
        captureLaunchPayload(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureLaunchPayload(intent)
    }

    private fun captureLaunchPayload(intent: Intent?) {
        if (intent == null) return
        val extras = intent.extras ?: return
        // 优先检查 payload（个推/华为厂商通道 intent 格式）
        extras.getString("payload")?.let { p ->
            if (p.contains("call_invitation")) {
                LaunchPayloadHolder.payload = p
                Log.d(TAG, "Captured launch payload (key=payload)")
                return
            }
        }
        for (key in extras.keySet()) {
            val value = extras.get(key)?.toString() ?: continue
            if (value.contains("messageType") && value.contains("call_invitation")) {
                LaunchPayloadHolder.payload = value
                Log.d(TAG, "Captured launch payload (key=$key)")
                break
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method == "getLaunchPayload") {
                val payload = LaunchPayloadHolder.payload
                LaunchPayloadHolder.payload = null
                result.success(payload)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // 锁屏来电：确保 Activity 在锁屏上可见
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
    }

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.example.teacher_hub/launch"
    }
}

object LaunchPayloadHolder {
    @Volatile
    var payload: String? = null
}
