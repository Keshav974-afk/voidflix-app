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
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.TextureOverlay
import com.google.common.collect.ImmutableList

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaScannerConnection
import androidx.media3.common.Effect
import java.io.File
import java.nio.ByteBuffer

data class SubtitleCue(val startMs: Long, val endMs: Long, val text: String)

class VoidflixOverlay(
    private val cues: List<SubtitleCue>,
    private val burnSubtitles: Boolean,
    private val startMs: Long
) : BitmapOverlay() {

    private val logoPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#E50914")
        textSize = 34f
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        letterSpacing = 0.18f
        setShadowLayer(6f, 2f, 2f, Color.BLACK)
    }

    private val subTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 38f
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        textAlign = Paint.Align.CENTER
        setShadowLayer(6f, 2f, 2f, Color.BLACK)
    }

    private val subBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#99000000")
        style = Paint.Style.FILL
    }

    private val overlayWidth = 1280
    private val overlayHeight = 720
    private val bitmap = Bitmap.createBitmap(overlayWidth, overlayHeight, Bitmap.Config.ARGB_8888)
    private val canvas = Canvas(bitmap)

    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        bitmap.eraseColor(Color.TRANSPARENT)

        // 1. Draw signature VOIDFLIX logo watermark at bottom-right
        val logoText = "VOIDFLIX"
        val logoX = overlayWidth - 210f
        val logoY = overlayHeight - 36f
        canvas.drawText(logoText, logoX, logoY, logoPaint)

        // 2. Draw active subtitle if enabled
        if (burnSubtitles && cues.isNotEmpty()) {
            val currentMediaMs = startMs + (presentationTimeUs / 1000L)
            val activeCue = cues.firstOrNull { cue ->
                currentMediaMs >= cue.startMs && currentMediaMs <= cue.endMs
            }

            if (activeCue != null && activeCue.text.isNotBlank()) {
                val cleanText = activeCue.text.replace(Regex("<[^>]*>"), "").trim()
                val lines = cleanText.split("\n")
                val textX = overlayWidth / 2f
                var startY = overlayHeight - 75f - (lines.size - 1) * 44f

                for (line in lines) {
                    val textWidth = subTextPaint.measureText(line)
                    val bgRect = RectF(
                        textX - (textWidth / 2f) - 18f,
                        startY - 32f,
                        textX + (textWidth / 2f) + 18f,
                        startY + 10f
                    )
                    canvas.drawRoundRect(bgRect, 8f, 8f, subBgPaint)
                    canvas.drawText(line, textX, startY, subTextPaint)
                    startY += 44f
                }
            }
        }

        return bitmap
    }
}

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
                        val file = File(filePath)
                        if (file.exists()) {
                            MediaScannerConnection.scanFile(
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
                "trimAndExportClip" -> {
                    val inputPath = call.argument<String>("inputPath") ?: ""
                    val outputPath = call.argument<String>("outputPath") ?: ""
                    val startMs = (call.argument<Number>("startMs"))?.toLong() ?: 0L
                    val endMs = (call.argument<Number>("endMs"))?.toLong() ?: 0L
                    val isPreTrimmed = call.argument<Boolean>("isPreTrimmed") ?: false
                    val burnSubtitles = call.argument<Boolean>("burnSubtitles") ?: false
                    val rawSubtitles = call.argument<List<Map<String, Any>>>("subtitles") ?: emptyList()

                    val cues = rawSubtitles.mapNotNull { map ->
                        val s = (map["start"] as? Number)?.toLong() ?: return@mapNotNull null
                        val e = (map["end"] as? Number)?.toLong() ?: return@mapNotNull null
                        val t = map["text"] as? String ?: ""
                        SubtitleCue(s, e, t)
                    }

                    trimAndExportClipWithTransformer(inputPath, outputPath, startMs, endMs, cues, burnSubtitles, isPreTrimmed, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun trimAndExportClipWithTransformer(
        inputPath: String,
        outputPath: String,
        startMs: Long,
        endMs: Long,
        cues: List<SubtitleCue>,
        burnSubtitles: Boolean,
        isPreTrimmed: Boolean,
        result: MethodChannel.Result
    ) {
        val inputFile = File(inputPath)
        if (!inputFile.exists()) {
            result.error("FILE_NOT_FOUND", "Source file does not exist: $inputPath", null)
            return
        }

        val outputFile = File(outputPath)
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists()) {
            outputFile.delete()
        }

        val clipStartMs = if (isPreTrimmed) 0L else startMs
        val clipEndMs = if (isPreTrimmed) (endMs - startMs).coerceAtLeast(1000L) else endMs

        // 1. Attempt hardware-accelerated Media3 Transformer for Voidflix logo & burned subtitles
        try {
            val mediaItem = MediaItem.Builder()
                .setUri(android.net.Uri.fromFile(inputFile))
                .setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(clipStartMs)
                        .setEndPositionMs(clipEndMs)
                        .build()
                )
                .build()

            val overlay = VoidflixOverlay(cues, burnSubtitles, if (isPreTrimmed) 0L else startMs)
            val overlayEffect = OverlayEffect(ImmutableList.of(overlay))
            val effects = androidx.media3.transformer.Effects(
                emptyList(),
                listOf<Effect>(overlayEffect)
            )

            val editedMediaItem = EditedMediaItem.Builder(mediaItem)
                .setEffects(effects)
                .build()

            val transformer = Transformer.Builder(applicationContext)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .build()

            transformer.addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    MediaScannerConnection.scanFile(
                        applicationContext,
                        arrayOf(outputFile.absolutePath),
                        arrayOf("video/mp4")
                    ) { _, _ -> }
                    result.success(outputFile.absolutePath)
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException
                ) {
                    android.util.Log.w("Voidflix", "Media3 export error: ${exportException.message}, falling back to muxer...")
                    Thread {
                        val fallbackOk = fallbackMuxerTrim(inputPath, outputFile.absolutePath, startMs, endMs, isPreTrimmed)
                        if (fallbackOk && outputFile.exists() && outputFile.length() > 500) {
                            MediaScannerConnection.scanFile(
                                applicationContext,
                                arrayOf(outputFile.absolutePath),
                                arrayOf("video/mp4")
                            ) { _, _ -> }
                            runOnUiThread { result.success(outputFile.absolutePath) }
                        } else {
                            runOnUiThread { result.error("EXPORT_FAILED", exportException.message, null) }
                        }
                    }.start()
                }
            })

            transformer.start(editedMediaItem, outputFile.absolutePath)
        } catch (e: Exception) {
            android.util.Log.w("Voidflix", "Transformer initialization error: ${e.message}, falling back to muxer...")
            Thread {
                val fallbackOk = fallbackMuxerTrim(inputPath, outputFile.absolutePath, startMs, endMs, isPreTrimmed)
                if (fallbackOk && outputFile.exists() && outputFile.length() > 500) {
                    MediaScannerConnection.scanFile(
                        applicationContext,
                        arrayOf(outputFile.absolutePath),
                        arrayOf("video/mp4")
                    ) { _, _ -> }
                    runOnUiThread { result.success(outputFile.absolutePath) }
                } else {
                    runOnUiThread { result.error("EXPORT_ERROR", e.message ?: "Unknown error", null) }
                }
            }.start()
        }
    }

    private fun fallbackMuxerTrim(
        inputPath: String,
        outputPath: String,
        startMs: Long,
        endMs: Long,
        isPreTrimmed: Boolean
    ): Boolean {
        var extractor: MediaExtractor? = null
        var muxer: MediaMuxer? = null
        try {
            extractor = MediaExtractor()
            extractor.setDataSource(inputPath)
            val trackCount = extractor.trackCount
            if (trackCount == 0) return false

            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            val trackIndexMap = HashMap<Int, Int>()
            var bufferSize = 1024 * 1024

            for (i in 0 until trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("video/") || mime.startsWith("audio/")) {
                    try {
                        extractor.selectTrack(i)
                        val newTrackIndex = muxer.addTrack(format)
                        trackIndexMap[i] = newTrackIndex
                        if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                            val size = format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
                            if (size > bufferSize) bufferSize = size
                        }
                    } catch (trackEx: Exception) {
                        android.util.Log.w("Voidflix", "Track $i ($mime) rejected by muxer: ${trackEx.message}")
                        extractor.unselectTrack(i)
                    }
                }
            }

            if (trackIndexMap.isEmpty()) return false
            muxer.start()

            val durationUs = (endMs - startMs).coerceAtLeast(1000L) * 1000L
            var baseUs = -1L
            val startUs = startMs * 1000L
            val endUs = endMs * 1000L

            if (!isPreTrimmed) {
                extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                baseUs = extractor.sampleTime
                if (baseUs < 0L) baseUs = startUs
            }

            val buffer = ByteBuffer.allocateDirect(bufferSize)
            val bufferInfo = MediaCodec.BufferInfo()
            var samplesWritten = 0

            while (true) {
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize < 0) break

                val sampleTimeUs = extractor.sampleTime
                if (sampleTimeUs < 0) {
                    extractor.advance()
                    continue
                }

                if (isPreTrimmed) {
                    if (baseUs < 0L) {
                        baseUs = sampleTimeUs
                    }
                    if ((sampleTimeUs - baseUs) > durationUs) {
                        break
                    }
                } else {
                    if (sampleTimeUs > endUs) {
                        break
                    }
                }

                val trackIndex = extractor.sampleTrackIndex
                if (trackIndexMap.containsKey(trackIndex)) {
                    val pts = if (baseUs >= 0L) (sampleTimeUs - baseUs).coerceAtLeast(0L) else 0L
                    bufferInfo.offset = 0
                    bufferInfo.size = sampleSize
                    bufferInfo.presentationTimeUs = pts
                    bufferInfo.flags = extractor.sampleFlags
                    try {
                        muxer.writeSampleData(trackIndexMap[trackIndex]!!, buffer, bufferInfo)
                        samplesWritten++
                    } catch (writeEx: Exception) {
                        android.util.Log.w("Voidflix", "Sample write error: ${writeEx.message}")
                    }
                }
                extractor.advance()
            }

            return samplesWritten > 0
        } catch (e: Exception) {
            android.util.Log.e("Voidflix", "Fallback muxer trim failed: ${e.message}")
            return false
        } finally {
            try { extractor?.release() } catch (_: Exception) {}
            try {
                muxer?.stop()
                muxer?.release()
            } catch (_: Exception) {}
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
