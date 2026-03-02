package com.example.teacher_hub

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.app.NotificationManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.example.teacher_hub.call.IncomingCallService

/**
 * 主 Activity：支持锁屏显示来电，并捕获个推通知点击冷启动时的 payload。
 */
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureLaunchPayload(intent)
        handleCallActionIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureLaunchPayload(intent)
        handleCallActionIntent(intent)
    }

    private fun handleCallActionIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.getStringExtra("action") ?: return
        when (action) {
            "answer_call" -> {
                stopService(Intent(this, IncomingCallService::class.java))
                val invitationId = intent.getStringExtra("invitation_id") ?: ""
                val channelId = intent.getStringExtra("channel_id") ?: ""
                val callType = intent.getStringExtra("call_type") ?: "voice"
                val callerName = intent.getStringExtra("caller_name") ?: "对方"
                if (invitationId.isNotEmpty() && channelId.isNotEmpty()) {
                    PendingCallAnswerHolder.data = mapOf(
                        "invitationId" to invitationId,
                        "channelId" to channelId,
                        "callType" to callType,
                        "fromUserName" to callerName,
                    )
                }
            }
            "decline_call" -> {
                stopService(Intent(this, IncomingCallService::class.java))
                val invitationId = intent.getStringExtra("invitation_id") ?: ""
                if (invitationId.isNotEmpty()) {
                    PendingCallDeclineHolder.invitationId = invitationId
                }
            }
        }
    }

    fun startIncomingCallService(caller: String, invitationId: String, channelId: String, callType: String) {
        val intent = Intent(this, IncomingCallService::class.java).apply {
            putExtra(IncomingCallService.EXTRA_CALLER_NAME, caller)
            putExtra(IncomingCallService.EXTRA_INVITATION_ID, invitationId)
            putExtra(IncomingCallService.EXTRA_CHANNEL_ID, channelId)
            putExtra(IncomingCallService.EXTRA_CALL_TYPE, callType)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
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
            when (call.method) {
                "getLaunchPayload" -> {
                    val payload = LaunchPayloadHolder.payload
                    LaunchPayloadHolder.payload = null
                    result.success(payload)
                }
                "canUseFullScreenIntent" -> {
                    result.success(canUseFullScreenIntent())
                }
                "openFullScreenIntentSettings" -> {
                    openFullScreenIntentSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CALL_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "showIncomingCall" -> {
                    val caller = call.argument<String>("caller") ?: "来电"
                    val invitationId = call.argument<String>("invitationId") ?: ""
                    val channelId = call.argument<String>("channelId") ?: ""
                    val callType = call.argument<String>("callType") ?: "voice"
                    startIncomingCallService(caller, invitationId, channelId, callType)
                    result.success(true)
                }
                "getPendingCallAnswer" -> {
                    val data = PendingCallAnswerHolder.data
                    PendingCallAnswerHolder.data = null
                    result.success(data)
                }
                "getPendingCallDecline" -> {
                    val id = PendingCallDeclineHolder.invitationId
                    PendingCallDeclineHolder.invitationId = null
                    result.success(id)
                }
                "dismissIncomingCall" -> {
                    stopService(Intent(this, IncomingCallService::class.java))
                    result.success(true)
                }
                else -> result.notImplemented()
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

    /** Android 14+ 需用户手动开启「全屏意图」权限，否则来电只显示横幅不弹全屏 */
    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < 34) return true
        val nm = getSystemService(NOTIFICATION_SERVICE) as? NotificationManager ?: return true
        return nm.canUseFullScreenIntent()
    }

    private fun openFullScreenIntentSettings() {
        if (Build.VERSION.SDK_INT >= 34) {
            try {
                val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                    .setData(Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "openFullScreenIntentSettings failed, fallback to app settings", e)
                try {
                    val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.parse("package:$packageName"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(fallback)
                } catch (e2: Exception) {
                    Log.e(TAG, "fallback also failed", e2)
                }
            }
        } else {
            try {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "openAppSettings failed", e)
            }
        }
    }

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.example.teacher_hub/launch"
        private const val CALL_CHANNEL = "teacherhub.call"
    }
}

object LaunchPayloadHolder {
    @Volatile
    var payload: String? = null
}

object PendingCallAnswerHolder {
    @Volatile
    var data: Map<String, String>? = null
}

object PendingCallDeclineHolder {
    @Volatile
    var invitationId: String? = null
}
