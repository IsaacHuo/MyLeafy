package com.myleafy.android.features.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.automirrored.outlined.Login
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.CloudSync
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Feedback
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.SystemUpdate
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Wallpaper
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.navigation.FeatureDestination
import com.myleafy.android.shared.model.ProfileDto
import com.myleafy.android.ui.components.LeafyAlertDialog
import com.myleafy.android.ui.components.LeafyContentSurface
import com.myleafy.android.ui.components.LeafyDestructiveButton
import com.myleafy.android.ui.components.LeafyLoadingState
import com.myleafy.android.ui.components.LeafyRootTopBar
import com.myleafy.android.ui.components.LeafySettingsDivider
import com.myleafy.android.ui.components.LeafySettingsGroup
import com.myleafy.android.ui.components.LeafySettingsRow
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafySecondaryButton
import com.myleafy.android.ui.components.LeafyTextButton
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.theme.LeafyComponentSize
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.leafySurfaces
import androidx.compose.ui.graphics.vector.ImageVector

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
    LifecycleResumeEffect(Unit) {
        viewModel.refreshProfile()
        onPauseOrDispose { }
    }

    ProfileContent(
        state = uiState,
        isSigningOut = isSigningOut,
        onLoginClick = onLoginClick,
        onEditProfileClick = onEditProfileClick,
        onFeatureClick = onFeatureClick,
        onLogout = viewModel::logout,
        modifier = modifier,
    )
}

/**
 * 由 state 驱动的“我的”页面：只消费 state 与回调，供截图与预览使用。
 * 退出确认弹窗的开合是本页的瞬时 UI 状态，不参与进程重建恢复，
 * 因此用 remember 而不是 rememberSaveable——恢复语义与抽取前保持一致。
 */
