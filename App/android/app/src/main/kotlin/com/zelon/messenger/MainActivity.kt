package com.zelon.messenger

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.zelon.messenger/system_notifications"
    private val MESSAGES_CHANNEL_ID = "zelon_messages_channel"
    private val BROADCASTS_CHANNEL_ID = "zelon_broadcasts_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannels()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showNotification" -> {
                    val title = call.argument<String>("title") ?: "New Message"
                    val body = call.argument<String>("body") ?: ""
                    val chatId = call.argument<String>("chatId") ?: ""
                    val notificationId = call.argument<Int>("id") ?: System.currentTimeMillis().toInt()
                    showSystemNotification(notificationId, title, body, chatId, false)
                    result.success(true)
                }
                "showBroadcast" -> {
                    val title = call.argument<String>("title") ?: "Admin Announcement"
                    val body = call.argument<String>("body") ?: ""
                    val notificationId = call.argument<Int>("id") ?: (System.currentTimeMillis().toInt() + 1000)
                    showSystemNotification(notificationId, title, body, "", true)
                    result.success(true)
                }
                "cancelNotification" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.cancel(id)
                    result.success(true)
                }
                "cancelAll" -> {
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.cancelAll()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT)
                .build()

            // 1. WhatsApp Messages Channel
            val msgChannel = NotificationChannel(
                MESSAGES_CHANNEL_ID,
                "Zelon WhatsApp Messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming WhatsApp chat messages and voice notes"
                enableLights(true)
                lightColor = Color.GREEN
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 200, 100, 200)
                setSound(soundUri, audioAttributes)
                setShowBadge(true)
            }
            manager.createNotificationChannel(msgChannel)

            // 2. Broadcasts Channel
            val broadcastChannel = NotificationChannel(
                BROADCASTS_CHANNEL_ID,
                "Zelon Admin Broadcasts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "High priority messages and admin announcements"
                enableLights(true)
                lightColor = Color.RED
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 350, 150, 350)
                setSound(soundUri, audioAttributes)
                setShowBadge(true)
            }
            manager.createNotificationChannel(broadcastChannel)
        }
    }

    private fun showSystemNotification(id: Int, title: String, body: String, chatId: String, isBroadcast: Boolean) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = if (isBroadcast) BROADCASTS_CHANNEL_ID else MESSAGES_CHANNEL_ID

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("chatId", chatId)
            putExtra("isBroadcast", isBroadcast)
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setSound(soundUri)
            .setVibrate(if (isBroadcast) longArrayOf(0, 350, 150, 350) else longArrayOf(0, 200, 100, 200))
            .setLights(if (isBroadcast) Color.RED else Color.GREEN, 500, 1500)

        manager.notify(id, builder.build())
    }
}
