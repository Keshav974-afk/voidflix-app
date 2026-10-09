package com.flowflix.flowflix_app

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.speech.RecognizerIntent
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "org.voidflix/notifications"
    private val SPEECH_REQUEST_CODE = 4210
    private var pendingSpeechResult: MethodChannel.Result? = null
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
                "startVoiceSearch" -> {
                    pendingSpeechResult = result
                    try {
                        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                            putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak to search movies and shows…")
                        }
                        startActivityForResult(intent, SPEECH_REQUEST_CODE)
                    } catch (_: Exception) {
                        pendingSpeechResult?.success("")
                        pendingSpeechResult = null
                    }
                }
                "scanFileIntoGallery" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        val file = java.io.File(filePath)
                        if (file.exists()) {
                            android.media.MediaScannerConnection.scanFile(
                                applicationContext,
                                arrayOf(file.absolutePath),
                                arrayOf("video/mp4")
                            ) { path, uri ->
                                android.util.Log.d("Voidflix", "Scanned clip into gallery: $path -> $uri")
                            }
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } else {
                        result.error("ARG_ERROR", "filePath is required", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SPEECH_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val results = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                val spokenText = results?.firstOrNull() ?: ""
                pendingSpeechResult?.success(spokenText)
            } else {
                pendingSpeechResult?.success("")
            }
            pendingSpeechResult = null
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
