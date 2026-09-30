package com.myleafy.android.features.profile

import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.BuildConfig
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.ui.components.LeafyContentSurface
import com.myleafy.android.ui.components.LeafyLoadingState
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafySecondaryButton
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.theme.LeafySpacing
import java.io.File

@Composable
fun CheckUpdatesScreen(
    onBack: () -> Unit,
    viewModel: CheckUpdatesViewModel = viewModel(
        factory = appViewModelFactory { container ->
            CheckUpdatesViewModel(container.appUpdateManager)
        },
    ),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var installError by remember { mutableStateOf<String?>(null) }

    UpdateInstallationHost(viewModel.manager) { installError = it }

    LeafySecondaryScaffold(title = "检查更新", onBack = onBack) { contentModifier ->
        LazyColumn(
            modifier = contentModifier.fillMaxSize(),
            contentPadding = PaddingValues(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            item {
                Text(
                    text = "Android ${BuildConfig.VERSION_NAME} · build ${BuildConfig.VERSION_CODE}",
                    style = MaterialTheme.typography.titleMedium,
                )
                Text(
                    text = "通过 MyLeafy 下载服务获取更新，GitHub Releases 同步提供安装包与发布说明。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            installError?.let { message ->
                item { LeafyStatusBanner(message = message, isError = true) }
            }
            when (val current = state) {
                UpdateUiState.Idle -> Unit
                UpdateUiState.Unpublished -> item { LeafyStatusBanner(message = "暂未发布适用于当前应用的版本。", isError = false) }
                UpdateUiState.Checking -> item {
                    LeafyLoadingState(message = "正在检查更新", modifier = Modifier.fillMaxWidth())
                }
                is UpdateUiState.UpToDate -> item {
                    LeafyStatusBanner(message = "已是最新版本（${current.currentVersion}）。", isError = false)
                }
                is UpdateUiState.Available -> item {
                    LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                        Column(
                            modifier = Modifier.padding(LeafySpacing.card),
                            verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
                        ) {
                            Text("发现新版本 ${current.info.versionName}", style = MaterialTheme.typography.titleMedium)
                            Text("${"%.1f".format(current.info.sizeBytes / 1048576.0)} MB", style = MaterialTheme.typography.labelMedium)
                            current.info.releaseNotes.let {
                                Text(
                                    text = it,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            Spacer(Modifier.height(LeafySpacing.tiny))
                            LeafyPrimaryButton(
                                onClick = { viewModel.download(current.info) },
                                modifier = Modifier.fillMaxWidth(),
                            ) { Text("下载并安装") }
                        }
                    }
                }
                is UpdateUiState.Downloading -> item {
                    LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                        Column(
                            modifier = Modifier.padding(LeafySpacing.card),
                            verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro),
                        ) {
                            Text("${current.message} ${current.info.versionName}", style = MaterialTheme.typography.titleSmall)
                            LinearProgressIndicator(
                                progress = { current.progress },
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Text(
                                text = "${(current.progress * 100).toInt()}%",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                is UpdateUiState.Downloaded -> item {
                    LeafyStatusBanner(
                        message = "${current.info.versionName} 已下载并通过校验。安装需要系统确认。",
                        isError = false,
                    )
                    LeafyPrimaryButton(onClick = { viewModel.manager.requestInstall() }) { Text("继续安装") }
                }
                is UpdateUiState.Error -> item {
                    LeafyStatusBanner(message = current.message, isError = true)
                }
            }
            item {
                LeafySecondaryButton(
                    onClick = viewModel::check,
                    enabled = state !is UpdateUiState.Checking && state !is UpdateUiState.Downloading,
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("重新检查") }
            }
        }
    }
}

internal fun launchInstaller(context: android.content.Context, file: File) {
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    context.startActivity(
        Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        },
    )
}
