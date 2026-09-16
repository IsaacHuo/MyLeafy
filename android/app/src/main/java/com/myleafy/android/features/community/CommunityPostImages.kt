package com.myleafy.android.features.community

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import coil.compose.SubcomposeAsyncImage
import com.myleafy.android.services.SupabaseConfig
import com.myleafy.android.shared.model.PostImageDto
import com.myleafy.android.ui.theme.LeafySpacing

/** `community-images` 为公开 bucket，客户端按公开 URL 读取，无需签名。 */
fun postImagePublicUrl(path: String?): String? {
    val trimmed = path?.trim().orEmpty()
    if (trimmed.isEmpty() || !SupabaseConfig.isConfigured) return null
    return "${SupabaseConfig.supabaseUrl}/storage/v1/object/public/community-images/$trimmed"
}

fun PostImageDto.thumbnailPublicUrl(): String? = postImagePublicUrl(thumbnail_path ?: path)

fun PostImageDto.fullPublicUrl(): String? = postImagePublicUrl(path)

private fun PostImageDto.displayAspectRatio(): Float {
    val width = (full_width ?: width)?.toFloat() ?: 0f
    val height = (full_height ?: height)?.toFloat() ?: 0f
    if (width <= 0f || height <= 0f) return 4f / 3f
    return (width / height).coerceIn(0.5f, 2.0f)
}

@Composable
private fun RemotePostImage(
    image: PostImageDto,
    fullSize: Boolean,
    modifier: Modifier = Modifier,
) {
    val url = if (fullSize) image.fullPublicUrl() else image.thumbnailPublicUrl()
    Box(
        modifier = modifier
            .clip(MaterialTheme.shapes.medium)
            .background(MaterialTheme.colorScheme.surfaceContainer),
    ) {
        SubcomposeAsyncImage(
            model = url,
            contentDescription = "帖子图片",
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
            loading = { PostImagePlaceholder() },
            error = { PostImagePlaceholder() },
        )
    }
}

@Composable
private fun PostImagePlaceholder() {
    Box(
        modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceContainer),
    )
}

/** 信息流封面：仅展示第一张，多图时叠加数量标记。 */
@Composable
fun CommunityPostCoverImage(images: List<PostImageDto>, modifier: Modifier = Modifier) {
    if (images.isEmpty()) return
    val sorted = images.sortedBy { it.sort_order }
    val cover = sorted.first()
    Box(modifier = modifier.fillMaxWidth()) {
        RemotePostImage(
            image = cover,
            fullSize = false,
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(cover.displayAspectRatio())
                .then(Modifier),
        )
        if (sorted.size > 1) {
            Text(
                text = "${sorted.size} 图",
                style = MaterialTheme.typography.labelSmall,
                color = Color.White,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(LeafySpacing.micro)
                    .background(Color.Black.copy(alpha = 0.5f), MaterialTheme.shapes.small)
                    .padding(horizontal = LeafySpacing.micro, vertical = LeafySpacing.tiny),
            )
        }
    }
}

/** 详情页图片列：按 sort_order 展示全部图片。 */
@Composable
fun CommunityPostImageColumn(images: List<PostImageDto>, modifier: Modifier = Modifier) {
    if (images.isEmpty()) return
    val sorted = images.sortedBy { it.sort_order }
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
    ) {
        sorted.forEach { image ->
            RemotePostImage(
                image = image,
                fullSize = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(image.displayAspectRatio()),
            )
        }
    }
}