@Composable
fun ProfileContent(
    state: ProfileUiState,
    isSigningOut: Boolean,
    onLoginClick: () -> Unit,
    onEditProfileClick: () -> Unit,
    onFeatureClick: (FeatureDestination) -> Unit,
    onLogout: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var confirmLogout by remember { mutableStateOf(false) }
    if (confirmLogout) {
        LeafyAlertDialog(
            onDismissRequest = { confirmLogout = false },
            title = { Text("退出登录") },
            text = { Text("将清理学校和社区会话及本机保存的登录凭据；课表、日程、随记和学业缓存会按当前身份保留。") },
            confirmButton = {
                LeafyTextButton(onClick = {
                    confirmLogout = false
                    onLogout()
                }) { Text("退出") }
            },
            dismissButton = { LeafyTextButton(onClick = { confirmLogout = false }) { Text("取消") } },
        )
    }

    Scaffold(
        modifier = modifier,
        containerColor = MaterialTheme.leafySurfaces.page,
        topBar = { LeafyRootTopBar(title = "我的") },
    ) { contentPadding ->
        Box(
            modifier = Modifier.fillMaxSize().padding(contentPadding),
            contentAlignment = Alignment.TopCenter,
        ) {
            LazyColumn(
                modifier = Modifier.widthIn(max = LeafyComponentSize.contentMaxWidth).fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(LeafySpacing.page),
                verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
            ) {
            item {
                when (val profileState = state) {
                    is ProfileUiState.Local -> {
                        val eduId = profileState.eduId?.takeIf { it.isNotBlank() }
                        ProfileEntry(
                            title = if (eduId != null) "MyLeafy" else "登录学校账号",
                            subtitle = if (eduId != null) {
                                "校园 ${profileState.campusId} · 学号 $eduId"
                            } else {
                                "尚未绑定学校身份，登录后可同步课表与成绩"
                            },
                            avatarLabel = eduId ?: "我",
                            onClick = if (eduId == null) onLoginClick else null,
                        )
                    }
                    is ProfileUiState.ProfileLoading -> {
                        ProfileEntry(
                            title = "正在加载资料…",
                            subtitle = "读取当前校园身份",
                            avatarLabel = "我",
                            onClick = null,
                        )
                    }
                    is ProfileUiState.Community -> {
                        val name = profileState.profile.nickname.ifBlank {
                            profileState.profile.display_name ?: "未命名"
                        }
                        ProfileEntry(
                            title = name,
                            subtitle = buildString {
                                append("校园 ${profileState.campusId} · 学号 ${profileState.eduId}")
                                if (!profileState.profile.is_profile_complete) append(" · 资料待完善")
                            },
                            avatarLabel = name,
                            onClick = onEditProfileClick,
                        )
                    }
                    is ProfileUiState.Error -> {
                        Column(verticalArrangement = Arrangement.spacedBy(LeafySpacing.micro)) {
                            ProfileEntry(
                                title = "MyLeafy",
                                subtitle = buildString {
                                    append("校园 ${profileState.campusId}")
                                    profileState.eduId?.takeIf { it.isNotBlank() }?.let { append(" · 学号 $it") }
                                },
                                avatarLabel = profileState.eduId ?: "我",
                                onClick = null,
                            )
                            LeafyStatusBanner(message = profileState.message, isError = true)
                        }
                    }
                }
            }


            item {
                LeafySettingsGroup(title = "数据与偏好") {
                    ProfileDestinationRow(
                        title = "缓存与同步",
                        description = "检查本地数据与学校同步状态",
                        icon = Icons.Outlined.CloudSync,
                        onClick = { onFeatureClick(FeatureDestination.PROFILE_SYNC) },
                    )
                    LeafySettingsDivider()
                    ProfileDestinationRow(
                        title = "共享课表",
                        description = "邀请同学查看课程安排",
                        icon = Icons.Outlined.People,
                        onClick = { onFeatureClick(FeatureDestination.PROFILE_SHARING) },
                    )
                    LeafySettingsDivider()
                    ProfileDestinationRow(
                        title = "课表背景",
                        description = "照片、纯色、模糊与课程块透明度",
                        icon = Icons.Outlined.Wallpaper,
                        onClick = { onFeatureClick(FeatureDestination.TIMETABLE_BACKGROUND) },
                    )
                    LeafySettingsDivider()
                    ProfileDestinationRow(
                        title = "个性化",
                        description = "主题、文字与课表列数",
                        icon = Icons.Outlined.AutoAwesome,
                        onClick = { onFeatureClick(FeatureDestination.PROFILE_PERSONALIZATION) },
                    )
                }
            }

            item {
                LeafySettingsGroup(title = "帮助与安全") {
                    ProfileDestinationRow(
                        title = "检查更新",
                        description = "获取最新的 Android 安装包",
                        icon = Icons.Outlined.SystemUpdate,
                        onClick = { onFeatureClick(FeatureDestination.PROFILE_UPDATE) },
                    )
                    LeafySettingsDivider()
                    ProfileDestinationRow(
                        title = "帮助中心",
                        description = "使用指南、常见问题与数据安全",
                        icon = Icons.AutoMirrored.Outlined.HelpOutline,
                        onClick = { onFeatureClick(FeatureDestination.PROFILE_HELP) },
                    )
                    LeafySettingsDivider()
                    ProfileDestinationRow(
                        title = "系统权限",
                        description = "了解权限用途并打开 Android 设置",
                        icon = Icons.Outlined.Lock,
                        onClick = { onFeatureClick(FeatureDestination.PROFILE_PERMISSIONS) },
                    )
                    LeafySettingsDivider()
                    ProfileDestinationRow(
                        title = "反馈与支持",
                        description = "提交问题、建议或联系项目支持",
                        icon = Icons.Outlined.Feedback,
                        onClick = { onFeatureClick(FeatureDestination.PROFILE_FEEDBACK) },
                    )
                }
            }

            item {
                LeafySettingsGroup(title = "项目") {
                    ProfileDestinationRow(
                        title = "关于 MyLeafy",
                        description = "项目、版本、开源与支持信息",
                        icon = Icons.Outlined.Info,
                        onClick = { onFeatureClick(FeatureDestination.PROFILE_ABOUT) },
                    )
                }
            }
            val hasIdentity = when (state) {
                is ProfileUiState.Community -> true
                is ProfileUiState.Local -> !state.eduId.isNullOrBlank()
                is ProfileUiState.Error -> !state.eduId.isNullOrBlank()
                ProfileUiState.ProfileLoading -> true
            }
            if (hasIdentity) {
                item {
                    LeafyDestructiveButton(
                        onClick = { confirmLogout = true },
                        enabled = !isSigningOut,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        androidx.compose.material3.Icon(Icons.AutoMirrored.Outlined.Logout, contentDescription = null)
                        Text(
                            if (isSigningOut) "正在退出…" else "退出登录",
                            modifier = Modifier.padding(start = LeafySpacing.micro),
                        )
                    }
                }
            }
            }
        }
    }
}

@Composable
private fun ProfileEntry(
    title: String,
    subtitle: String,
    avatarLabel: String,
    onClick: (() -> Unit)?,
) {
    LeafySettingsRow(
        headlineContent = { Text(title, style = MaterialTheme.typography.titleSmall) },
        supportingContent = {
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
        leadingContent = { ProfileAvatar(avatarLabel) },
        trailingContent = {
            if (onClick != null) {
                Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null)
            }
        },
        onClick = onClick,
    )
}

@Composable
private fun ProfileAvatar(label: String) {
    Surface(
        modifier = Modifier.size(LeafyComponentSize.featureIconContainer),
        shape = CircleShape,
        color = MaterialTheme.leafySurfaces.accentSoft,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                text = label.trim().take(1).ifBlank { "我" },
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

@Composable
private fun ProfileDestinationRow(
    title: String,
    description: String,
    icon: ImageVector,
    onClick: () -> Unit,
) {
    LeafySettingsRow(
        headlineContent = { Text(title, style = MaterialTheme.typography.titleSmall) },
        supportingContent = {
            Text(
                description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
        leadingContent = {
            Surface(
                modifier = Modifier.size(LeafyComponentSize.settingsIconContainer),
                shape = MaterialTheme.shapes.medium,
                color = MaterialTheme.leafySurfaces.accentSoft,
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(icon, contentDescription = null, modifier = Modifier.size(LeafyIconSize.standard))
                }
            }
        },
        trailingContent = {
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null)
        },
        onClick = onClick,
    )
}
