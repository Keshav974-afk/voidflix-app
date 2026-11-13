package com.flowflix.flowflix_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

object VoidflixNotificationChecker {
    private const val CONFIG_URL = "https://voidflix.org/api/public/config"
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val BG_PREFS = "voidflix_bg_notif_prefs"
    private const val JOB_ID = 4209

    private val isChecking = AtomicBoolean(false)

    fun schedulePeriodicJob(context: Context) {
        try {
            val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler ?: return
            val component = ComponentName(context, VoidflixNotificationJobService::class.java)
            val builder = JobInfo.Builder(JOB_ID, component)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPersisted(true)
                .setPeriodic(15 * 60 * 1000L)
            scheduler.schedule(builder.build())
        } catch (_: Exception) {}
    }

    fun startBackgroundWatcher(context: Context) {
        schedulePeriodicJob(context)
        try {
            val intent = Intent(context, VoidflixNotificationService::class.java)
            context.startService(intent)
        } catch (_: Exception) {}
    }

    fun checkNow(context: Context, onComplete: (() -> Unit)? = null) {
        if (!isChecking.compareAndSet(false, true)) {
            onComplete?.invoke()
            return
        }

        Thread {
            try {
                val flutterPrefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
                val bgPrefs = context.getSharedPreferences(BG_PREFS, Context.MODE_PRIVATE)

                val pushEnabled = flutterPrefs.getBoolean("flutter.voidflix_notifications_enabled", true)
                if (!pushEnabled) return@Thread

                val conn = (URL(CONFIG_URL).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 7000
                    readTimeout = 7000
                    setRequestProperty("Accept", "application/json")
                    setRequestProperty("User-Agent", "Voidflix-Android/0.4.4")
                }

                if (conn.responseCode == 200) {
                    val reader = BufferedReader(InputStreamReader(conn.inputStream))
                    val sb = StringBuilder()
                    var line: String?
                    while (reader.readLine().also { line = it } != null) {
                        sb.append(line)
                    }
                    reader.close()

                    val json = JSONObject(sb.toString())
                    val history = json.optJSONArray("notificationHistory") ?: return@Thread

                    val isInitialized = bgPrefs.getBoolean("bg_initialized", false) ||
                            flutterPrefs.contains("flutter.voidflix_last_seen_notif")

                    if (!isInitialized) {
                        val fEdit = flutterPrefs.edit()
                        val bEdit = bgPrefs.edit()
                        bEdit.putBoolean("bg_initialized", true)
                        for (i in 0 until history.length()) {
                            val item = history.optJSONObject(i) ?: continue
                            val id = item.optString("id", "")
                            if (id.isNotEmpty()) {
                                fEdit.putBoolean("flutter.admin_notified_$id", true)
                                bEdit.putBoolean("notified_$id", true)
                            }
                        }
                        fEdit.apply()
                        bEdit.apply()
                        return@Thread
                    }

                    for (i in 0 until history.length()) {
                        val item = history.optJSONObject(i) ?: continue
                        val id = item.optString("id", "")
                        if (id.isEmpty()) continue

                        val target = item.optString("target", "all").lowercase()
                        if (target == "web") continue

                        val alreadyNotified = flutterPrefs.getBoolean("flutter.admin_notified_$id", false) ||
                                bgPrefs.getBoolean("notified_$id", false)

                        if (!alreadyNotified) {
                            flutterPrefs.edit().putBoolean("flutter.admin_notified_$id", true).apply()
                            bgPrefs.edit().putBoolean("notified_$id", true).apply()

                            val title = item.optString("title", "Voidflix")
                            val body = item.optString("body", "")
                            if (body.isNotEmpty()) {
                                postSystemNotification(
                                    context = context,
                                    notifId = (id.hashCode() and 0x7FFFFFFF) % 90000 + 10000,
                                    title = title,
                                    body = body
                                )
                            }
                        }
                    }
                }
            } catch (_: Exception) {
            } finally {
                isChecking.set(false)
                onComplete?.invoke()
            }
        }.start()
    }

    fun postSystemNotification(context: Context, notifId: Int, title: String, body: String) {
        try {
            val channelId = "voidflix_notifications"
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    "Voidflix Notifications",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Updates, new releases, and broadcasts from Voidflix"
                    enableVibration(true)
                }
                nm.createNotificationChannel(channel)
            }

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getActivity(context, notifId, launchIntent, pendingFlags)

            val builder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)

            nm.notify(notifId, builder.build())
        } catch (_: Exception) {}
    }
}

class VoidflixNotificationService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val pollRunnable = object : Runnable {
        override fun run() {
            VoidflixNotificationChecker.checkNow(applicationContext)
            handler.postDelayed(this, 25_000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        handler.post(pollRunnable)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        VoidflixNotificationChecker.checkNow(applicationContext)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(pollRunnable)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

class VoidflixNotificationJobService : JobService() {
    override fun onStartJob(params: JobParameters?): Boolean {
        VoidflixNotificationChecker.startBackgroundWatcher(applicationContext)
        VoidflixNotificationChecker.checkNow(applicationContext) {
            if (params != null) {
                jobFinished(params, false)
            }
        }
        return true
    }

    override fun onStopJob(params: JobParameters?): Boolean = true
}

class VoidflixBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action == Intent.ACTION_BOOT_COMPLETED || action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            VoidflixNotificationChecker.startBackgroundWatcher(context.applicationContext)
        }
    }
}
