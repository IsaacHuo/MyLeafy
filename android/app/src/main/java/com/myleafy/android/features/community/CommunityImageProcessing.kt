package com.myleafy.android.features.community

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * 待上传的社区帖子图片。
 *
 * [bytes] 与 [thumbnailBytes] 均为 JPEG；服务端 `community-validate-upload` 要求
 * full ≤1600px、thumb ≤480px 且单对象 ≤1MB，客户端按更严格的目标体积编码。
 * `ByteArray` 不便做结构化相等，沿用同一实例语义。
 */
class CommunityPostImageUpload(
    val id: String,
    val bytes: ByteArray,
    val thumbnailBytes: ByteArray,
) {
    override fun equals(other: Any?): Boolean = this === other
    override fun hashCode(): Int = System.identityHashCode(this)
}

/** 图片选择与压缩（对应 iOS `CommunityImageProcessing` / `CommunityImageUpload`）。 */
object CommunityImageProcessing {

    const val postImageLimit = 4
    private const val fullMaxDimension = 1600
    private const val thumbnailMaxDimension = 480
    private const val fullMaxBytes = 800 * 1024
    private const val thumbnailMaxBytes = 120 * 1024

    /** 解码、按 EXIF 方向归一，并输出 full/thumb 两档 JPEG。 */
    fun prepare(context: Context, uri: Uri, id: String): CommunityPostImageUpload {
        val source = ImageDecoder.createSource(context.contentResolver, uri)
        val decoded = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            val longest = max(info.size.width, info.size.height)
            var sample = 1
            while (longest / (sample * 2) >= fullMaxDimension) sample *= 2
            decoder.setTargetSampleSize(sample)
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
        val full = scaleToFit(decoded, fullMaxDimension)
        if (full !== decoded) decoded.recycle()
        val thumbnail = scaleToFit(full, thumbnailMaxDimension)
        val fullBytes = encodeJpegWithinBudget(full, fullMaxBytes)
        val thumbnailBytes = encodeJpegWithinBudget(thumbnail, thumbnailMaxBytes)
        full.recycle()
        if (thumbnail !== full) thumbnail.recycle()
        return CommunityPostImageUpload(id = id, bytes = fullBytes, thumbnailBytes = thumbnailBytes)
    }

    private fun scaleToFit(bitmap: Bitmap, maxDimension: Int): Bitmap {
        val longest = max(bitmap.width, bitmap.height)
        if (longest <= maxDimension) return bitmap
        val ratio = maxDimension.toFloat() / longest
        val width = (bitmap.width * ratio).roundToInt().coerceAtLeast(1)
        val height = (bitmap.height * ratio).roundToInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, width, height, true)
    }

    private fun encodeJpegWithinBudget(bitmap: Bitmap, maxBytes: Int): ByteArray {
        var quality = 88
        while (true) {
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
            val bytes = stream.toByteArray()
            if (bytes.size <= maxBytes || quality <= 40) return bytes
            quality -= 8
        }
    }
}
