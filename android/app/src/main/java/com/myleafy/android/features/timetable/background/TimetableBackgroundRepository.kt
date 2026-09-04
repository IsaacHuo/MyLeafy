package com.myleafy.android.features.timetable.background

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import com.myleafy.android.core.prefs.SettingsStore
import com.myleafy.android.core.prefs.TimetableBackgroundSettings
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

class TimetableBackgroundRepository(
    private val context: Context,
    private val settingsStore: SettingsStore,
) {
    val settings: Flow<TimetableBackgroundSettings> = settingsStore.settings.map { it.timetableBackground }

    suspend fun update(value: TimetableBackgroundSettings) {
        val prepared = withContext(Dispatchers.IO) {
            if (value.kind == "photo" && value.photoPath != null && Build.VERSION.SDK_INT < 31) {
                value.copy(blurredPhotoPath = prepareBlurCache(value.photoPath, value.blurRadius))
            } else {
                value
            }
        }
        if (prepared.blurredPhotoPath != value.blurredPhotoPath) {
            value.blurredPhotoPath?.let(::File)?.takeIf(File::isFile)?.delete()
        }
        settingsStore.setTimetableBackground(prepared)
    }

    suspend fun importPhoto(uri: Uri, current: TimetableBackgroundSettings): TimetableBackgroundSettings =
        withContext(Dispatchers.IO) {
            val directory = File(context.filesDir, "timetable-background").apply { mkdirs() }
            val target = File(directory, "background-${UUID.randomUUID()}.jpg")
            val decoded = decodeScaled(uri, 1_920) ?: error("无法读取所选照片")
            FileOutputStream(target).use { output ->
                check(decoded.compress(Bitmap.CompressFormat.JPEG, 88, output)) { "背景照片压缩失败" }
            }
            decoded.recycle()
            current.photoPath?.let(::File)?.takeIf(File::isFile)?.delete()
            current.blurredPhotoPath?.let(::File)?.takeIf(File::isFile)?.delete()
            current.copy(
                enabled = true,
                kind = "photo",
                photoPath = target.absolutePath,
                blurredPhotoPath = if (Build.VERSION.SDK_INT < 31) prepareBlurCache(target.absolutePath, current.blurRadius) else null,
            ).also { settingsStore.setTimetableBackground(it) }
        }

    suspend fun removePhoto(current: TimetableBackgroundSettings): TimetableBackgroundSettings = withContext(Dispatchers.IO) {
        current.photoPath?.let(::File)?.takeIf { it.isFile && it.parentFile?.name == "timetable-background" }?.delete()
        current.blurredPhotoPath?.let(::File)?.takeIf { it.isFile && it.parentFile?.name == "timetable-background" }?.delete()
        current.copy(enabled = false, kind = "color", photoPath = null, blurredPhotoPath = null)
            .also { settingsStore.setTimetableBackground(it) }
    }

    private fun decodeScaled(uri: Uri, maxSide: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > maxSide * 2) sample *= 2
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }
    }

    private fun prepareBlurCache(sourcePath: String, radius: Int): String? {
        if (radius <= 0) return null
        val source = BitmapFactory.decodeFile(sourcePath) ?: return null
        val maxSide = maxOf(source.width, source.height)
        val baseScale = (720f / maxSide).coerceAtMost(1f)
        val factor = (1f / (1f + radius / 3f)).coerceAtLeast(0.08f)
        val smallWidth = (source.width * baseScale * factor).toInt().coerceAtLeast(2)
        val smallHeight = (source.height * baseScale * factor).toInt().coerceAtLeast(2)
        val small = Bitmap.createScaledBitmap(source, smallWidth, smallHeight, true)
        val resultWidth = (source.width * baseScale).toInt().coerceAtLeast(2)
        val resultHeight = (source.height * baseScale).toInt().coerceAtLeast(2)
        val blurred = Bitmap.createScaledBitmap(small, resultWidth, resultHeight, true)
        val sourceName = File(sourcePath).nameWithoutExtension
        val target = File(
            File(context.filesDir, "timetable-background").apply { mkdirs() },
            "$sourceName-blurred-$radius.jpg",
        )
        FileOutputStream(target).use { blurred.compress(Bitmap.CompressFormat.JPEG, 85, it) }
        if (small !== source) small.recycle()
        if (blurred !== small && blurred !== source) blurred.recycle()
        source.recycle()
        return target.absolutePath
    }
}
