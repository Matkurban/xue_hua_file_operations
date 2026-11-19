package com.kurban.xue_hua_file_operations.custom_picker

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.net.Uri
import java.util.Locale

/**
 * Resolved visual theme for the Android custom media picker.
 * Android 自定义媒体选择器的已解析视觉主题。
 */
data class CustomMediaPickerTheme(
    val isDark: Boolean,
    val backgroundColor: Int,
    val surfaceColor: Int,
    val primaryColor: Int,
    val onPrimaryColor: Int,
    val textColor: Int,
    val secondaryTextColor: Int,
    val iconColor: Int,
    val unselectedBadgeBorderColor: Int,
    val unselectedBadgeFillColor: Int,
    val scrimColor: Int,
    val handleColor: Int,
    val dateBubbleBackgroundColor: Int,
    val dateBubbleTextColor: Int,
    val sheetCornerRadiusDp: Float,
    val gridSpacingDp: Float,
) {
    companion object {
        /**
         * Parses a theme map from Flutter and fills omitted fields from the
         * built-in light or dark default palette.
         * 解析来自 Flutter 的主题 Map，并为未传字段填充内置浅色或深色默认配色。
         */
        fun fromMap(context: Context, map: Map<*, *>?): CustomMediaPickerTheme {
            val systemDark = (context.resources.configuration.uiMode and
                    Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
            val isDark = when (map?.get("brightness") as? String) {
                "dark" -> true
                "light" -> false
                else -> systemDark
            }

            fun color(key: String, lightDefault: Int, darkDefault: Int): Int {
                val raw = map?.get(key)
                if (raw is Number) return raw.toInt()
                return if (isDark) darkDefault else lightDefault
            }

            fun dp(key: String, defaultVal: Float): Float {
                val raw = map?.get(key)
                return if (raw is Number) raw.toFloat() else defaultVal
            }

            return CustomMediaPickerTheme(
                isDark = isDark,
                backgroundColor = color("backgroundColor", 0xFFFFFFFF.toInt(), 0xFF1C1C1E.toInt()),
                surfaceColor = color("surfaceColor", 0xF2F3F4F6.toInt(), 0xF22C2C2E.toInt()),
                primaryColor = color("primaryColor", 0xFF2AABEE.toInt(), 0xFF2AABEE.toInt()),
                onPrimaryColor = color("onPrimaryColor", Color.WHITE, Color.WHITE),
                textColor = color("textColor", 0xFF111111.toInt(), 0xFFF5F5F7.toInt()),
                secondaryTextColor = color(
                    "secondaryTextColor",
                    0xFF7A8089.toInt(),
                    0xFF98989F.toInt()
                ),
                iconColor = color("iconColor", 0xFF1A1A1A.toInt(), 0xFFF5F5F7.toInt()),
                unselectedBadgeBorderColor = color(
                    "unselectedBadgeBorderColor",
                    Color.WHITE,
                    Color.WHITE
                ),
                unselectedBadgeFillColor = color(
                    "unselectedBadgeFillColor",
                    0x40000000,
                    0x40000000
                ),
                scrimColor = color("scrimColor", 0x66000000, 0x80000000.toInt()),
                handleColor = color("handleColor", 0x408E8E93, 0x55AEAEB2),
                dateBubbleBackgroundColor = color(
                    "dateBubbleBackgroundColor",
                    0xF2FFFFFF.toInt(),
                    0xF22C2C2E.toInt()
                ),
                dateBubbleTextColor = color(
                    "dateBubbleTextColor",
                    0xFF111111.toInt(),
                    0xFFF5F5F7.toInt()
                ),
                sheetCornerRadiusDp = dp("sheetCornerRadius", 20f).coerceAtLeast(0f),
                gridSpacingDp = dp("gridSpacing", 2f).coerceAtLeast(0f),
            )
        }
    }
}

/**
 * Resolved localized strings for the Android custom media picker.
 * Android 自定义媒体选择器的已解析本地化文案。
 */
data class CustomMediaPickerStrings(
    val galleryTitle: String,
    val allMedia: String,
    val allVideos: String,
    val openInOtherApp: String,
    val done: String,
    val cancel: String,
    val maxSelectionReached: String,
    val limitedAccessHint: String,
    val managePermission: String,
    val permissionDeniedMessage: String,
    val openSettings: String,
    val emptyAlbum: String,
    val cameraLabel: String,
) {
    companion object {
        /**
         * Parses string overrides from Flutter and falls back to Chinese or
         * English defaults based on the device locale.
         * 解析来自 Flutter 的文案覆盖，并根据系统语言回退为简体中文或英文默认文案。
         */
        fun fromMap(map: Map<*, *>?): CustomMediaPickerStrings {
            val isZh = Locale.getDefault().language.lowercase(Locale.ROOT).startsWith("zh")
            fun str(key: String, zhDefault: String, enDefault: String): String {
                val custom = map?.get(key) as? String
                if (!custom.isNullOrEmpty()) return custom
                return if (isZh) zhDefault else enDefault
            }

            return CustomMediaPickerStrings(
                galleryTitle = str("galleryTitle", "相册", "Gallery"),
                allMedia = str("allMedia", "所有媒体", "All Media"),
                allVideos = str("allVideos", "所有视频", "All Videos"),
                openInOtherApp = str("openInOtherApp", "使用其它应用打开…", "Open in other app…"),
                done = str("done", "完成", "Done"),
                cancel = str("cancel", "取消", "Cancel"),
                maxSelectionReached = str(
                    "maxSelectionReached",
                    "最多只能选择 {max} 个文件",
                    "You can select up to {max} items"
                ),
                limitedAccessHint = str(
                    "limitedAccessHint",
                    "已授权访问部分照片和视频",
                    "Limited access to selected photos and videos"
                ),
                managePermission = str("managePermission", "管理", "Manage"),
                permissionDeniedMessage = str(
                    "permissionDeniedMessage",
                    "需要相册访问权限以浏览图片和视频",
                    "Photo library permission is required to browse media"
                ),
                openSettings = str("openSettings", "前往设置", "Open Settings"),
                emptyAlbum = str("emptyAlbum", "暂无媒体文件", "No media found"),
                cameraLabel = str("cameraLabel", "拍摄", "Camera"),
            )
        }
    }
}

/**
 * Full runtime configuration for launching the Android custom media picker.
 * 启动 Android 自定义媒体选择器的完整运行时配置。
 */
data class CustomMediaPickerConfig(
    val mediaType: String, // "image" | "video" | "media"
    val multiple: Boolean,
    val maxFiles: Int?,
    val withData: Boolean,
    val showCameraTile: Boolean,
    val allowOpenInOtherApp: Boolean,
    val crossAxisCount: Int,
    val initialExpanded: Boolean,
    val enablePreview: Boolean,
    val theme: CustomMediaPickerTheme,
    val strings: CustomMediaPickerStrings,
) {
    companion object {
        /**
         * Builds a [CustomMediaPickerConfig] from MethodChannel arguments.
         * 从 MethodChannel 调用参数构建 [CustomMediaPickerConfig]。
         */
        fun fromArgs(
            context: Context,
            mediaType: String,
            multiple: Boolean,
            maxFiles: Int?,
            withData: Boolean,
            optionsMap: Map<*, *>?,
        ): CustomMediaPickerConfig {
            val themeMap = optionsMap?.get("theme") as? Map<*, *>
            val stringsMap = optionsMap?.get("strings") as? Map<*, *>
            val rawCols = (optionsMap?.get("crossAxisCount") as? Number)?.toInt() ?: 3
            return CustomMediaPickerConfig(
                mediaType = mediaType,
                multiple = multiple,
                maxFiles = maxFiles,
                withData = withData,
                showCameraTile = (optionsMap?.get("showCameraTile") as? Boolean) ?: true,
                allowOpenInOtherApp = (optionsMap?.get("allowOpenInOtherApp") as? Boolean) ?: true,
                crossAxisCount = rawCols.coerceIn(2, 6),
                initialExpanded = (optionsMap?.get("initialExpanded") as? Boolean) ?: false,
                enablePreview = (optionsMap?.get("enablePreview") as? Boolean) ?: true,
                theme = CustomMediaPickerTheme.fromMap(context, themeMap),
                strings = CustomMediaPickerStrings.fromMap(stringsMap),
            )
        }
    }
}

/**
 * A single image or video entry queried from Android MediaStore.
 * 从 Android MediaStore 查询得到的单条图片或视频媒体项。
 */
data class MediaItem(
    val id: Long,
    val uri: Uri,
    val displayName: String,
    val mimeType: String,
    val isVideo: Boolean,
    val durationMs: Long,
    val dateAddedSec: Long,
    val bucketId: String,
    val bucketName: String,
    val size: Long,
)

/**
 * A virtual or device album bucket displayed in the album selector popover.
 * 相册下拉浮窗中展示的虚拟相册或设备相册分组。
 */
data class MediaAlbum(
    val id: String,
    val name: String,
    val count: Int,
    val coverUri: Uri?,
    val isAllMedia: Boolean = false,
    val isAllVideos: Boolean = false,
) {
    companion object {
        const val ID_ALL_MEDIA = "__all_media__"
        const val ID_ALL_VIDEOS = "__all_videos__"
    }
}
