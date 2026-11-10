package com.example.fc_tuning_studio

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * One-click save into public Downloads/FC_Tuning (visible in Files app).
 * Uses MediaStore on API 29+; direct file write on older APIs.
 */
class DownloadsBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> {
                    try {
                        val name = call.argument<String>("fileName")
                            ?: throw IllegalArgumentException("fileName required")
                        val bytes = call.argument<ByteArray>("bytes")
                            ?: throw IllegalArgumentException("bytes required")
                        val path = saveToDownloads(name, bytes)
                        result.success(path)
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
    }

    private fun saveToDownloads(rawName: String, bytes: ByteArray): String {
        val fileName = sanitizeName(rawName)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(fileName, bytes)
        } else {
            saveViaLegacyFile(fileName, bytes)
        }
    }

    private fun saveViaMediaStore(fileName: String, bytes: ByteArray): String {
        val mime = when {
            fileName.lowercase().endsWith(".csv") -> "text/csv"
            fileName.lowercase().endsWith(".txt") -> "text/plain"
            else -> "application/octet-stream"
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(
                MediaStore.MediaColumns.RELATIVE_PATH,
                Environment.DIRECTORY_DOWNLOADS + "/FC_Tuning",
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore insert failed")
        resolver.openOutputStream(uri)?.use { it.write(bytes) }
            ?: throw IllegalStateException("Cannot open MediaStore stream")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }
        return "Download/FC_Tuning/$fileName"
    }

    @Suppress("DEPRECATION")
    private fun saveViaLegacyFile(fileName: String, bytes: ByteArray): String {
        val root = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS,
        )
        val dir = File(root, "FC_Tuning")
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("Cannot create ${dir.absolutePath}")
        }
        val out = File(dir, fileName)
        FileOutputStream(out).use { it.write(bytes) }
        return out.absolutePath
    }

    private fun sanitizeName(raw: String): String {
        var name = raw.replace(Regex("[^A-Za-z0-9._-]"), "_")
        if (name.isBlank()) name = "LOG.csv"
        return name
    }

    companion object {
        const val CHANNEL = "fc_tuning_studio/downloads"
    }
}
