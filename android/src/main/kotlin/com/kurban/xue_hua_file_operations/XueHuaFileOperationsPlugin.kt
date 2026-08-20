package com.kurban.xue_hua_file_operations

import android.Manifest
import android.content.ActivityNotFoundException
import android.app.Activity
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.net.toUri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.FileOutputStream
import kotlin.concurrent.thread

class XueHuaFileOperationsPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {

    private lateinit var channel: MethodChannel
    private var applicationContext: Context? = null
    private var activity: Activity? = null
    private var pendingResult: Result? = null
    private var pendingWithData: Boolean = false
    private var pendingMaxFiles: Int? = null
    private var pendingSaveBytes: ByteArray? = null
    private var pendingSaveSourcePath: String? = null
    private var pendingSaveFileName: String = "file"
    private var pendingGalleryRequest: GalleryRequest? = null
    private var pendingPermissionOnly: Boolean = false
    private var pendingSingleAsMultiple: Boolean = false
    private var openDocumentLauncher: ActivityResultLauncher<Array<String>>? = null
    private var openMultipleDocumentsLauncher: ActivityResultLauncher<Array<String>>? = null
    private var openDocumentTreeLauncher: ActivityResultLauncher<Uri?>? = null
    private var createDocumentLauncher: ActivityResultLauncher<Pair<String, String>>? = null
    private var writeStoragePermissionLauncher: ActivityResultLauncher<String>? = null
    private var pickVisualMediaLauncher: ActivityResultLauncher<PickVisualMediaRequest>? = null
    private var pickMultipleVisualMediaLauncher:
        ActivityResultLauncher<PickVisualMediaRequest>? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private class GalleryRequest(
        val fileName: String,
        val bytes: ByteArray?,
        val sourcePath: String?,
        val type: String,
        val albumName: String?,
    )

    /** CreateDocument with dynamic MIME type + suggested file name. */
    private class CreateDocumentContract :
        ActivityResultContract<Pair<String, String>, Uri?>() {
        override fun createIntent(context: Context, input: Pair<String, String>): Intent {
            return Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = input.first
                putExtra(Intent.EXTRA_TITLE, input.second)
            }
        }

