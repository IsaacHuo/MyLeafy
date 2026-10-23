package com.myleafy.android.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.myleafy.android.core.network.AcademicStep
import com.myleafy.android.core.network.AcademicStepStatus
import com.myleafy.android.ui.theme.LeafyAlpha
import com.myleafy.android.ui.theme.LeafyElevation
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.LeafyStroke
import com.myleafy.android.ui.theme.leafySurfaces

/**
 * 教务操作的过程卡片：运行中 spinner、已完成打勾、失败保留原因。
 * 与 iOS `AcademicOperationProgressCard` 的信息结构一致，不改变任何请求范围。
 */
@Composable
fun AcademicProgressCard(
    title: String,
    steps: List<AcademicStep>,
    modifier: Modifier = Modifier,
    maxHeight: Dp = 320.dp,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.leafySurfaces.content,
        border = BorderStroke(
            LeafyStroke.hairline,
            MaterialTheme.colorScheme.outlineVariant.copy(alpha = LeafyAlpha.cardBorder),
        ),
        shadowElevation = LeafyElevation.card,
    ) {
        Column(
            modifier = Modifier.padding(LeafySpacing.card),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        ) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            AcademicStepList(steps = steps, maxHeight = maxHeight)
        }
    }
}

/** 步骤列表本身；对话框里直接复用，避免再套一层卡片。 */
@Composable
fun AcademicStepList(
    steps: List<AcademicStep>,
    modifier: Modifier = Modifier,
    maxHeight: Dp = 320.dp,
) {
    Column(
        modifier = modifier
            .heightIn(max = maxHeight)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
    ) {
        steps.forEach { step -> AcademicStepRow(step) }
    }
}

@Composable
private fun AcademicStepRow(step: AcademicStep) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
        verticalAlignment = Alignment.Top,
    ) {
        when (step.status) {
            AcademicStepStatus.RUNNING -> CircularProgressIndicator(
                modifier = Modifier.size(LeafyIconSize.compact),
                strokeWidth = LeafyStroke.progress,
            )
            AcademicStepStatus.COMPLETED -> Icon(
                imageVector = Icons.Filled.CheckCircle,
                contentDescription = "已完成",
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(LeafyIconSize.compact),
            )
            AcademicStepStatus.FAILED -> Icon(
                imageVector = Icons.Outlined.Warning,
                contentDescription = "失败",
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(LeafyIconSize.compact),
            )
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.tiny),
        ) {
            Text(
                text = step.label,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            step.detail?.takeIf { it.isNotBlank() }?.let { detail ->
                Text(
                    text = detail,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (step.status == AcademicStepStatus.FAILED) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
            }
        }
    }
}
