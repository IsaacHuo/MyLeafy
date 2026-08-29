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
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.People
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
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
    onFeatureClick: (FeatureDestination) -> Unit = {},
    viewModel: ProfileViewModel = viewModel(
        factory = appViewModelFactory { container ->
            ProfileViewModel(
                repository = container.profileRepository,
                settings = container.settingsStore,
            )
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()

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
                    is ProfileUiState.Community -> ProfileCard(state.campusId, state.eduId, state.profile)
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

            item { LeafySectionHeader(title = "项目", modifier = Modifier.padding(top = 8.dp)) }
            item {
                LeafyFeatureCard(
                    title = "关于 MyLeafy",
                    description = "项目、版本、开源与支持信息",
                    icon = Icons.Outlined.Info,
                    onClick = { onFeatureClick(FeatureDestination.PROFILE_ABOUT) },
                )
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
private fun ProfileCard(campusId: String, eduId: String, profile: ProfileDto) {
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
        }
    }
}
