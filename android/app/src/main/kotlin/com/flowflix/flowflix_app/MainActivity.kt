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
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaScannerConnection
import java.io.File
import java.nio.ByteBuffer

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

                    val inputFile = File(inputPath)
                    if (!inputFile.exists()) {
                        result.error("FILE_NOT_FOUND", "Source file does not exist: $inputPath", null)
                        return@setMethodCallHandler
                    }

                    val outputFile = File(outputPath)
                    outputFile.parentFile?.mkdirs()
                    if (outputFile.exists()) {
                        outputFile.delete()
                    }

                    Thread {
                        try {
                            val trimOk = fallbackMuxerTrim(inputPath, outputFile.absolutePath, startMs, endMs, isPreTrimmed)
                            if (trimOk && outputFile.exists() && outputFile.length() > 500) {
                                MediaScannerConnection.scanFile(
                                    applicationContext,
                                    arrayOf(outputFile.absolutePath),
                                    arrayOf("video/mp4")
                                ) { _, _ -> }
                                runOnUiThread {
                                    result.success(outputFile.absolutePath)
                                }
                            } else {
                                runOnUiThread {
                                    result.error("TRIM_FAILED", "Failed to trim video stream", null)
                                }
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("Voidflix", "Clip export error: ${e.message}", e)
                            runOnUiThread {
                                result.error("EXPORT_ERROR", e.message ?: "Unknown error", null)
                            }
                        }
                    }.start()
                }
                "getDeviceInfo" -> {
                    try {
                        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            packageManager.getPackageInfo(packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageInfo(packageName, 0)
                        }

                        val versionName = packageInfo.versionName ?: "1.0.0"
                        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            packageInfo.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            packageInfo.versionCode.toLong()
                        }

                        val supportedAbis = Build.SUPPORTED_ABIS.joinToString(", ")
                        val primaryAbi = Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"

                        val info = mapOf(
                            "model" to Build.MODEL,
                            "manufacturer" to Build.MANUFACTURER,
                            "brand" to Build.BRAND,
                            "device" to Build.DEVICE,
                            "product" to Build.PRODUCT,
                            "hardware" to Build.HARDWARE,
                            "board" to Build.BOARD,
                            "versionName" to versionName,
                            "versionCode" to versionCode,
                            "sdkInt" to Build.VERSION.SDK_INT,
                            "release" to Build.VERSION.RELEASE,
                            "supportedAbis" to supportedAbis,
                            "primaryAbi" to primaryAbi,
                            "buildId" to Build.ID,
                            "display" to Build.DISPLAY,
                            "fingerprint" to Build.FINGERPRINT
                        )
                        result.success(info)
                    } catch (e: Exception) {
                        result.error("DEVICE_INFO_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    data class NalUnit(val offset: Int, val length: Int, val type: Int)

    private fun findAnnexBNalUnits(bytes: ByteArray, size: Int): List<NalUnit> {
        val nals = ArrayList<NalUnit>()
        var i = 0
        var currentStart = -1

        while (i <= size - 4) {
            val is4Byte = bytes[i] == 0.toByte() && bytes[i + 1] == 0.toByte() && bytes[i + 2] == 0.toByte() && bytes[i + 3] == 1.toByte()
            val is3Byte = !is4Byte && bytes[i] == 0.toByte() && bytes[i + 1] == 0.toByte() && bytes[i + 2] == 1.toByte()

            if (is4Byte || is3Byte) {
                val prefixLen = if (is4Byte) 4 else 3
                if (currentStart != -1) {
                    val nalLen = i - currentStart
                    if (nalLen > 0) {
                        val type = (bytes[currentStart].toInt() and 0x1F)
                        nals.add(NalUnit(currentStart, nalLen, type))
                    }
                }
                currentStart = i + prefixLen
                i += prefixLen
            } else {
                i++
            }
        }
        if (currentStart != -1 && currentStart < size) {
            val nalLen = size - currentStart
            val type = (bytes[currentStart].toInt() and 0x1F)
            nals.add(NalUnit(currentStart, nalLen, type))
        }
        return nals
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
            val isVideoTrack = HashMap<Int, Boolean>()
            val isAnnexBVideo = HashMap<Int, Boolean>()
            val isAacAudio = HashMap<Int, Boolean>()
            var bufferSize = 2 * 1024 * 1024

            for (i in 0 until trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""

                if (mime.startsWith("video/")) {
                    isVideoTrack[i] = true
                    // If video format lacks csd-0 (e.g. from MPEG-TS), scan for SPS (type 7) and PPS (type 8)
                    if (!format.containsKey("csd-0") && mime.contains("avc")) {
                        val scanBuf = ByteBuffer.allocateDirect(1024 * 1024)
                        var foundSps: ByteArray? = null
                        var foundPps: ByteArray? = null
                        extractor.selectTrack(i)
                        extractor.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC)

                        for (scan in 0 until 80) {
                            val sz = extractor.readSampleData(scanBuf, 0)
                            if (sz <= 0) break
                            if (extractor.sampleTrackIndex == i) {
                                val bytes = ByteArray(sz)
                                scanBuf.position(0)
                                scanBuf.get(bytes, 0, sz)
                                val nals = findAnnexBNalUnits(bytes, sz)
                                for (nal in nals) {
                                    if (nal.type == 7 && foundSps == null) {
                                        foundSps = ByteArray(nal.length + 4)
                                        foundSps[0] = 0; foundSps[1] = 0; foundSps[2] = 0; foundSps[3] = 1
                                        System.arraycopy(bytes, nal.offset, foundSps, 4, nal.length)
                                    } else if (nal.type == 8 && foundPps == null) {
                                        foundPps = ByteArray(nal.length + 4)
                                        foundPps[0] = 0; foundPps[1] = 0; foundPps[2] = 0; foundPps[3] = 1
                                        System.arraycopy(bytes, nal.offset, foundPps, 4, nal.length)
                                    }
                                }
                                if (foundSps != null && foundPps != null) break
                            }
                            extractor.advance()
                        }

                        if (foundSps != null && foundPps != null) {
                            format.setByteBuffer("csd-0", ByteBuffer.wrap(foundSps))
                            format.setByteBuffer("csd-1", ByteBuffer.wrap(foundPps))
                            isAnnexBVideo[i] = true
                        }
                    }

                    try {
                        extractor.selectTrack(i)
                        val newTrackIndex = muxer.addTrack(format)
                        trackIndexMap[i] = newTrackIndex
                    } catch (trackEx: Exception) {
                        android.util.Log.w("Voidflix", "Video track rejected by muxer: ${trackEx.message}")
                        extractor.unselectTrack(i)
                    }
                } else if (mime.startsWith("audio/")) {
                    isVideoTrack[i] = false
                    if (mime.contains("mp4a") || mime.contains("aac")) {
                        isAacAudio[i] = true
                        // Supply AudioSpecificConfig if missing
                        if (!format.containsKey("csd-0")) {
                            val sampleRate = if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) format.getInteger(MediaFormat.KEY_SAMPLE_RATE) else 44100
                            val channelCount = if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) else 2
                            val freqIdx = when (sampleRate) {
                                96000 -> 0; 88200 -> 1; 64000 -> 2; 48000 -> 3; 44100 -> 4; 32000 -> 5
                                24000 -> 6; 22050 -> 7; 16000 -> 8; 12000 -> 9; 11025 -> 10; 8000 -> 11; else -> 4
                            }
                            val asc = ByteArray(2)
                            asc[0] = ((2 shl 3) or (freqIdx shr 1)).toByte()
                            asc[1] = (((freqIdx and 1) shl 7) or (channelCount shl 3)).toByte()
                            format.setByteBuffer("csd-0", ByteBuffer.wrap(asc))
                        }
                    }

                    try {
                        extractor.selectTrack(i)
                        val newTrackIndex = muxer.addTrack(format)
                        trackIndexMap[i] = newTrackIndex
                    } catch (trackEx: Exception) {
                        android.util.Log.w("Voidflix", "Audio track rejected by muxer: ${trackEx.message}")
                        extractor.unselectTrack(i)
                    }
                }
            }

            if (trackIndexMap.isEmpty()) return false
            muxer.start()

            val startUs = startMs * 1000L
            val endUs = endMs * 1000L
            val durationUs = (endMs - startMs).coerceAtLeast(1000L) * 1000L

            if (!isPreTrimmed) {
                extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            } else {
                extractor.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
            }

            val readBuffer = ByteBuffer.allocateDirect(bufferSize)
            val writeBuffer = ByteBuffer.allocateDirect(bufferSize + 65536)
            val bufferInfo = MediaCodec.BufferInfo()
            val trackBaseUs = HashMap<Int, Long>()
            val trackLastPts = HashMap<Int, Long>()
            var videoKeyframeSeen = false
            var samplesWritten = 0

            while (true) {
                val sampleSize = extractor.readSampleData(readBuffer, 0)
                if (sampleSize <= 0) break

                val sampleTimeUs = extractor.sampleTime
                if (sampleTimeUs < 0) {
                    extractor.advance()
                    continue
                }

                val trackIndex = extractor.sampleTrackIndex
                if (!trackIndexMap.containsKey(trackIndex)) {
                    extractor.advance()
                    continue
                }

                val isVideo = isVideoTrack[trackIndex] == true
                val isSyncFrame = (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0

                // If trimming from an untrimmed source, ensure video starts at a sync frame
                if (isVideo && !videoKeyframeSeen) {
                    if (!isSyncFrame) {
                        extractor.advance()
                        continue
                    }
                    videoKeyframeSeen = true
                }

                // Check end bounds
                if (isPreTrimmed) {
                    val base = trackBaseUs[trackIndex] ?: sampleTimeUs
                    if ((sampleTimeUs - base) > durationUs + 2000000L) {
                        break
                    }
                } else {
                    if (sampleTimeUs > endUs) {
                        break
                    }
                }

                // Initialize monotonic timestamp base per track
                val base = trackBaseUs.getOrPut(trackIndex) { sampleTimeUs }
                val rawPts = (sampleTimeUs - base).coerceAtLeast(0L)
                val lastPts = trackLastPts[trackIndex] ?: -1L
                val pts = if (rawPts > lastPts) rawPts else lastPts + 1000L
                trackLastPts[trackIndex] = pts

                val rawBytes = ByteArray(sampleSize)
                readBuffer.position(0)
                readBuffer.get(rawBytes, 0, sampleSize)

                writeBuffer.clear()

                if (isVideo) {
                    // Check if sample has Annex-B start codes
                    val hasAnnexB = sampleSize >= 4 && (
                        (rawBytes[0] == 0.toByte() && rawBytes[1] == 0.toByte() && rawBytes[2] == 0.toByte() && rawBytes[3] == 1.toByte()) ||
                        (rawBytes[0] == 0.toByte() && rawBytes[1] == 0.toByte() && rawBytes[2] == 1.toByte())
                    )

                    if (hasAnnexB || isAnnexBVideo[trackIndex] == true) {
                        // Convert Annex-B to AVCC (4-byte length prefixes)
                        val nals = findAnnexBNalUnits(rawBytes, sampleSize)
                        for (nal in nals) {
                            writeBuffer.putInt(nal.length)
                            writeBuffer.put(rawBytes, nal.offset, nal.length)
                        }
                    } else {
                        writeBuffer.put(rawBytes, 0, sampleSize)
                    }
                } else {
                    // Audio: check for 7-byte ADTS header and strip it for standard MP4
                    if (isAacAudio[trackIndex] == true && sampleSize > 7 &&
                        rawBytes[0] == 0xFF.toByte() && (rawBytes[1].toInt() and 0xF6) == 0xF0) {
                        writeBuffer.put(rawBytes, 7, sampleSize - 7)
                    } else {
                        writeBuffer.put(rawBytes, 0, sampleSize)
                    }
                }

                writeBuffer.flip()
                bufferInfo.offset = 0
                bufferInfo.size = writeBuffer.remaining()
                bufferInfo.presentationTimeUs = pts
                bufferInfo.flags = extractor.sampleFlags

                try {
                    muxer.writeSampleData(trackIndexMap[trackIndex]!!, writeBuffer, bufferInfo)
                    samplesWritten++
                } catch (writeEx: Exception) {
                    android.util.Log.w("Voidflix", "Sample write error on track $trackIndex: ${writeEx.message}")
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
