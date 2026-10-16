package com.kurban.xue_hua_file_operations

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.io.FileOutputStream
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Downscales / recompresses a captured photo so it honours `maxWidth`,
 * `maxHeight` and `imageQuality`. The result is written next to the original
 * as `scaled_<name>` and keeps the EXIF metadata of the source.
 */
internal class CaptureImageResizer(private val context: Context) {

    /** Returns [imagePath] untouched when no resize / recompress is needed. */
    fun resizeIfNeeded(
        imagePath: String,
        maxWidth: Double?,
        maxHeight: Double?,
        imageQuality: Int?,
    ): String {
        val quality = imageQuality ?: 100
        if (maxWidth == null && maxHeight == null && quality >= 100) return imagePath

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(imagePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return imagePath

        val (targetWidth, targetHeight) = calculateTargetSize(
            bounds.outWidth.toDouble(),
            bounds.outHeight.toDouble(),
            maxWidth,
            maxHeight,
        )
        val options = BitmapFactory.Options().apply {
            inSampleSize = calculateSampleSize(
                bounds.outWidth,
                bounds.outHeight,
                targetWidth.toInt(),
                targetHeight.toInt(),
            )
        }
        val decoded = BitmapFactory.decodeFile(imagePath, options) ?: return imagePath
        val scaled = Bitmap.createScaledBitmap(
            decoded,
            targetWidth.toInt().coerceAtLeast(1),
            targetHeight.toInt().coerceAtLeast(1),
            false,
        )
        val outDir = File(context.cacheDir, CAPTURE_DIR).apply { mkdirs() }
        val out = File(outDir, "scaled_${File(imagePath).name}")
        // PNG is lossless, so `quality` has no effect on images with alpha.
        val format = if (scaled.hasAlpha()) Bitmap.CompressFormat.PNG
        else Bitmap.CompressFormat.JPEG
        FileOutputStream(out).use { scaled.compress(format, quality, it) }
        copyExif(imagePath, out.path)
        return out.path
    }

    private fun calculateTargetSize(
        originalWidth: Double,
        originalHeight: Double,
        maxWidth: Double?,
        maxHeight: Double?,
    ): Pair<Double, Double> {
        val aspectRatio = originalWidth / originalHeight
        var width = if (maxWidth != null) min(originalWidth, maxWidth.roundToInt().toDouble())
        else originalWidth
        var height = if (maxHeight != null) min(originalHeight, maxHeight.roundToInt().toDouble())
        else originalHeight

        val downscale = (maxWidth != null && maxWidth < originalWidth) ||
                (maxHeight != null && maxHeight < originalHeight)
        if (downscale) {
            val widthForMaxHeight = height * aspectRatio
            val heightForMaxWidth = width / aspectRatio
            if (heightForMaxWidth > height) {
                width = widthForMaxHeight.roundToInt().toDouble()
            } else {
                height = heightForMaxWidth.roundToInt().toDouble()
            }
        }
        return width to height
    }

    private fun calculateSampleSize(
        width: Int,
        height: Int,
        targetWidth: Int,
        targetHeight: Int,
    ): Int {
        var sampleSize = 1
        if (height > targetHeight || width > targetWidth) {
            val halfHeight = height / 2
            val halfWidth = width / 2
            while (halfHeight / sampleSize >= targetHeight &&
                halfWidth / sampleSize >= targetWidth
            ) {
                sampleSize *= 2
            }
        }
        return sampleSize
    }

    private fun copyExif(from: String, to: String) {
        try {
            val source = ExifInterface(from)
            val dest = ExifInterface(to)
            for (tag in EXIF_TAGS) {
                source.getAttribute(tag)?.let { dest.setAttribute(tag, it) }
            }
            dest.saveAttributes()
        } catch (_: Exception) {
            // Metadata is best effort; the pixels are already written.
        }
    }

    companion object {
        const val CAPTURE_DIR = "xue_hua_file_operations/capture"

        private val EXIF_TAGS = listOf(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.TAG_MAKE,
            ExifInterface.TAG_MODEL,
            ExifInterface.TAG_SOFTWARE,
            ExifInterface.TAG_DATETIME,
            ExifInterface.TAG_DATETIME_ORIGINAL,
            ExifInterface.TAG_DATETIME_DIGITIZED,
            ExifInterface.TAG_EXPOSURE_TIME,
            ExifInterface.TAG_F_NUMBER,
            ExifInterface.TAG_EXPOSURE_PROGRAM,
            ExifInterface.TAG_ISO_SPEED_RATINGS,
            ExifInterface.TAG_APERTURE_VALUE,
            ExifInterface.TAG_EXPOSURE_BIAS_VALUE,
            ExifInterface.TAG_METERING_MODE,
            ExifInterface.TAG_LIGHT_SOURCE,
            ExifInterface.TAG_FLASH,
            ExifInterface.TAG_FOCAL_LENGTH,
            ExifInterface.TAG_WHITE_BALANCE,
            ExifInterface.TAG_FOCAL_LENGTH_IN_35MM_FILM,
            ExifInterface.TAG_LENS_MAKE,
            ExifInterface.TAG_LENS_MODEL,
            ExifInterface.TAG_GPS_LATITUDE_REF,
            ExifInterface.TAG_GPS_LATITUDE,
            ExifInterface.TAG_GPS_LONGITUDE_REF,
            ExifInterface.TAG_GPS_LONGITUDE,
            ExifInterface.TAG_GPS_ALTITUDE_REF,
            ExifInterface.TAG_GPS_ALTITUDE,
            ExifInterface.TAG_GPS_TIMESTAMP,
            ExifInterface.TAG_GPS_DATESTAMP,
            ExifInterface.TAG_GPS_PROCESSING_METHOD,
        )
    }
}
