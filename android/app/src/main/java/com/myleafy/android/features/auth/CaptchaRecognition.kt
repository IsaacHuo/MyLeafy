package com.myleafy.android.features.auth

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

data class CaptchaReading(val text: String, val confidence: Float)

object CaptchaConsensus {
    fun candidate(readings: List<CaptchaReading>): String? {
        val reliable = readings.filter { it.confidence.isFinite() && it.confidence >= 0.85f }
            .map { it.text.filterNot(Char::isWhitespace).lowercase() }
            .filter { it.matches(Regex("[a-z0-9]{4}")) }
            .groupingBy { it }.eachCount().filterValues { it >= 2 }
        return reliable.keys.singleOrNull()
    }
}

fun interface CaptchaRecognizer { suspend fun recognize(bytes: ByteArray): String? }

/** Bundled Latin model. No image uploads and no dependency on a model download. */
class MlKitCaptchaRecognizer : CaptchaRecognizer {
    override suspend fun recognize(bytes: ByteArray): String? = CaptchaConsensus.candidate(readings(bytes))
    internal suspend fun readings(bytes: ByteArray): List<CaptchaReading> = withContext(Dispatchers.Default) {
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return@withContext emptyList()
        // ML Kit requires both dimensions >=32; school images are only 20px high.
        // Padding preserves the original glyphs rather than silently skipping that variant.
        val original = if (decoded.width < 32 || decoded.height < 32) {
            Bitmap.createBitmap(maxOf(32, decoded.width), maxOf(32, decoded.height), Bitmap.Config.ARGB_8888).also {
                Canvas(it).apply { drawColor(android.graphics.Color.WHITE); drawBitmap(decoded, 0f, 0f, null) }
            }
        } else decoded
        val scaled = Bitmap.createScaledBitmap(original, original.width * 4, original.height * 4, true)
        val enhanced = Bitmap.createBitmap(scaled.width, scaled.height, Bitmap.Config.ARGB_8888)
        val matrix = ColorMatrix().apply { setSaturation(0f) }
        matrix.postConcat(ColorMatrix(floatArrayOf(1.4f,0f,0f,0f,5.1f, 0f,1.4f,0f,0f,5.1f, 0f,0f,1.4f,0f,5.1f, 0f,0f,0f,1f,0f)))
        Canvas(enhanced).drawBitmap(scaled, 0f, 0f, Paint().apply { colorFilter = ColorMatrixColorFilter(matrix) })
        val client = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            val readings = listOf(original, scaled, enhanced).mapNotNull { image ->
                coroutineContext.ensureActive()
                val result = suspendCancellableCoroutine<com.google.mlkit.vision.text.Text> { continuation ->
                    client.process(InputImage.fromBitmap(image, 0))
                        .addOnSuccessListener { if (continuation.isActive) continuation.resume(it) }
                        .addOnFailureListener { if (continuation.isActive) continuation.resumeWithException(it) }
                }
                val elements = result.textBlocks.flatMap { it.lines }.flatMap { it.elements }
                    .sortedBy { it.boundingBox?.left ?: Int.MAX_VALUE }
                if (elements.isEmpty()) null else CaptchaReading(elements.joinToString("") { it.text }, elements.minOf { it.confidence })
            }
            readings
        } finally { client.close() }
    }
}
