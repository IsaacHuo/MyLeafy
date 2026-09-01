package com.myleafy.android.features.community

import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.leafyMinimumTouchTarget
import com.myleafy.android.ui.theme.LeafyComponentSize
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.LeafySpacing

@Composable
fun ComposePostScreen(
    onBack: () -> Unit,
    onPublished: () -> Unit,
    viewModel: ComposePostViewModel = viewModel(
        factory = appViewModelFactory { container ->
            ComposePostViewModel(repository = container.communityRepository)
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

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
                )
                Spacer(modifier = Modifier.height(LeafySpacing.compact))
                OutlinedTextField(
                    value = uiState.category,
                    onValueChange = viewModel::updateCategory,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("分类（可选）") },
                    singleLine = true,
                )
                Spacer(modifier = Modifier.height(LeafySpacing.compact))
                OutlinedTextField(
                    value = uiState.body,
                    onValueChange = viewModel::updateBody,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("正文") },
                    minLines = 6,
                )
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
                    Text(
                        text = errorMessage,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error,
                    )
                    Spacer(modifier = Modifier.height(LeafySpacing.micro))
                }

                Button(
                    onClick = viewModel::submit,
                    modifier = Modifier.fillMaxWidth().leafyMinimumTouchTarget(),
                    enabled = !uiState.isSubmitting,
                ) {
                    if (uiState.isSubmitting) {
                        CircularProgressIndicator(modifier = Modifier.height(LeafyIconSize.compact), strokeWidth = LeafySpacing.hairline)
                    } else {
                        Text("发布")
                    }
                }
                Spacer(modifier = Modifier.height(LeafySpacing.section))
            }
        }
    }
}
