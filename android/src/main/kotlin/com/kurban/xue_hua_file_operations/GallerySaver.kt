package com.kurban.xue_hua_file_operations

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.annotation.RequiresApi
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

internal class GallerySaver(private val context: Context) {
    data class SaveResult(
        val name: String,
        val path: String?,
        val identifier: String?,
    )

    fun save(
        fileName: String,
        bytes: ByteArray?,
        sourcePath: String?,
        type: String,
        albumName: String?,
    ): SaveResult {
        if (bytes == null && sourcePath.isNullOrEmpty()) {
            throw IllegalArgumentException("Either bytes or sourcePath must be provided")
        }
        val isVideo = type == "video"
        val mime = guessMime(fileName, isVideo)
        val safeAlbum = albumName
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.replace(Regex("[\\\\/]+"), "_")

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveWithMediaStore(fileName, bytes, sourcePath, isVideo, mime, safeAlbum)
        } else {
            saveToPublicDirectory(fileName, bytes, sourcePath, isVideo, mime, safeAlbum)
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun saveWithMediaStore(
        fileName: String,
        bytes: ByteArray?,
        sourcePath: String?,
        isVideo: Boolean,
        mime: String,
        albumName: String?,
    ): SaveResult {
        val resolver = context.contentResolver
        val collection = if (isVideo) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
        val relativePath = buildString {
            append(
                if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
            )
            append('/')
            if (!albumName.isNullOrEmpty()) {
                append(albumName)
                append('/')
            }
        }
        val now = System.currentTimeMillis()
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
            put(MediaStore.MediaColumns.DATE_ADDED, now / 1000)
            put(MediaStore.MediaColumns.DATE_MODIFIED, now / 1000)
            put(MediaStore.MediaColumns.DATE_TAKEN, now)
        }

        val uri = resolver.insert(collection, values)
            ?: throw java.io.IOException("MediaStore insert failed")
        try {
            resolver.openOutputStream(uri)?.use { out ->
                copyToStream(out, bytes, sourcePath)
            } ?: throw java.io.IOException("Unable to open output stream")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return SaveResult(name = fileName, path = null, identifier = uri.toString())
    }

    @Suppress("DEPRECATION")
    private fun saveToPublicDirectory(
        fileName: String,
        bytes: ByteArray?,
        sourcePath: String?,
        isVideo: Boolean,
        mime: String,
        albumName: String?,
    ): SaveResult {
        val dirType =
            if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
        val base = Environment.getExternalStoragePublicDirectory(dirType)
        val destDir = if (albumName != null) File(base, albumName) else base
        if (!destDir.exists() && !destDir.mkdirs() && !destDir.isDirectory) {
            throw java.io.IOException("Unable to create directory: ${destDir.absolutePath}")
        }
        val destFile = uniqueFile(destDir, fileName)
        FileOutputStream(destFile).use { out ->
            copyToStream(out, bytes, sourcePath)
        }

        var scannedUri: Uri? = null
        val latch = CountDownLatch(1)
        MediaScannerConnection.scanFile(
            context,
            arrayOf(destFile.absolutePath),
            arrayOf(mime),
        ) { _, uri ->
            scannedUri = uri
            latch.countDown()
        }
        latch.await(15, TimeUnit.SECONDS)

        return SaveResult(
            name = destFile.name,
            path = destFile.absolutePath,
            identifier = scannedUri?.toString() ?: destFile.toURI().toString(),
        )
    }

    private fun copyToStream(out: OutputStream, bytes: ByteArray?, sourcePath: String?) {
        if (bytes != null) {
            out.write(bytes)
            return
        }
        openSource(sourcePath!!).use { input ->
            input.copyTo(out)
        }
    }

    private fun openSource(sourcePath: String): InputStream {
        if (sourcePath.startsWith("content://")) {
            return context.contentResolver.openInputStream(Uri.parse(sourcePath))
                ?: throw FileNotFoundException(sourcePath)
        }
        if (sourcePath.startsWith("file://")) {
            val path = Uri.parse(sourcePath).path
                ?: throw FileNotFoundException(sourcePath)
            val file = File(path)
            if (!file.exists()) throw FileNotFoundException(path)
            return FileInputStream(file)
        }
        val file = File(sourcePath)
        if (!file.exists()) throw FileNotFoundException(sourcePath)
        return FileInputStream(file)
    }

    private fun uniqueFile(dir: File, fileName: String): File {
        val candidate = File(dir, fileName)
        if (!candidate.exists()) return candidate
        val dot = fileName.lastIndexOf('.')
        val stem = if (dot > 0) fileName.substring(0, dot) else fileName
        val ext = if (dot > 0) fileName.substring(dot) else ""
        var i = 1
        while (true) {
            val next = File(dir, "${stem}_$i$ext")
            if (!next.exists()) return next
            i++
        }
    }

    private fun guessMime(fileName: String, isVideo: Boolean): String {
        val ext = fileName.substringAfterLast('.', "").lowercase()
        if (ext.isNotEmpty()) {
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)?.let { return it }
        }
        return if (isVideo) "video/mp4" else "image/jpeg"
    }
}
