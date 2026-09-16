package com.myleafy.android.features.community

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AddPhotoAlternate
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafySecondaryButton
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.theme.LeafyComponentSize
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.LeafyStroke

@Composable
fun ComposePostScreen(
    onBack: () -> Unit,
    onPublished: () -> Unit,
    viewModel: ComposePostViewModel = viewModel(
        factory = appViewModelFactory { container ->
            ComposePostViewModel(
                repository = container.communityRepository,
                context = container.applicationContext,
            )
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val categoryFocus = remember { FocusRequester() }
    val bodyFocus = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    val imagePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(CommunityImageProcessing.postImageLimit),
    ) { uris: List<Uri> -> viewModel.addImages(uris) }

    if (uiState.published) {
        LaunchedEffect(Unit) { onPublished() }
    }

    LeafySecondaryScaffold(title = "发帖", onBack = onBack, modifier = modifier) { contentModifier ->
        Box(modifier = contentModifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .widthIn(max = LeafyComponentSize.formMaxWidth)
                    .verticalScroll(rememberScrollState())
                    .imePadding()
                    .padding(horizontal = LeafySpacing.page),
            ) {
                Spacer(modifier = Modifier.height(LeafySpacing.micro))
                OutlinedTextField(
                    value = uiState.title,
                    onValueChange = viewModel::updateTitle,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("标题") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    keyboardActions = KeyboardActions(onNext = { categoryFocus.requestFocus() }),
                )
                Spacer(modifier = Modifier.height(LeafySpacing.compact))
                OutlinedTextField(
                    value = uiState.category,
                    onValueChange = viewModel::updateCategory,
                    modifier = Modifier.fillMaxWidth().focusRequester(categoryFocus),
                    label = { Text("分类（可选）") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    keyboardActions = KeyboardActions(onNext = { bodyFocus.requestFocus() }),
                )
                Spacer(modifier = Modifier.height(LeafySpacing.compact))
                OutlinedTextField(
                    value = uiState.body,
                    onValueChange = viewModel::updateBody,
                    modifier = Modifier.fillMaxWidth().focusRequester(bodyFocus),
                    label = { Text("正文") },
                    minLines = 6,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
                )
                Spacer(modifier = Modifier.height(LeafySpacing.compact))
                Text(
                    text = "图片（${uiState.images.size}/${CommunityImageProcessing.postImageLimit}）",
                    style = MaterialTheme.typography.titleSmall,
                )
                if (uiState.images.isNotEmpty()) {
                    LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = LeafySpacing.micro),
                    ) {
                        items(uiState.images, key = { it.id }) { image ->
                            Box(modifier = Modifier.size(88.dp).clip(MaterialTheme.shapes.medium)) {
                                AsyncImage(
                                    model = image.uri,
                                    contentDescription = "已选图片",
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier.fillMaxSize(),
                                )
                                IconButton(
                                    onClick = { viewModel.removeImage(image.id) },
                                    modifier = Modifier.align(Alignment.TopEnd).size(32.dp),
                                ) {
                                    Icon(Icons.Outlined.Close, contentDescription = "移除图片", tint = Color.White)
                                }
                            }
                        }
                    }
                }
                LeafySecondaryButton(
                    onClick = {
                        imagePicker.launch(
                            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                        )
                    },
                    enabled = !uiState.isSubmitting &&
                        uiState.images.size < CommunityImageProcessing.postImageLimit,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Outlined.AddPhotoAlternate, contentDescription = null)
                    Text("添加图片", modifier = Modifier.padding(start = LeafySpacing.micro))
                }
                Spacer(modifier = Modifier.height(LeafySpacing.micro))
                androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(
                        checked = uiState.isAnonymous,
                        onCheckedChange = { viewModel.toggleAnonymous() },
                    )
                    Text(
                        text = "匿名发布",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(modifier = Modifier.height(LeafySpacing.compact))

                uiState.errorMessage?.let { errorMessage ->
                    LeafyStatusBanner(message = errorMessage, isError = true)
                    Spacer(modifier = Modifier.height(LeafySpacing.micro))
                }

                LeafyPrimaryButton(
                    onClick = viewModel::submit,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !uiState.isSubmitting,
                ) {
                    if (uiState.isSubmitting) {
                        CircularProgressIndicator(modifier = Modifier.height(LeafyIconSize.compact), strokeWidth = LeafyStroke.progress)
                    } else {
                        Text("发布")
                    }
                }
                Spacer(modifier = Modifier.height(LeafySpacing.section))
            }
        }
    }
}
