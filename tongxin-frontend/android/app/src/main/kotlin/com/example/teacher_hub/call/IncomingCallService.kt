package com.example.teacher_hub.call

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.example.teacher_hub.MainActivity
import com.example.teacher_hub.R

/**
 * ForegroundService + CallStyle 来电方案，适配华为/小米/Android 12+ 后台弹出来电。
 * 替代 fullScreenIntent 方案，避免 hwPS_PopupBackgroundWindowHelper DENY。
 */
class IncomingCallService : Service() {

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val callerName = intent?.getStringExtra(EXTRA_CALLER_NAME) ?: "来电"
        val invitationId = intent?.getStringExtra(EXTRA_INVITATION_ID) ?: ""
        val channelId = intent?.getStringExtra(EXTRA_CHANNEL_ID) ?: ""
        val callType = intent?.getStringExtra(EXTRA_CALL_TYPE) ?: "voice"

        val answerIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("action", "answer_call")
            putExtra(EXTRA_INVITATION_ID, invitationId)
            putExtra(EXTRA_CHANNEL_ID, channelId)
            putExtra(EXTRA_CALL_TYPE, callType)
            putExtra(EXTRA_CALLER_NAME, callerName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        val declineIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("action", "decline_call")
            putExtra(EXTRA_INVITATION_ID, invitationId)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        val answerPendingIntent = PendingIntent.getActivity(
            this, 0, answerIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val declinePendingIntent = PendingIntent.getActivity(
            this, 1, declineIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val channelIdNotif = "incoming_call"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelIdNotif,
                "来电",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "语音/视频来电提醒"
                setSound(null, null)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }

        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val person = android.app.Person.Builder()
                .setName(callerName)
                .build()
            Notification.Builder(this, channelIdNotif)
                .setSmallIcon(R.drawable.ic_call)
                .setContentTitle("来电")
                .setContentText(callerName)
                .setCategory(Notification.CATEGORY_CALL)
                .setOngoing(true)
                .setStyle(
                    Notification.CallStyle.forIncomingCall(
                        person,
                        declinePendingIntent,
                        answerPendingIntent
                    )
                )
                .build()
        } else {
            NotificationCompat.Builder(this, channelIdNotif)
                .setSmallIcon(R.drawable.ic_call)
                .setContentTitle("来电")
                .setContentText(callerName)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setOngoing(true)
                .addAction(0, "接听", answerPendingIntent)
                .addAction(0, "拒绝", declinePendingIntent)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .build()
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val NOTIFICATION_ID = 1001
        const val EXTRA_CALLER_NAME = "caller_name"
        const val EXTRA_INVITATION_ID = "invitation_id"
        const val EXTRA_CHANNEL_ID = "channel_id"
        const val EXTRA_CALL_TYPE = "call_type"
    }
}
