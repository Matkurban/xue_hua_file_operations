package com.kurban.xue_hua_file_operations

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/** XueHuaFileOperationsPlugin */
class XueHuaFileOperationsPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var pendingResult: Result? = null
    private var pendingWithData: Boolean = false
    private var pendingMaxFiles: Int? = null
    private var pendingSaveBytes: ByteArray? = null
    private var pendingSaveSourcePath: String? = null
    private var pendingSaveFileName: String = "file"

    private var openDocumentLauncher: ActivityResultLauncher<Array<String>>? = null
    private var openMultipleDocumentsLauncher: ActivityResultLauncher<Array<String>>? = null
    private var openDocumentTreeLauncher: ActivityResultLauncher<Uri?>? = null
    private var createDocumentLauncher: ActivityResultLauncher<Pair<String, String>>? = null

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
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "xue_hua_file_operations")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "pickFile" -> pickFile(call, result)
            "pickFiles" -> pickFiles(call, result)
            "pickDirectory" -> pickDirectory(result)
            "saveFile" -> saveFile(call, result)
            "openFile" -> openFile(call, result)
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
        val mimeTypes = call.argument<List<String>>("allowedMimeTypes")
        if (!mimeTypes.isNullOrEmpty()) {
            return mimeTypes.toTypedArray()
        }
        val extensions = call.argument<List<String>>("allowedExtensions")
        if (!extensions.isNullOrEmpty()) {
            val mapped = extensions.mapNotNull { ext ->
                val clean = ext.removePrefix(".")
                MimeTypeMap.getSingleton().getMimeTypeFromExtension(clean)
            }.distinct()
            if (mapped.isNotEmpty()) return mapped.toTypedArray()
        }
        return when (call.argument<String>("type")) {
            "image" -> arrayOf("image/*")
            "video" -> arrayOf("video/*")
            "audio" -> arrayOf("audio/*")
            else -> arrayOf("*/*")
        }
    }

    private fun pickFile(call: MethodCall, result: Result) {
        ensureActivity(result) ?: return
        val launcher = openDocumentLauncher ?: return
        pendingResult = result
        pendingWithData = call.argument<Boolean>("withData") ?: false
        pendingMaxFiles = null
        launcher.launch(mimeTypesFromArgs(call))
    }

    private fun pickFiles(call: MethodCall, result: Result) {
        ensureActivity(result) ?: return
        val launcher = openMultipleDocumentsLauncher ?: return
        pendingResult = result
        pendingWithData = call.argument<Boolean>("withData") ?: false
        pendingMaxFiles = call.argument<Int>("maxFiles")
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

    private fun openFile(call: MethodCall, result: Result) {
        val act = activity
        if (act == null) {
            result.error("unknown", "Activity is not available", null)
            return
        }
        val path = call.argument<String>("path")
        val identifier = call.argument<String>("identifier")
        val uri = when {
            !identifier.isNullOrEmpty() -> Uri.parse(identifier)
            !path.isNullOrEmpty() -> {
                val file = File(path)
                if (!file.exists()) {
                    result.error("not_found", "File not found: $path", null)
                    return
                }
                try {
                    FileProvider.getUriForFile(
                        act,
                        "${act.packageName}.xue_hua_file_operations.fileprovider",
                        file
                    )
                } catch (_: Exception) {
                    Uri.fromFile(file)
                }
            }
            else -> {
                result.error("invalid_args", "Either path or identifier must be provided", null)
                return
            }
        }

        val mime = act.contentResolver.getType(uri) ?: "*/*"
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            act.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("io_error", "Unable to open file: ${e.message}", null)
        }
    }

    private fun onOpenDocumentResult(uri: Uri?) {
        val result = pendingResult ?: return
        try {
            if (uri == null) {
                result.success(null)
            } else {
                result.success(mapOf("file" to uriToMap(uri, pendingWithData)))
            }
        } catch (e: Exception) {
            result.error("io_error", e.message, null)
        } finally {
            clearPending()
        }
    }

    private fun onOpenMultipleDocumentsResult(uris: List<Uri>) {
        val result = pendingResult ?: return
        try {
            if (uris.isEmpty()) {
                result.success(null)
            } else {
                val max = pendingMaxFiles
                if (max != null && uris.size > max) {
                    result.error(
                        "too_many_files",
                        "Selected ${uris.size} files but maxFiles is $max",
                        mapOf("selected" to uris.size, "maxFiles" to max)
                    )
                } else {
                    val files = uris.map { uriToMap(it, pendingWithData) }
                    result.success(mapOf("files" to files))
                }
            }
        } catch (e: Exception) {
            result.error("io_error", e.message, null)
        } finally {
            clearPending()
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
        try {
            if (uri == null) {
                result.success(null)
            } else {
                writeToUri(uri)
                result.success(
                    mapOf(
                        "path" to uri.toString(),
                        "name" to pendingSaveFileName
                    )
                )
            }
        } catch (e: Exception) {
            result.error("io_error", e.message, null)
        } finally {
            clearPending()
        }
    }

    private fun writeToUri(uri: Uri) {
        val act = activity ?: throw IllegalStateException("No activity")
        act.contentResolver.openOutputStream(uri)?.use { out ->
            val bytes = pendingSaveBytes
            if (bytes != null) {
                out.write(bytes)
            } else {
                val source = pendingSaveSourcePath
                    ?: throw IllegalArgumentException("sourcePath missing")
                FileInputStream(File(source)).use { input ->
                    input.copyTo(out)
                }
            }
        } ?: throw IllegalStateException("Unable to open output stream")
    }

    private fun uriToMap(uri: Uri, withData: Boolean): Map<String, Any?> {
        val act = activity ?: throw IllegalStateException("No activity")
        val resolver = act.contentResolver
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

        val cacheFile = copyToCache(uri, name)
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
            "size" to size.toInt(),
            "path" to cacheFile.absolutePath,
            "bytes" to bytes,
            "identifier" to uri.toString()
        )
    }

    private fun copyToCache(uri: Uri, name: String): File {
        val act = activity ?: throw IllegalStateException("No activity")
        val dir = File(act.cacheDir, "xue_hua_file_operations")
        if (!dir.exists()) dir.mkdirs()
        val safeName = name.replace(Regex("[\\\\/]+"), "_")
        val outFile = File(dir, "${System.currentTimeMillis()}_$safeName")
        act.contentResolver.openInputStream(uri)?.use { input ->
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
    }

    private fun unregisterLaunchers() {
        openDocumentLauncher?.unregister()
        openMultipleDocumentsLauncher?.unregister()
        openDocumentTreeLauncher?.unregister()
        createDocumentLauncher?.unregister()
        openDocumentLauncher = null
        openMultipleDocumentsLauncher = null
        openDocumentTreeLauncher = null
        createDocumentLauncher = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        val componentActivity = binding.activity as? ComponentActivity
        if (componentActivity != null) {
            registerLaunchers(componentActivity)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        unregisterLaunchers()
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        unregisterLaunchers()
        activity = null
    }
}
