package com.myleafy.android.features.campus

import android.content.*
import android.graphics.*
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.myleafy.android.ui.components.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

fun shareCampusFile(context: Context, file: File, mime: String) {
    check(file.isFile) { "文件已丢失" }
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
        type = mime; putExtra(Intent.EXTRA_STREAM, uri); clipData = ClipData.newRawUri(file.name, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }, "分享文件"))
}

@Composable fun CampusFilePreview(file: File, mime: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var page by remember { mutableIntStateOf(0) }
    var count by remember { mutableIntStateOf(1) }
    var bitmap by remember(file, page) { mutableStateOf<Bitmap?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(file, page) {
        try {
            bitmap = withContext(Dispatchers.IO) {
                check(file.isFile) { "文件已丢失" }
                if (mime == "application/pdf") ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                    PdfRenderer(descriptor).use { renderer ->
                        count = renderer.pageCount
                        renderer.openPage(page).use { pdf ->
                            val width = 1200
                            Bitmap.createBitmap(width, (width.toFloat() * pdf.height / pdf.width).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888).apply {
                                eraseColor(Color.WHITE); pdf.render(this, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            }
                        }
                    }
                } else {
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(file.path, bounds)
                    val options = BitmapFactory.Options().apply { inSampleSize = (maxOf(bounds.outWidth, bounds.outHeight) / 1600).coerceAtLeast(1) }
                    BitmapFactory.decodeFile(file.path, options) ?: error("图片无法读取")
                }
            }
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (failure: Exception) { error = failure.message ?: "预览失败" }
    }
    LeafyAlertDialog(onDismissRequest = onDismiss, title = { Text(file.name) }, text = {
        Column { error?.let { LeafyStatusBanner(it, isError = true) }
            if (bitmap == null && error == null) CircularProgressIndicator()
            bitmap?.let { Image(it.asImageBitmap(), file.name, Modifier.fillMaxWidth().heightIn(max = 460.dp)) }
            if (mime == "application/pdf") Row {
                TextButton(enabled = page > 0, onClick = { page-- }) { Text("上一页") }
                Text("${page + 1} / $count", Modifier.padding(top = 12.dp))
                TextButton(enabled = page + 1 < count, onClick = { page++ }) { Text("下一页") }
            }
        }
    }, confirmButton = { TextButton(onClick = onDismiss) { Text("完成") } }, dismissButton = { TextButton(onClick = {
        try { shareCampusFile(context, file, mime) } catch (failure: Exception) { error = failure.message }
    }) { Text("分享原文件") } })
}

suspend fun campusTextImage(context: Context, name: String, title: String, lines: List<String>): File = withContext(Dispatchers.IO) {
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(28, 48, 40); textSize = 32f }
    val wrapped = mutableListOf<String>()
    lines.forEach { source -> source.lines().forEach { line ->
        var remaining = line
        while (remaining.isNotEmpty()) {
            val length = paint.breakText(remaining, true, 940f, null).coerceAtLeast(1)
            wrapped += remaining.take(length); remaining = remaining.drop(length)
        }
        if (line.isEmpty()) wrapped += ""
    } }
    check(wrapped.size <= 500) { "内容过多，请使用 CSV 导出完整记录" }
    val bitmap = Bitmap.createBitmap(1080, 210 + wrapped.size * 52, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap); canvas.drawColor(Color.WHITE)
    paint.textSize = 42f; paint.typeface = Typeface.DEFAULT_BOLD
    canvas.drawText(title, 70f, 90f, paint)
    paint.textSize = 32f; paint.typeface = Typeface.DEFAULT
    wrapped.forEachIndexed { i, text -> canvas.drawText(text, 70f, 165f + i * 52f, paint) }
    File(context.cacheDir, "campus-exports/$name.png").apply { parentFile?.mkdirs(); outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) } }.also { bitmap.recycle() }
}
