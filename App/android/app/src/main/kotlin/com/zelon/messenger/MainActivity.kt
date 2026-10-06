package com.zelon.messenger

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private val NOTIFICATION_CHANNEL = "com.zelon.messenger/system_notifications"
    private val LOCATION_CHANNEL = "com.zelon.messenger/location"
    private val MESSAGES_CHANNEL_ID = "zelon_messages_channel"
    private val BROADCASTS_CHANNEL_ID = "zelon_broadcasts_channel"
    private val LOCATION_PERMISSION_REQUEST_CODE = 1001

    private var pendingLocationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannels()
        setupNotificationChannel(flutterEngine)
        setupLocationChannel(flutterEngine)
    }

    private fun setupNotificationChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL).setMethodCallHandler { call, result ->
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

    private fun setupLocationChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> {
                    val fine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
                    val coarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION)
                    if (fine == PackageManager.PERMISSION_GRANTED || coarse == PackageManager.PERMISSION_GRANTED) {
                        result.success("granted")
                    } else {
                        result.success("denied")
                    }
                }
                "requestPermission" -> {
                    val fine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
                    val coarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION)
                    if (fine == PackageManager.PERMISSION_GRANTED || coarse == PackageManager.PERMISSION_GRANTED) {
                        result.success("granted")
                    } else {
                        pendingLocationResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                            LOCATION_PERMISSION_REQUEST_CODE
                        )
                    }
                }
                "isLocationEnabled" -> {
                    val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
                    val gps = lm.isProviderEnabled(LocationManager.GPS_PROVIDER)
                    val network = lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
                    result.success(gps || network)
                }
                "openLocationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "getCurrentLocation" -> {
                    getCurrentGpsLocation(result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getCurrentGpsLocation(result: MethodChannel.Result) {
        val fine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION)
        if (fine != PackageManager.PERMISSION_GRANTED && coarse != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION_DENIED", "Location permission is not granted", null)
            return
        }

        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        var bestLocation: Location? = null

        // Check last known location from all providers
        val providers = lm.getProviders(true)
        for (provider in providers) {
            try {
                val l = lm.getLastKnownLocation(provider) ?: continue
                if (bestLocation == null || l.accuracy < bestLocation.accuracy) {
                    bestLocation = l
                }
            } catch (_: SecurityException) {}
        }

        // If fresh location is available (< 20 seconds, accuracy < 80 meters), return immediately
        if (bestLocation != null && (System.currentTimeMillis() - bestLocation.time) < 20000 && bestLocation.accuracy < 80) {
            result.success(locationToMap(bestLocation))
            return
        }

        val handler = Handler(Looper.getMainLooper())
        var responded = false

        val listener = object : LocationListener {
            override fun onLocationChanged(loc: Location) {
                if (!responded) {
                    responded = true
                    handler.removeCallbacksAndMessages(null)
                    try { lm.removeUpdates(this) } catch (_: Exception) {}
                    result.success(locationToMap(loc))
                }
            }
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }

        val timeoutRunnable = Runnable {
            if (!responded) {
                responded = true
                try { lm.removeUpdates(listener) } catch (_: Exception) {}
                if (bestLocation != null) {
                    result.success(locationToMap(bestLocation))
                } else {
                    result.error("LOCATION_TIMEOUT", "Unable to obtain fresh GPS fix within timeout", null)
                }
            }
        }
        handler.postDelayed(timeoutRunnable, 9000)

        var requested = false
        if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            try {
                lm.requestSingleUpdate(LocationManager.GPS_PROVIDER, listener, Looper.getMainLooper())
                requested = true
            } catch (_: SecurityException) {}
        }
        if (!requested && lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
            try {
                lm.requestSingleUpdate(LocationManager.NETWORK_PROVIDER, listener, Looper.getMainLooper())
                requested = true
            } catch (_: SecurityException) {}
        }

        if (!requested) {
            handler.removeCallbacks(timeoutRunnable)
            if (bestLocation != null) {
                result.success(locationToMap(bestLocation))
            } else {
                result.error("PROVIDER_DISABLED", "Location services are turned off", null)
            }
        }
    }

    private fun locationToMap(loc: Location): Map<String, Any> {
        return mapOf(
            "latitude" to loc.latitude,
            "longitude" to loc.longitude,
            "accuracy" to loc.accuracy.toDouble(),
            "altitude" to loc.altitude,
            "speed" to loc.speed.toDouble(),
            "time" to loc.time
        )
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == LOCATION_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults.any { it == PackageManager.PERMISSION_GRANTED }
            pendingLocationResult?.success(if (granted) "granted" else "denied")
            pendingLocationResult = null
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
