package com.zelon.messenger

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * Keeps a server-sent-events connection to the Zelon server while the app is in
 * the background or closed, and posts a system notification for each new
 * incoming WhatsApp message. Flutter only notifies while it is on screen.
 */
class MessageListenerService : Service() {

    companion object {
        const val ACTION_START = "com.zelon.messenger.START_LISTENER"
        const val ACTION_STOP = "com.zelon.messenger.STOP_LISTENER"
        const val PREFS = "zelon_background"
        const val MUTED_PREFS = "zelon_muted_chats"
        private const val SERVICE_CHANNEL_ID = "zelon_service_channel"
        private const val MESSAGES_CHANNEL_ID = "zelon_messages_channel"
        private const val BROADCASTS_CHANNEL_ID = "zelon_broadcasts_channel"
        private const val SERVICE_NOTIFICATION_ID = 7001

        fun start(context: Context, baseUrl: String, token: String, instanceId: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("baseUrl", baseUrl)
                .putString("token", token)
                .putString("instanceId", instanceId)
                .apply()
            val intent = Intent(context, MessageListenerService::class.java).setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
            context.stopService(Intent(context, MessageListenerService::class.java))
        }
    }

    @Volatile private var running = false
    @Volatile private var connection: HttpURLConnection? = null
    private var worker: Thread? = null
    private val seenIds = LinkedHashSet<String>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val baseUrl = prefs.getString("baseUrl", null)
        val token = prefs.getString("token", null)
        val instanceId = prefs.getString("instanceId", null)
        if (baseUrl.isNullOrEmpty() || token.isNullOrEmpty() || instanceId.isNullOrEmpty()) {
            stopSelf()
            return START_NOT_STICKY
        }

        try {
            createChannels()
            val notification = buildServiceNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    SERVICE_NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING
                )
            } else {
                startForeground(SERVICE_NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // Android may refuse a foreground start from the background (e.g. a
            // sticky restart); the app restarts the service when next opened.
            stopSelf()
            return START_NOT_STICKY
        }

        // Restart the listener with the latest account/instance.
        stopWorker()
        running = true
        val thread = Thread { listenLoop(baseUrl, token, instanceId) }
        thread.isDaemon = true
        thread.start()
        worker = thread
        return START_STICKY
    }

    override fun onDestroy() {
        stopWorker()
        super.onDestroy()
    }

    private fun stopWorker() {
        running = false
        try {
            connection?.disconnect()
        } catch (_: Exception) {
        }
        worker?.interrupt()
        worker = null
    }

    private fun listenLoop(baseUrl: String, token: String, instanceId: String) {
        var backoffMs = 3000L
        while (running) {
            var conn: HttpURLConnection? = null
            try {
                val url = URL(baseUrl.trimEnd('/') + "/api/instances/" + instanceId + "/stream")
                conn = url.openConnection() as HttpURLConnection
                connection = conn
                conn.requestMethod = "GET"
                conn.connectTimeout = 20000
                // The server sends a ping comment every 20s; a silent minute means a dead link.
                conn.readTimeout = 65000
                conn.setRequestProperty("Authorization", "Bearer $token")
                conn.setRequestProperty("Accept", "text/event-stream")
                conn.setRequestProperty("Cache-Control", "no-cache")
                conn.setRequestProperty("X-Requested-With", "com.zelon.messenger")

                val code = conn.responseCode
                if (code == 401 || code == 403) {
                    // Signed out or access revoked: stop until the app starts us again.
                    running = false
                    stopSelf()
                    return
                }
                if (code != 200) throw Exception("HTTP $code")

                backoffMs = 3000L
                val reader = BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8))
                while (running) {
                    val line = reader.readLine() ?: break
                    if (line.startsWith("data:")) handleEvent(line.substring(5).trim())
                }
            } catch (_: Exception) {
            } finally {
                try {
                    conn?.disconnect()
                } catch (_: Exception) {
                }
            }
            if (!running) break
            try {
                Thread.sleep(backoffMs)
            } catch (_: InterruptedException) {
                break
            }
            backoffMs = (backoffMs * 2).coerceAtMost(60000L)
        }
    }

    private fun handleEvent(json: String) {
        if (json.isEmpty()) return
        val event = try {
            JSONObject(json)
        } catch (_: Exception) {
            return
        }
        // While the app is on screen Flutter shows its own in-app banner.
        if (MainActivity.isInForeground) return

        when (event.optString("type")) {
            "message" -> {
                // Only the inbox event (normalized chatId + notify flag, no 'data')
                // is used, so each message notifies once and history syncs don't.
                if (event.has("data")) return
                if (!event.optBoolean("notify", false)) return
                if (event.optBoolean("fromMe", false)) return
                val waId = event.optString("waId")
                if (waId.isNotEmpty() && !remember(waId)) return
                val chatId = event.optString("chatId")
                val muted = getSharedPreferences(MUTED_PREFS, Context.MODE_PRIVATE)
                    .getStringSet("chatIds", emptySet()) ?: emptySet()
                if (chatId.isNotEmpty() && muted.contains(chatId)) return
                val pushName = event.optString("pushName")
                val title = when {
                    pushName.isNotEmpty() -> pushName
                    chatId.endsWith("@s.whatsapp.net") -> "+" + chatId.substringBefore("@")
                    else -> "New message"
                }
                val preview = event.optString("preview")
                notify(
                    chatId.hashCode(),
                    title,
                    if (preview.isNotEmpty()) preview else "New message received",
                    chatId,
                    false
                )
            }
            "admin_broadcast" -> {
                val data = event.optJSONObject("data") ?: return
                val id = data.optString("id")
                if (id.isNotEmpty() && !remember("b:$id")) return
                notify(
                    ("b:$id").hashCode(),
                    data.optString("title", "Zelon Admin"),
                    data.optString("body", "You got a new announcement from Admin"),
                    "",
                    true
                )
            }
        }
    }

    @Synchronized
    private fun remember(id: String): Boolean {
        if (!seenIds.add(id)) return false
        if (seenIds.size > 300) {
            val iter = seenIds.iterator()
            iter.next()
            iter.remove()
        }
        return true
    }

    private fun notify(id: Int, title: String, body: String, chatId: String, isBroadcast: Boolean) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("chatId", chatId)
            putExtra("isBroadcast", isBroadcast)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            id,
            intent,
            pendingIntentFlags()
        )
        val notification = NotificationCompat.Builder(
            this,
            if (isBroadcast) BROADCASTS_CHANNEL_ID else MESSAGES_CHANNEL_ID
        )
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        try {
            manager.notify(id, notification)
        } catch (_: SecurityException) {
            // Notification permission not granted.
        }
    }

    private fun pendingIntentFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

    private fun buildServiceNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            pendingIntentFlags()
        )
        return NotificationCompat.Builder(this, SERVICE_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Zelon Messenger")
            .setContentText("Connected - you'll get new message alerts")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(openApp)
            .build()
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(SERVICE_CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                SERVICE_CHANNEL_ID,
                "Background connection",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Keeps Zelon connected so new messages can alert you"
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }
        // The message/broadcast channels are normally created by MainActivity;
        // create plain fallbacks if the service starts first.
        if (manager.getNotificationChannel(MESSAGES_CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(MESSAGES_CHANNEL_ID, "Zelon WhatsApp Messages", NotificationManager.IMPORTANCE_HIGH)
            )
        }
        if (manager.getNotificationChannel(BROADCASTS_CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(BROADCASTS_CHANNEL_ID, "Zelon Admin Broadcasts", NotificationManager.IMPORTANCE_HIGH)
            )
        }
    }
}
