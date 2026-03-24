package com.example.expense_tracker_app

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "expense_tracker_app/media_store",
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val bytes = call.argument<ByteArray>("bytes")
            val filename = call.argument<String>("filename")
            val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

            if (bytes == null || filename.isNullOrBlank()) {
                result.error("invalid_args", "Missing file payload.", null)
                return@setMethodCallHandler
            }

            try {
                val savedUri = saveFileToMediaStore(
                    bytes = bytes,
                    filename = filename,
                    mimeType = mimeType,
                )
                result.success(savedUri.toString())
            } catch (error: Exception) {
                result.error("save_failed", error.message, null)
            }
        }
    }

    private fun saveFileToMediaStore(
        bytes: ByteArray,
        filename: String,
        mimeType: String,
    ) = applicationContext.contentResolver.run {
        val isImage = mimeType.lowercase().startsWith("image/")
        val collection = if (isImage) {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Downloads.EXTERNAL_CONTENT_URI
        }
        val relativePath = if (isImage) {
            "${Environment.DIRECTORY_PICTURES}/Expense Tracker"
        } else {
            "${Environment.DIRECTORY_DOWNLOADS}/Expense Tracker"
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val uri = insert(collection, values)
            ?: throw IOException("Unable to create media entry.")
        try {
            openOutputStream(uri)?.use { output ->
                output.write(bytes)
                output.flush()
            } ?: throw IOException("Unable to open media output stream.")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val finalizeValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                update(uri, finalizeValues, null, null)
            }
            uri
        } catch (error: Exception) {
            delete(uri, null, null)
            throw error
        }
    }
}
