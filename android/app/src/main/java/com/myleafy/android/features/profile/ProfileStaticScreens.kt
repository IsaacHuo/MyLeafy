package com.myleafy.android.features.profile

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.myleafy.android.BuildConfig
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyButtonDefaults
import com.myleafy.android.ui.components.LeafyContentSurface
import com.myleafy.android.ui.components.leafyMinimumTouchTarget
import com.myleafy.android.ui.theme.LeafySpacing

private data class InfoBlock(val title: String, val body: String)

@Composable
fun HelpCenterScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    val chapters = listOf(
        InfoBlock(
            "开始使用",
            "MyLeafy 将课表、社区、日迹、校园和个人设置集中在五个主入口。Android 版本会逐步迁移 iOS 已有能力；暂未接入的功能会明确标注，不会用模拟数据代替真实结果。",
        ),
        InfoBlock(
            "学校系统与校园网",
            "课表、成绩、考试和空闲教室等数据来自学校教务系统。MyLeafy 是第三方校园应用，不属于学校官方系统。相关结果以学校系统为准，且主动同步通常需要能够访问教务的校园网络或学校认可的 VPN。",
        ),
        InfoBlock(
            "本机数据",
            "随记和个人日程以当前设备为权威来源，保存在 App 本地数据库中。卸载 App、清除应用数据或更换设备前，请先确认是否需要保留这些内容。",
        ),
        InfoBlock(
            "社区与云端数据",
            "主动发布的帖子、评论、点赞、社区资料与共享内容会提交到 MyLeafy 社区服务。成绩、考试、随记和个人日程不会因为进入社区而自动上传。",
        ),
        InfoBlock(
            "同步失败怎么办",
            "先确认浏览器能够访问学校教务，再检查登录状态和验证码。如果学校系统只允许校内网络访问，请断开会接管全部流量的代理，或为学校域名配置直连。同步失败不会主动删除最近一次成功缓存。",
        ),
        InfoBlock(
            "数据安全边界",
            "教务账号和密码仅用于向学校系统发起用户授权的登录请求，并存放在 Android Keystore 保护的本机存储中。社区使用独立服务与权限规则。请勿在帖子、评论或反馈中发布自己或他人的敏感信息。",
        ),
    )

    LeafySecondaryScaffold(title = "帮助中心", onBack = onBack, modifier = modifier) { contentModifier ->
        LazyColumn(
            modifier = contentModifier
                .fillMaxSize()
                .testTag("help-content"),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            item {
                Text(
                    text = "使用指南、常见问题与数据安全",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = "以下说明基于当前 Android 实现和 MyLeafy 的跨平台数据边界。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            chapters.forEach { chapter ->
                item { InfoCard(chapter) }
            }
            item {
                ExternalLinkButton(
                    label = "访问在线支持",
                    uri = "https://myleafy.space/support",
                    icon = Icons.Outlined.Language,
                )
            }
        }
    }
}

@Composable
fun PermissionsInfoScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    LeafySecondaryScaffold(title = "系统权限", onBack = onBack, modifier = modifier) { contentModifier ->
        LazyColumn(
            modifier = contentModifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            item {
                InfoCard(
                    InfoBlock(
                        "网络访问",
                        "用于连接用户主动选择的学校系统与 MyLeafy 社区服务。网络权限由 Android 在安装时授予，不读取联系人、短信或通话记录。",
                    ),
                )
            }
            item {
                InfoCard(
                    InfoBlock(
                        "通知",
                        "未来用于课程、考试和个人日程提醒。Android 13 及以上会在真正启用提醒时请求通知权限；当前骨架不会提前请求。",
                    ),
                )
            }
            item {
                InfoCard(
                    InfoBlock(
                        "照片与文件",
                        "未来导入图片或附件时优先使用 Android 系统选择器，只访问用户明确选择的内容。拒绝权限只会影响相应功能。",
                    ),
                )
            }
            item {
                InfoCard(
                    InfoBlock(
                        "凭据与本地存储",
                        "教务凭据和会话 Cookie 使用 Android Keystore 保护；课表、成绩缓存、随记和日程保存在 App 私有空间。",
                    ),
                )
            }
            item {
                Button(
                    onClick = {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:${context.packageName}"),
                        )
                        context.startActivity(intent)
                    },
                    modifier = Modifier.fillMaxWidth().leafyMinimumTouchTarget(),
                    shape = LeafyButtonDefaults.shape,
                ) {
                    Icon(Icons.Outlined.Security, contentDescription = null)
                    Text("打开 Android 应用设置", modifier = Modifier.padding(start = LeafySpacing.micro))
                }
            }
        }
    }
}

