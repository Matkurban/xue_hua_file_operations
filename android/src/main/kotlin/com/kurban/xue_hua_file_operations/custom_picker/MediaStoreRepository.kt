package com.kurban.xue_hua_file_operations.custom_picker

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.LruCache
import android.util.Size
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Queries albums and media items from Android [MediaStore] and manages an
 * in-memory LRU thumbnail cache for smooth grid scrolling.
 * 负责从 Android [MediaStore] 查询相册与媒体列表，并维护内存 LRU 缩略图缓存以保证流畅滚动。
 */
class MediaStoreRepository(private val context: Context) {

    private val thumbnailExecutor: ExecutorService = Executors.newFixedThreadPool(4)

    // Use up to 1/8 of available VM memory (capped at 32 MB) for thumbnails.
    // 分配最多 1/8 可用内存（上限 32 MB）用于缩略图 LRU 缓存。
    private val cacheSizeKb: Int =
        ((Runtime.getRuntime().maxMemory() / 1024L) / 8L).toInt().coerceIn(4096, 32768)

    private val thumbnailCache = object : LruCache<String, Bitmap>(cacheSizeKb) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount / 1024
    }

    /**
     * Loads all matching media items and builds virtual + device albums.
     * 加载符合类型条件的全部媒体项，并构建虚拟聚合相册与设备相册列表。
     */
    fun loadMediaAndAlbums(
        mediaType: String,
        strings: CustomMediaPickerStrings,
    ): Pair<List<MediaAlbum>, Map<String, List<MediaItem>>> {
        val allItems = queryItems(mediaType)
        val bucketItems = LinkedHashMap<String, MutableList<MediaItem>>()
        val bucketNames = HashMap<String, String>()
        val videoItems = ArrayList<MediaItem>()

        for (item in allItems) {
            if (item.isVideo) {
                videoItems.add(item)
            }
            val list = bucketItems.getOrPut(item.bucketId) { ArrayList() }
            list.add(item)
            bucketNames.putIfAbsent(item.bucketId, item.bucketName)
        }

        val albums = ArrayList<MediaAlbum>()
        val itemsByAlbum = HashMap<String, List<MediaItem>>()

        // 1. Virtual "All Media" album / 虚拟“所有媒体”相册
        albums.add(
            MediaAlbum(
                id = MediaAlbum.ID_ALL_MEDIA,
                name = strings.allMedia,
                count = allItems.size,
                coverUri = allItems.firstOrNull()?.uri,
                isAllMedia = true,
            )
        )
        itemsByAlbum[MediaAlbum.ID_ALL_MEDIA] = allItems

        // 2. Virtual "All Videos" album (when picking both images & videos)
        // 虚拟“所有视频”相册（仅在混合选择模式下且存在视频时显示）
        if (mediaType == "media" && videoItems.isNotEmpty()) {
            albums.add(
                MediaAlbum(
                    id = MediaAlbum.ID_ALL_VIDEOS,
                    name = strings.allVideos,
                    count = videoItems.size,
                    coverUri = videoItems.firstOrNull()?.uri,
                    isAllVideos = true,
                )
            )
            itemsByAlbum[MediaAlbum.ID_ALL_VIDEOS] = videoItems
        }

        // 3. Real device albums sorted by item count descending
        // 设备真实相册（按媒体数量降序排列）
        val sortedBuckets = bucketItems.entries.sortedByDescending { it.value.size }
        for ((bucketId, list) in sortedBuckets) {
            albums.add(
                MediaAlbum(
                    id = bucketId,
                    name = bucketNames[bucketId] ?: "Album",
                    count = list.size,
                    coverUri = list.firstOrNull()?.uri,
                )
            )
            itemsByAlbum[bucketId] = list
        }

        return albums to itemsByAlbum
    }

    private fun queryItems(mediaType: String): List<MediaItem> {
        val collection = MediaStore.Files.getContentUri("external")
        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.MEDIA_TYPE,
            MediaStore.Files.FileColumns.DISPLAY_NAME,
            MediaStore.Files.FileColumns.MIME_TYPE,
            MediaStore.Files.FileColumns.DATE_ADDED,
            MediaStore.Files.FileColumns.SIZE,
            MediaStore.MediaColumns.DURATION,
            MediaStore.Images.Media.BUCKET_ID,
            MediaStore.Images.Media.BUCKET_DISPLAY_NAME,
        )

        val selection = when (mediaType) {
            "image" -> "${MediaStore.Files.FileColumns.MEDIA_TYPE} = ${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE}"
            "video" -> "${MediaStore.Files.FileColumns.MEDIA_TYPE} = ${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO}"
            else -> "(${MediaStore.Files.FileColumns.MEDIA_TYPE} = ${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE} OR " +
                    "${MediaStore.Files.FileColumns.MEDIA_TYPE} = ${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO})"
        }

        val sortOrder =
            "${MediaStore.Files.FileColumns.DATE_ADDED} DESC, ${MediaStore.Files.FileColumns._ID} DESC"
        val items = ArrayList<MediaItem>()

        context.contentResolver.query(collection, projection, selection, null, sortOrder)
            ?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
                val typeCol = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MEDIA_TYPE)
                val nameCol = cursor.getColumnIndex(MediaStore.Files.FileColumns.DISPLAY_NAME)
                val mimeCol = cursor.getColumnIndex(MediaStore.Files.FileColumns.MIME_TYPE)
                val dateCol = cursor.getColumnIndex(MediaStore.Files.FileColumns.DATE_ADDED)
                val sizeCol = cursor.getColumnIndex(MediaStore.Files.FileColumns.SIZE)
                val durationCol = cursor.getColumnIndex(MediaStore.MediaColumns.DURATION)
                val bucketIdCol = cursor.getColumnIndex(MediaStore.Images.Media.BUCKET_ID)
                val bucketNameCol =
                    cursor.getColumnIndex(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)

                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idCol)
                    val type = cursor.getInt(typeCol)
                    val isVideo = type == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
                    val contentUri = ContentUris.withAppendedId(
                        if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                        else MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        id
                    )
                    val name =
                        if (nameCol >= 0) cursor.getString(nameCol) ?: "media_$id" else "media_$id"
                    val mime = if (mimeCol >= 0) cursor.getString(mimeCol) ?: "" else ""
                    val dateAdded = if (dateCol >= 0) cursor.getLong(dateCol) else 0L
                    val size = if (sizeCol >= 0) cursor.getLong(sizeCol) else 0L
                    val duration =
                        if (isVideo && durationCol >= 0) cursor.getLong(durationCol) else 0L
                    val bucketId =
                        if (bucketIdCol >= 0) cursor.getString(bucketIdCol) ?: "other" else "other"
                    val bucketName = if (bucketNameCol >= 0) cursor.getString(bucketNameCol)
                        ?: "Other" else "Other"

                    items.add(
                        MediaItem(
                            id = id,
                            uri = contentUri,
                            displayName = name,
                            mimeType = mime,
                            isVideo = isVideo,
                            durationMs = duration,
                            dateAddedSec = dateAdded,
                            bucketId = bucketId,
                            bucketName = bucketName,
                            size = size,
                        )
                    )
                }
            }
        return items
    }

    /**
     * Loads a thumbnail bitmap asynchronously with LRU caching.
     * 异步加载缩略图 Bitmap 并使用内存 LRU 缓存。
     */
    fun loadThumbnail(
        uri: Uri,
        sizePx: Int,
        isVideo: Boolean,
        onLoaded: (Bitmap?) -> Unit,
    ) {
        val key = "${uri}_${sizePx}"
        thumbnailCache.get(key)?.let { cached ->
            if (!cached.isRecycled) {
                onLoaded(cached)
                return
            }
        }
        thumbnailExecutor.execute {
            val bmp = decodeThumbnail(uri, sizePx, isVideo)
            if (bmp != null) {
                thumbnailCache.put(key, bmp)
            }
            onLoaded(bmp)
        }
    }

    /**
     * Loads a higher-resolution preview bitmap for the full-screen preview page.
     * 为全屏预览页加载较高分辨率的图片 Bitmap。
     */
    fun loadPreviewBitmap(
        uri: Uri,
        maxDimensionPx: Int,
        isVideo: Boolean,
        onLoaded: (Bitmap?) -> Unit,
    ) {
        thumbnailExecutor.execute {
            val bmp = if (isVideo) {
                decodeThumbnail(uri, maxDimensionPx.coerceAtMost(1080), isVideo = true)
            } else {
                decodeSampledImage(uri, maxDimensionPx)
            }
            onLoaded(bmp)
        }
    }

    private fun decodeThumbnail(uri: Uri, sizePx: Int, isVideo: Boolean): Bitmap? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                context.contentResolver.loadThumbnail(uri, Size(sizePx, sizePx), null)
            } else if (isVideo) {
                val id = ContentUris.parseId(uri)
                @Suppress("DEPRECATION")
                MediaStore.Video.Thumbnails.getThumbnail(
                    context.contentResolver,
                    id,
                    MediaStore.Video.Thumbnails.MINI_KIND,
                    null
                )
            } else {
                decodeSampledImage(uri, sizePx)
            }
        } catch (_: Exception) {
            if (!isVideo) decodeSampledImage(uri, sizePx) else null
        }
    }

    private fun decodeSampledImage(uri: Uri, maxDim: Int): Bitmap? {
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, bounds)
            }
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            var inSample = 1
            while (bounds.outWidth / inSample > maxDim * 2 || bounds.outHeight / inSample > maxDim * 2) {
                inSample *= 2
            }
            val opts = BitmapFactory.Options().apply { inSampleSize = inSample }
            val decoded = context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, opts)
            } ?: return null
            if (decoded.width > maxDim || decoded.height > maxDim) {
                val scale = maxDim.toFloat() / maxOf(decoded.width, decoded.height)
                val targetW = (decoded.width * scale).toInt().coerceAtLeast(1)
                val targetH = (decoded.height * scale).toInt().coerceAtLeast(1)
                ThumbnailUtils.extractThumbnail(
                    decoded,
                    targetW,
                    targetH,
                    ThumbnailUtils.OPTIONS_RECYCLE_INPUT
                )
            } else {
                decoded
            }
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Releases background executor and clears cached bitmaps.
     * 释放后台线程池并清空缓存。
     */
    fun release() {
        thumbnailExecutor.shutdownNow()
        thumbnailCache.evictAll()
    }

    companion object {
        /**
         * Formats video duration in milliseconds to `m:ss` or `h:mm:ss`.
         * 将毫秒级视频时长格式化为 `m:ss` 或 `h:mm:ss`。
         */
        fun formatDuration(durationMs: Long): String {
            val totalSec = (durationMs / 1000L).coerceAtLeast(0L)
            val hours = totalSec / 3600L
            val minutes = (totalSec % 3600L) / 60L
            val seconds = totalSec % 60L
            return if (hours > 0) {
                String.format(Locale.US, "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                String.format(Locale.US, "%d:%02d", minutes, seconds)
            }
        }

        /**
         * Formats a unix timestamp (seconds) into a localized Month + Year label
         * for the fast-scroll floating date bubble (e.g. "十一月 2026" / "November 2026").
         * 将秒级时间戳格式化为本地化的“月份 + 年份”文案，用于快速滚动时的日期浮窗。
         */
        fun formatMonthYear(dateAddedSec: Long): String {
            if (dateAddedSec <= 0L) return ""
            val date = Date(dateAddedSec * 1000L)
            val locale = Locale.getDefault()
            val pattern = if (locale.language.lowercase(Locale.ROOT).startsWith("zh")) {
                "MMMM yyyy"
            } else {
                "MMMM yyyy"
            }
            return SimpleDateFormat(pattern, locale).format(date)
        }
    }
}
