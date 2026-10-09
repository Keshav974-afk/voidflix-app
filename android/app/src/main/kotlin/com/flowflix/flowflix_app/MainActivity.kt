package com.flowflix.flowflix_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "org.voidflix/notifications"
    private var wakeLock: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showNotification" -> {
                    val id = call.argument<Int>("id") ?: 1
                    val title = call.argument<String>("title") ?: "Voidflix"
                    val body = call.argument<String>("body") ?: ""

                    showSystemNotification(id, title, body)
                    result.success(true)
                }
                "updateDownloadProgress" -> {
                    val id = call.argument<Int>("id") ?: 999
                    val title = call.argument<String>("title") ?: "Voidflix Download"
                    val progress = call.argument<Int>("progress") ?: 0
                    val isDone = call.argument<Boolean>("isDone") ?: false

                    updateDownloadNotification(id, title, progress, isDone)
                    result.success(true)
                }
                "cancelDownloadNotification" -> {
                    val id = call.argument<Int>("id") ?: 999
                    cancelDownloadNotification(id)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun showSystemNotification(id: Int, title: String, body: String) {
        val channelId = "voidflix_notifications"
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Voidflix Notifications",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Updates and trending picks from Voidflix"
            }
            notificationManager.createNotificationChannel(channel)
        }

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)

        notificationManager.notify(id, builder.build())
    }

    private fun updateDownloadNotification(id: Int, title: String, progress: Int, isDone: Boolean) {
        val channelId = "voidflix_downloads"
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Voidflix Downloads",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Active download status and offline progress"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }

        if (isDone) {
            releaseWakeLock()
            val builder = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText("Download complete — ready to play offline.")
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setAutoCancel(true)
                .setOngoing(false)

            notificationManager.notify(id, builder.build())
        } else {
            acquireWakeLock()
            val builder = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText("Downloading… $progress%")
                .setProgress(100, progress, false)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(true)
                .setOnlyAlertOnce(true)

            notificationManager.notify(id, builder.build())
        }
    }

    private fun cancelDownloadNotification(id: Int) {
        releaseWakeLock()
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(id)
    }

    private fun acquireWakeLock() {
        try {
            if (wakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Voidflix::DownloadWakeLock").apply {
                    setReferenceCounted(false)
                }
            }
            if (wakeLock?.isHeld == false) {
                wakeLock?.acquire(2 * 60 * 60 * 1000L) // 2 hours maximum safety timeout
            }
        } catch (_: Exception) {}
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
    }
}