@Composable
fun FeedbackScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    LeafySecondaryScaffold(title = "反馈与支持", onBack = onBack, modifier = modifier) { contentModifier ->
        LazyColumn(
            modifier = contentModifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            item {
                InfoCard(
                    InfoBlock(
                        "提交反馈前",
                        "请说明所用校园、功能入口、复现步骤和错误提示。涉及教务问题时不要发送密码、Cookie、验证码或完整学号。",
                    ),
                )
            }
            item {
                ExternalLinkButton(
                    label = "发送支持邮件",
                    uri = "mailto:support@myleafy.space?subject=MyLeafy%20Android%20反馈",
                    icon = Icons.Outlined.Email,
                )
            }
            item {
                ExternalLinkButton(
                    label = "打开在线支持",
                    uri = "https://myleafy.space/support",
                    icon = Icons.Outlined.Language,
                )
            }
        }
    }
}

@Composable
fun AboutMyLeafyScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    LeafySecondaryScaffold(title = "关于 MyLeafy", onBack = onBack, modifier = modifier) { contentModifier ->
        LazyColumn(
            modifier = contentModifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            item {
                LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(LeafySpacing.page)) {
                        Text(
                            text = "MyLeafy",
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Spacer(modifier = Modifier.height(LeafySpacing.micro))
                        Text(
                            text = "面向高校学习与校园生活的原生应用，将课表、学业数据、个人记录和校园社区组织在一个清晰的工作流中。",
                            style = MaterialTheme.typography.bodyLarge,
                        )
                        HorizontalDivider(modifier = Modifier.padding(vertical = LeafySpacing.card))
                        Text(
                            text = "Android ${BuildConfig.VERSION_NAME} · build ${BuildConfig.VERSION_CODE}",
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            text = "Apache License 2.0",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            item {
                ExternalLinkButton(
                    label = "项目官网",
                    uri = "https://myleafy.space/",
                    icon = Icons.Outlined.Language,
                )
            }
            item {
                ExternalLinkButton(
                    label = "GitHub 开源仓库",
                    uri = "https://github.com/IsaacHuo/MyLeafy",
                    icon = Icons.Outlined.Code,
                )
            }
            item {
                ExternalLinkButton(
                    label = "隐私政策",
                    uri = "https://myleafy.space/privacy",
                    icon = Icons.Outlined.Lock,
                )
            }
            item {
                ExternalLinkButton(
                    label = "联系支持",
                    uri = "mailto:support@myleafy.space",
                    icon = Icons.Outlined.Email,
                )
            }
        }
    }
}

@Composable
private fun InfoCard(block: InfoBlock) {
    LeafyContentSurface(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(LeafySpacing.card)) {
            Text(text = block.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Spacer(modifier = Modifier.height(LeafySpacing.micro))
            Text(
                text = block.body,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ExternalLinkButton(
    label: String,
    uri: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
) {
    val context = LocalContext.current
    OutlinedButton(
        onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri))) },
        modifier = Modifier.fillMaxWidth().leafyMinimumTouchTarget(),
        shape = LeafyButtonDefaults.shape,
    ) {
        Row(modifier = Modifier.fillMaxWidth()) {
            Icon(icon, contentDescription = null)
            Text(label, modifier = Modifier.padding(start = LeafySpacing.compact).weight(1f))
            Icon(Icons.AutoMirrored.Outlined.OpenInNew, contentDescription = null)
        }
    }
}
