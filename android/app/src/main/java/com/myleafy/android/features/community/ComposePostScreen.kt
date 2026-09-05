package com.myleafy.android.features.community

import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyPrimaryButton
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
            ComposePostViewModel(repository = container.communityRepository)
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val categoryFocus = remember { FocusRequester() }
    val bodyFocus = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current

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