        override fun parseResult(resultCode: Int, intent: Intent?): Uri? {
            return intent?.data?.takeIf { resultCode == Activity.RESULT_OK }
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "xue_hua_file_operations")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "pickFile" -> pickFile(call, result)
            "pickFiles" -> pickFiles(call, result)
            "pickDirectory" -> pickDirectory(result)
            "saveFile" -> saveFile(call, result)
            "saveToGallery" -> saveToGallery(call, result)
            "galleryPermissionStatus" -> result.success(galleryPermissionWireName())
            "requestGalleryPermission" -> requestGalleryPermission(result)
            "openFile" -> openFile(call, result)
            "openAppSettings" -> openAppSettings(result)
            else -> result.notImplemented()
        }
    }

    private fun ensureActivity(result: Result): Activity? {
        val act = activity
        if (act == null) {
            result.error("unknown", "Activity is not available", null)
            return null
        }
        if (pendingResult != null) {
            result.error("invalid_args", "Another file operation is in progress", null)
            return null
        }
        if (openDocumentLauncher == null) {
            result.error(
                "unsupported",
                "Host Activity must extend FlutterFragmentActivity (ComponentActivity) " +
                        "to use file pickers",
                null
            )
            return null
        }
        return act
    }

    private fun mimeTypesFromArgs(call: MethodCall): Array<String> {
        // Merge MIME types and extension-derived MIME types (same as iOS).
        val merged = mutableListOf<String>()
        call.argument<List<String>>("allowedMimeTypes")?.let { merged.addAll(it) }
        call.argument<List<String>>("allowedExtensions")?.forEach { ext ->
            val clean = ext.removePrefix(".")
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(clean)?.let { merged.add(it) }
        }
        if (merged.isNotEmpty()) {
            return merged.distinct().toTypedArray()
        }
        return when (call.argument<String>("type")) {
            "image" -> arrayOf("image/*")
            "video" -> arrayOf("video/*")
            "media" -> arrayOf("image/*", "video/*")
            "audio" -> arrayOf("audio/*")
            else -> arrayOf("*/*")
        }
    }

    /**
     * Returns a Photo Picker request when the call targets media (image /
     * video) without custom MIME / extension filters, otherwise null (SAF).
     */
    private fun photoPickerRequest(call: MethodCall): PickVisualMediaRequest? {
        if (!call.argument<List<String>>("allowedMimeTypes").isNullOrEmpty()) return null
        if (!call.argument<List<String>>("allowedExtensions").isNullOrEmpty()) return null
        val mediaType = when (call.argument<String>("type")) {
            "image" -> ActivityResultContracts.PickVisualMedia.ImageOnly
            "video" -> ActivityResultContracts.PickVisualMedia.VideoOnly
            "media" -> ActivityResultContracts.PickVisualMedia.ImageAndVideo
            else -> return null
        }
        return PickVisualMediaRequest(mediaType)
    }

    private fun pickFile(call: MethodCall, result: Result) {
        ensureActivity(result) ?: return
        val photoRequest = photoPickerRequest(call)
        pendingResult = result
        pendingWithData = call.argument<Boolean>("withData") ?: false
        pendingMaxFiles = null
        if (photoRequest != null) {
            val launcher = pickVisualMediaLauncher
            if (launcher != null) {
                launcher.launch(photoRequest)
                return
            }
        }
        val launcher = openDocumentLauncher ?: run {
            clearPending()
            return
        }
        launcher.launch(mimeTypesFromArgs(call))
    }

    private fun pickFiles(call: MethodCall, result: Result) {
        ensureActivity(result) ?: return
        val photoRequest = photoPickerRequest(call)
        pendingResult = result
        pendingWithData = call.argument<Boolean>("withData") ?: false
        pendingMaxFiles = call.argument<Int>("maxFiles")
        if (photoRequest != null) {
            // Photo Picker enforces maxFiles == 1 via the single-select
            // contract; larger limits are validated after selection.
            if (pendingMaxFiles == 1) {
                val single = pickVisualMediaLauncher
                if (single != null) {
                    pendingSingleAsMultiple = true
                    single.launch(photoRequest)
                    return
                }
            }
            val launcher = pickMultipleVisualMediaLauncher
            if (launcher != null) {
                launcher.launch(photoRequest)
                return
            }
        }
        val launcher = openMultipleDocumentsLauncher ?: run {
            clearPending()
            return
        }
        launcher.launch(mimeTypesFromArgs(call))
    }

    private fun pickDirectory(result: Result) {
        ensureActivity(result) ?: return
        val launcher = openDocumentTreeLauncher ?: return
        pendingResult = result
        launcher.launch(null)
    }

    private fun saveFile(call: MethodCall, result: Result) {
        ensureActivity(result) ?: return
        val launcher = createDocumentLauncher ?: return
        val fileName = call.argument<String>("fileName") ?: "file"
        val bytes = call.argument<ByteArray>("bytes")
        val sourcePath = call.argument<String>("sourcePath")
        if (bytes == null && sourcePath.isNullOrEmpty()) {
            result.error("invalid_args", "Either bytes or sourcePath must be provided", null)
            return
        }

        pendingResult = result
        pendingSaveBytes = bytes
        pendingSaveSourcePath = sourcePath
        pendingSaveFileName = fileName

        val mime = guessMime(fileName, call.argument<List<String>>("allowedExtensions"))
        launcher.launch(mime to fileName)
    }

    private fun saveToGallery(call: MethodCall, result: Result) {
        val fileName = call.argument<String>("fileName") ?: "file"
        val bytes = call.argument<ByteArray>("bytes")
        val sourcePath = call.argument<String>("sourcePath")
        val type = call.argument<String>("type")
        val albumName = call.argument<String>("albumName")

        if (bytes == null && sourcePath.isNullOrEmpty()) {
            result.error("invalid_args", "Either bytes or sourcePath must be provided", null)
            return
        }
        if (type != "image" && type != "video") {
            result.error("invalid_args", "type must be image or video", null)
            return
        }

        val request = GalleryRequest(fileName, bytes, sourcePath, type, albumName)
        if (Build.VERSION.SDK_INT <= 28) {
            val act = activity
            if (act == null) {
                result.error("unknown", "Activity is not available", null)
                return
            }
            val granted = ContextCompat.checkSelfPermission(
                act,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                val launcher = writeStoragePermissionLauncher
                if (launcher == null) {
                    result.error(
                        "unsupported",
                        "Host Activity must extend FlutterFragmentActivity (ComponentActivity) " +
                                "to request storage permission",
                        null
                    )
                    return
                }
                if (pendingResult != null) {
                    result.error("invalid_args", "Another file operation is in progress", null)
                    return
                }
                pendingResult = result
                pendingGalleryRequest = request
                markWriteStorageRequested()
                launcher.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                return
            }
        }

        executeGallerySave(request, result)
    }

    private fun requestGalleryPermission(result: Result) {
        if (Build.VERSION.SDK_INT >= 29) {
            result.success("granted")
            return
        }
        val act = activity
        if (act == null) {
            result.error("unknown", "Activity is not available", null)
            return
        }
        if (ContextCompat.checkSelfPermission(
                act,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success("granted")
            return
        }
        val launcher = writeStoragePermissionLauncher
        if (launcher == null) {
            result.error(
                "unsupported",
                "Host Activity must extend FlutterFragmentActivity (ComponentActivity) " +
                        "to request storage permission",
                null
            )
            return
        }
        if (pendingResult != null) {
            result.error("invalid_args", "Another file operation is in progress", null)
            return
        }
        pendingResult = result
        pendingPermissionOnly = true
        markWriteStorageRequested()
        launcher.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
    }

    private fun galleryPermissionWireName(): String {
        if (Build.VERSION.SDK_INT >= 29) {
            return "granted"
        }
        val ctx = activity ?: applicationContext ?: return "denied"
        val granted = ContextCompat.checkSelfPermission(
            ctx,
            Manifest.permission.WRITE_EXTERNAL_STORAGE
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            return "granted"
        }
        val requested = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_WRITE_STORAGE_REQUESTED, false)
        val act = activity
        val showRationale = act != null &&
            ActivityCompat.shouldShowRequestPermissionRationale(
                act,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
            )
        return if (!requested || showRationale) "denied" else "permanentlyDenied"
    }

    private fun markWriteStorageRequested() {
        val ctx = activity ?: applicationContext ?: return
        ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_WRITE_STORAGE_REQUESTED, true)
            .apply()
    }

    private fun executeGallerySave(request: GalleryRequest, result: Result) {
        val ctx = activity ?: applicationContext
        if (ctx == null) {
            result.error("unknown", "Context is not available", null)
            return
        }
        thread {
            try {
                val saved = GallerySaver(ctx).save(
                    fileName = request.fileName,
                    bytes = request.bytes,
                    sourcePath = request.sourcePath,
                    type = request.type,
                    albumName = request.albumName,
                )
                Handler(Looper.getMainLooper()).post {
                    result.success(
                        mapOf(
                            "name" to saved.name,
                            "path" to saved.path,
                            "identifier" to saved.identifier,
                        )
                    )
                }
            } catch (e: FileNotFoundException) {
                Handler(Looper.getMainLooper()).post {
                    result.error("not_found", e.message, null)
                }
            } catch (e: SecurityException) {
                Handler(Looper.getMainLooper()).post {
                    result.error("permission_denied", e.message, null)
                }
            } catch (e: IllegalArgumentException) {
                Handler(Looper.getMainLooper()).post {
                    result.error("invalid_args", e.message, null)
                }
            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post {
                    result.error("io_error", e.message, null)
                }
            }
        }
    }

    private fun onWriteStoragePermissionResult(granted: Boolean) {
        if (pendingPermissionOnly) {
            val res = pendingResult
            pendingPermissionOnly = false
            pendingResult = null
            res?.success(if (granted) "granted" else galleryPermissionWireName())
            return
        }
        val request = pendingGalleryRequest
        val res = pendingResult
        pendingGalleryRequest = null
        pendingResult = null
        if (res == null || request == null) return
        if (!granted) {
            res.error("permission_denied", "WRITE_EXTERNAL_STORAGE was denied", null)
            return
        }
        executeGallerySave(request, res)
    }

    private fun guessMime(fileName: String, extensions: List<String>?): String {
        val ext = fileName.substringAfterLast('.', "").lowercase()
        if (ext.isNotEmpty()) {
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)?.let { return it }
        }
        val first = extensions?.firstOrNull()?.removePrefix(".")?.lowercase()
        if (!first.isNullOrEmpty()) {
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(first)?.let { return it }
        }
        return "application/octet-stream"
    }

    private fun openAppSettings(result: Result) {
        val context = activity ?: applicationContext
        if (context == null) {
            result.error("unknown", "Context is not available", null)
            return
        }
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", context.packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.error("unsupported", "Unable to open application settings", null)
        }
    }

    private fun openFile(call: MethodCall, result: Result) {
        val act = activity
        if (act == null) {
            result.error("unknown", "Activity is not available", null)
            return
        }
        val path = call.argument<String>("path")
        val identifier = call.argument<String>("identifier")

        if ((path.isNullOrEmpty()) && (identifier.isNullOrEmpty())) {
            result.error("invalid_args", "Either path or identifier must be provided", null)
            return
        }

        var targetFile: File? = null
        if (!path.isNullOrEmpty()) {
            val file = File(path)
            if (file.exists()) {
                targetFile = file
            } else if (identifier.isNullOrEmpty()) {
                result.error("not_found", "File not found: $path", null)
                return
            }
        }

        if (targetFile == null && !identifier.isNullOrEmpty()) {
            when {
                identifier.startsWith("file://") -> {
                    val pathFromUri = identifier.toUri().path
                    if (!pathFromUri.isNullOrEmpty()) {
                        val file = File(pathFromUri)
                        if (file.exists()) {
                            targetFile = file
                        } else {
                            result.error("not_found", "File not found: $pathFromUri", null)
                            return
                        }
                    }
                }
                !identifier.contains("://") -> {
                    val file = File(identifier)
                    if (file.exists()) {
                        targetFile = file
                    } else {
                        result.error("not_found", "File not found: $identifier", null)
                        return
                    }
                }
            }
        }

        val uri: Uri = when {
            targetFile != null -> {
                try {
                    FileProvider.getUriForFile(
                        act,
                        "${act.packageName}.xue_hua_file_operations.fileprovider",
                        targetFile
                    )
                } catch (e: Exception) {
                    result.error(
                        "io_error",
                        "Unable to share file via FileProvider: ${e.message}",
                        null
                    )
                    return
                }
            }
            !identifier.isNullOrEmpty() && identifier.contains("://") -> {
                // content:// (or other non-file schemes) — open directly
                identifier.toUri()
            }
            else -> {
                result.error("not_found", "File not found: ${path ?: identifier}", null)
                return
            }
        }

        if (uri.scheme == "file") {
            result.error(
                "io_error",
                "file:// URIs cannot be shared with other apps; use a local path",
                null
            )
            return
        }

        var mime: String? = null
        try {
            mime = act.contentResolver.getType(uri)
        } catch (_: Exception) {
        }

        if (mime.isNullOrEmpty() || mime == "*/*" || mime == "application/octet-stream") {
            val name = targetFile?.name
                ?: path?.substringAfterLast('/')
                ?: uri.lastPathSegment?.substringAfterLast('/')
                ?: ""
            val ext = name.substringAfterLast('.', "").lowercase()
            if (ext.isNotEmpty()) {
                val guessed = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
                if (!guessed.isNullOrEmpty()) {
                    mime = guessed
                }
            }
        }

        val finalMime = mime.takeIf { !it.isNullOrEmpty() } ?: "*/*"

        try {
            act.startActivity(buildViewChooser(act, uri, finalMime))
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            if (finalMime != "*/*") {
                try {
                    act.startActivity(buildViewChooser(act, uri, "*/*"))
                    result.success(true)
                    return
                } catch (_: Exception) {
                }
            }
            result.error("io_error", "Unable to open file: ${e.message}", null)
        } catch (e: Exception) {
            result.error("io_error", "Unable to open file: ${e.message}", null)
        }
    }

    private fun buildViewChooser(act: Activity, uri: Uri, mime: String): Intent {
        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            clipData = ClipData.newUri(act.contentResolver, "open_file", uri)
        }
        return Intent.createChooser(viewIntent, null).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            clipData = viewIntent.clipData
        }
    }

    private fun onOpenDocumentResult(uri: Uri?) {
        val result = pendingResult ?: return
        val withData = pendingWithData
        val asMultiple = pendingSingleAsMultiple
        val ctx: Context? = activity ?: applicationContext
        clearPending()
        if (uri == null) {
            result.success(null)
            return
        }
        if (ctx == null) {
            result.error("unknown", "Context is not available", null)
            return
        }
        thread {
            try {
                val map = uriToMap(ctx, uri, withData)
                mainHandler.post {
                    if (asMultiple) {
                        result.success(mapOf("files" to listOf(map)))
                    } else {
                        result.success(mapOf("file" to map))
                    }
                }
            } catch (e: Exception) {
                mainHandler.post { result.error("io_error", e.message, null) }
            }
        }
    }

    private fun onOpenMultipleDocumentsResult(uris: List<Uri>) {
        val result = pendingResult ?: return
        val withData = pendingWithData
        val max = pendingMaxFiles
        val ctx: Context? = activity ?: applicationContext
        clearPending()
        if (uris.isEmpty()) {
            result.success(null)
            return
        }
        if (max != null && uris.size > max) {
            result.error(
                "too_many_files",
                "Selected ${uris.size} files but maxFiles is $max",
                mapOf("selected" to uris.size, "maxFiles" to max)
            )
            return
        }
        if (ctx == null) {
            result.error("unknown", "Context is not available", null)
            return
        }
        thread {
            try {
                val files = uris.map { uriToMap(ctx, it, withData) }
                mainHandler.post { result.success(mapOf("files" to files)) }
            } catch (e: Exception) {
                mainHandler.post { result.error("io_error", e.message, null) }
            }
        }
    }

    private fun onOpenDocumentTreeResult(uri: Uri?) {
        val result = pendingResult ?: return
        try {
            if (uri == null) {
                result.success(null)
            } else {
                try {
                    activity?.contentResolver?.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                } catch (_: Exception) {
                }
                val name = uri.lastPathSegment ?: "directory"
                result.success(
                    mapOf(
                        "path" to uri.toString(),
                        "name" to name,
                        "identifier" to uri.toString()
                    )
                )
            }
        } catch (e: Exception) {
            result.error("io_error", e.message, null)
        } finally {
            clearPending()
        }
    }

    private fun onCreateDocumentResult(uri: Uri?) {
        val result = pendingResult ?: return
        val bytes = pendingSaveBytes
        val sourcePath = pendingSaveSourcePath
        val fileName = pendingSaveFileName
        val ctx: Context? = activity ?: applicationContext
        clearPending()
        if (uri == null) {
            result.success(null)
            return
        }
        if (ctx == null) {
            result.error("unknown", "Context is not available", null)
            return
        }
        thread {
            try {
                writeToUri(ctx, uri, bytes, sourcePath)
                mainHandler.post {
                    result.success(
                        mapOf(
                            "path" to uri.toString(),
                            "name" to fileName
                        )
                    )
                }
            } catch (e: FileNotFoundException) {
                mainHandler.post { result.error("not_found", e.message, null) }
            } catch (e: Exception) {
                mainHandler.post { result.error("io_error", e.message, null) }
            }
        }
    }

    private fun writeToUri(ctx: Context, uri: Uri, bytes: ByteArray?, sourcePath: String?) {
        ctx.contentResolver.openOutputStream(uri)?.use { out ->
            if (bytes != null) {
                out.write(bytes)
            } else {
                val source = sourcePath
                    ?: throw IllegalArgumentException("sourcePath missing")
                val sourceFile = File(source)
                if (!sourceFile.exists()) {
                    throw FileNotFoundException("File not found: $source")
                }
                FileInputStream(sourceFile).use { input ->
                    input.copyTo(out)
                }
            }
        } ?: throw IllegalStateException("Unable to open output stream")
    }

    private fun uriToMap(ctx: Context, uri: Uri, withData: Boolean): Map<String, Any?> {
        val resolver = ctx.contentResolver
        var name = uri.lastPathSegment ?: "file"
        var size = 0L

        resolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (cursor.moveToFirst()) {
                if (nameIndex >= 0) name = cursor.getString(nameIndex) ?: name
                if (sizeIndex >= 0) size = cursor.getLong(sizeIndex)
            }
        }

        val cacheFile = copyToCache(ctx, uri, name)
        val bytes: ByteArray? = if (withData) {
            cacheFile.readBytes()
        } else {
            null
        }
        if (!withData && size <= 0) {
            size = cacheFile.length()
        } else if (withData && size <= 0) {
            size = bytes?.size?.toLong() ?: cacheFile.length()
        }

        return mapOf(
            "name" to name,
            "size" to size,
            "path" to cacheFile.absolutePath,
            "bytes" to bytes,
            "identifier" to uri.toString()
        )
    }

    private fun copyToCache(ctx: Context, uri: Uri, name: String): File {
        val dir = File(ctx.cacheDir, "xue_hua_file_operations")
        if (!dir.exists()) dir.mkdirs()
        val safeName = name.replace(Regex("[\\\\/]+"), "_")
        val outFile = File(dir, "${System.currentTimeMillis()}_$safeName")
        ctx.contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(outFile).use { output ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Unable to open input stream")
        return outFile
    }

    private fun clearPending() {
        pendingResult = null
        pendingWithData = false
        pendingMaxFiles = null
        pendingSaveBytes = null
        pendingSaveSourcePath = null
        pendingSaveFileName = "file"
        pendingGalleryRequest = null
        pendingPermissionOnly = false
        pendingSingleAsMultiple = false
    }

    private fun registerLaunchers(componentActivity: ComponentActivity) {
        unregisterLaunchers()
        val registry = componentActivity.activityResultRegistry
        openDocumentLauncher = registry.register(
            "xue_hua_file_operations/open_document",
            ActivityResultContracts.OpenDocument()
        ) { uri -> onOpenDocumentResult(uri) }
        openMultipleDocumentsLauncher = registry.register(
            "xue_hua_file_operations/open_multiple_documents",
            ActivityResultContracts.OpenMultipleDocuments()
        ) { uris -> onOpenMultipleDocumentsResult(uris) }
        openDocumentTreeLauncher = registry.register(
            "xue_hua_file_operations/open_document_tree",
            ActivityResultContracts.OpenDocumentTree()
        ) { uri -> onOpenDocumentTreeResult(uri) }
        createDocumentLauncher = registry.register(
            "xue_hua_file_operations/create_document",
            CreateDocumentContract()
        ) { uri -> onCreateDocumentResult(uri) }
        writeStoragePermissionLauncher = registry.register(
            "xue_hua_file_operations/write_storage_permission",
            ActivityResultContracts.RequestPermission()
        ) { granted -> onWriteStoragePermissionResult(granted) }
        pickVisualMediaLauncher = registry.register(
            "xue_hua_file_operations/pick_visual_media",
            ActivityResultContracts.PickVisualMedia()
        ) { uri -> onOpenDocumentResult(uri) }
        pickMultipleVisualMediaLauncher = registry.register(
            "xue_hua_file_operations/pick_multiple_visual_media",
            ActivityResultContracts.PickMultipleVisualMedia()
        ) { uris -> onOpenMultipleDocumentsResult(uris) }
    }

    private fun unregisterLaunchers() {
        openDocumentLauncher?.unregister()
        openMultipleDocumentsLauncher?.unregister()
        openDocumentTreeLauncher?.unregister()
        createDocumentLauncher?.unregister()
        writeStoragePermissionLauncher?.unregister()
        pickVisualMediaLauncher?.unregister()
        pickMultipleVisualMediaLauncher?.unregister()
        openDocumentLauncher = null
        openMultipleDocumentsLauncher = null
        openDocumentTreeLauncher = null
        createDocumentLauncher = null
        writeStoragePermissionLauncher = null
        pickVisualMediaLauncher = null
        pickMultipleVisualMediaLauncher = null
    }

    /** Fails any in-flight operation so the Dart Future never hangs. */
    private fun failPendingOnDetach() {
        val result = pendingResult ?: return
        clearPending()
        result.error("cancelled", "Activity was detached during the operation", null)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        applicationContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        val componentActivity = binding.activity as? ComponentActivity
        if (componentActivity != null) {
            registerLaunchers(componentActivity)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        failPendingOnDetach()
        unregisterLaunchers()
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        failPendingOnDetach()
        unregisterLaunchers()
        activity = null
    }

    companion object {
        private const val PREFS_NAME = "xue_hua_file_operations"
        private const val KEY_WRITE_STORAGE_REQUESTED = "write_external_storage_requested"
    }
}
