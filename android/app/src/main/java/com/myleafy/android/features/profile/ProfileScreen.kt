package com.myleafy.android.features.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.automirrored.outlined.Login
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.CloudSync
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Feedback
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.People
import androidx.compose.material3.Button
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.navigation.FeatureDestination
import com.myleafy.android.shared.model.ProfileDto
import com.myleafy.android.ui.components.LeafyFeatureCard
import com.myleafy.android.ui.components.LeafyRootTopBar
import com.myleafy.android.ui.components.LeafySectionHeader
import com.myleafy.android.ui.components.LeafyStatusBanner

@Composable
fun ProfileScreen(
    onLoginClick: () -> Unit = {},
    onEditProfileClick: () -> Unit = {},
    onFeatureClick: (FeatureDestination) -> Unit = {},
    viewModel: ProfileViewModel = viewModel(
        factory = appViewModelFactory { container ->
            ProfileViewModel(
                repository = container.profileRepository,
                settings = container.settingsStore,
                signOut = container::signOut,
            )
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val isSigningOut by viewModel.isSigningOut.collectAsStateWithLifecycle()
    var confirmLogout by remember { mutableStateOf(false) }
    LifecycleResumeEffect(Unit) {
        viewModel.refreshProfile()
        onPauseOrDispose { }
    }
    if (confirmLogout) {
        AlertDialog(
            onDismissRequest = { confirmLogout = false },
            title = { Text("退出登录") },
            text = { Text("将清理学校和社区会话及本机保存的登录凭据；课表、日程、随记和学业缓存会按当前身份保留。") },
            confirmButton = {
                TextButton(onClick = {
                    confirmLogout = false
                    viewModel.logout()
                }) { Text("退出") }
            },
            dismissButton = { TextButton(onClick = { confirmLogout = false }) { Text("取消") } },
        )
    }

    Scaffold(
        modifier = modifier,
        topBar = { LeafyRootTopBar(title = "我的") },
    ) { contentPadding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(contentPadding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                when (val state = uiState) {
                    is ProfileUiState.Local -> LocalProfileCard(state, onLoginClick)
                    is ProfileUiState.ProfileLoading -> {
                        Column(
                            modifier = Modifier.fillMaxWidth().padding(24.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            CircularProgressIndicator()
                        }
                    }
                    is ProfileUiState.Community -> ProfileCard(
                        state.campusId,
                        state.eduId,
                        state.profile,
                        onEditProfileClick,
                    )
                    is ProfileUiState.Error -> {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            LocalIdentityCard(state.campusId, state.eduId)
                            LeafyStatusBanner(message = state.message, isError = true)
                        }
                    }
                }
            }

            item { LeafySectionHeader(title = "课表与偏好", modifier = Modifier.padding(top = 8.dp)) }
            item {
                LeafyFeatureCard(
                    title = "缓存与同步",
                    description = "检查本地数据与学校同步状态",
                    icon = Icons.Outlined.CloudSync,
                    onClick = { onFeatureClick(FeatureDestination.PROFILE_SYNC) },
                )
            }
            item {
                LeafyFeatureCard(
                    title = "共享课表",
                    description = "邀请同学查看课程安排",
                    icon = Icons.Outlined.People,
                    onClick = { onFeatureClick(FeatureDestination.PROFILE_SHARING) },
                )
            }
            item {
                LeafyFeatureCard(
                    title = "个性化",
                    description = "主题、显示与课表背景",
                    icon = Icons.Outlined.AutoAwesome,
                    onClick = { onFeatureClick(FeatureDestination.PROFILE_PERSONALIZATION) },
                )
            }

            item { LeafySectionHeader(title = "帮助与安全", modifier = Modifier.padding(top = 8.dp)) }
            item {
                LeafyFeatureCard(
                    title = "帮助中心",
                    description = "使用指南、常见问题与数据安全",
                    icon = Icons.AutoMirrored.Outlined.HelpOutline,
                    onClick = { onFeatureClick(FeatureDestination.PROFILE_HELP) },
                )
            }
            item {
                LeafyFeatureCard(
                    title = "系统权限",
                    description = "了解权限用途并打开 Android 设置",
                    icon = Icons.Outlined.Lock,
                    onClick = { onFeatureClick(FeatureDestination.PROFILE_PERMISSIONS) },
                )
            }
            item {
                LeafyFeatureCard(
                    title = "反馈与支持",
                    description = "提交问题、建议或联系项目支持",
                    icon = Icons.Outlined.Feedback,
                    onClick = { onFeatureClick(FeatureDestination.PROFILE_FEEDBACK) },
                )
            }

            item { LeafySectionHeader(title = "项目", modifier = Modifier.padding(top = 8.dp)) }
            item {
                LeafyFeatureCard(
                    title = "关于 MyLeafy",
                    description = "项目、版本、开源与支持信息",
                    icon = Icons.Outlined.Info,
                    onClick = { onFeatureClick(FeatureDestination.PROFILE_ABOUT) },
                )
            }
            val hasIdentity = when (val state = uiState) {
                is ProfileUiState.Community -> true
                is ProfileUiState.Local -> !state.eduId.isNullOrBlank()
                is ProfileUiState.Error -> !state.eduId.isNullOrBlank()
                ProfileUiState.ProfileLoading -> true
            }
            if (hasIdentity) {
                item {
                    OutlinedButton(
                        onClick = { confirmLogout = true },
                        enabled = !isSigningOut,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        androidx.compose.material3.Icon(Icons.AutoMirrored.Outlined.Logout, contentDescription = null)
                        Text(if (isSigningOut) "正在退出…" else "退出登录", modifier = Modifier.padding(start = 8.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun LocalProfileCard(state: ProfileUiState.Local, onLoginClick: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        LocalIdentityCard(state.campusId, state.eduId)
        if (state.eduId.isNullOrBlank()) {
            Button(onClick = onLoginClick, modifier = Modifier.fillMaxWidth()) {
                androidx.compose.material3.Icon(Icons.AutoMirrored.Outlined.Login, contentDescription = null)
                Text("登录学校账号", modifier = Modifier.padding(start = 8.dp))
            }
        }
    }
}

@Composable
private fun LocalIdentityCard(campusId: String, eduId: String?) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(20.dp)) {
            Text(text = "MyLeafy", style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.primary)
            Spacer(modifier = Modifier.height(6.dp))
            Text(text = "校园 $campusId", style = MaterialTheme.typography.titleMedium)
            Text(
                text = if (eduId.isNullOrBlank()) "尚未绑定学校身份" else "学号 $eduId",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ProfileCard(campusId: String, eduId: String, profile: ProfileDto, onEdit: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(20.dp)) {
            Text(
                text = profile.nickname.ifBlank { profile.display_name ?: "未命名" },
                style = MaterialTheme.typography.headlineSmall,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = "校园 $campusId · 学号 $eduId",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (!profile.bio.isNullOrBlank()) {
                Spacer(modifier = Modifier.height(10.dp))
                Text(text = profile.bio, style = MaterialTheme.typography.bodyMedium)
            }
            val studyInfo = listOfNotNull(profile.major, profile.grade)
                .filter { it.isNotBlank() }
                .joinToString(" · ")
            if (studyInfo.isNotBlank()) {
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = studyInfo,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!profile.is_profile_complete) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "完善社区资料后可参与发布与互动",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedButton(onClick = onEdit, modifier = Modifier.fillMaxWidth()) {
                androidx.compose.material3.Icon(Icons.Outlined.Edit, contentDescription = null)
                Text("编辑资料", modifier = Modifier.padding(start = 8.dp))
            }
        }
    }
}
