package com.myleafy.android.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.School
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.MyLeafyTheme

@Preview(name = "Leafy components · Light", showBackground = true)
@Preview(name = "Leafy components · Dark", showBackground = true, uiMode = 0x20)
@Preview(name = "Leafy components · Large text", showBackground = true, fontScale = 1.3f)
@Composable
private fun LeafyComponentsPreview() {
    MyLeafyTheme {
        Column(
            modifier = Modifier.padding(LeafySpacing.page),
            verticalArrangement = Arrangement.spacedBy(LeafySpacing.card),
        ) {
            LeafySectionHeader(title = "学校教学", supportingText = "教务数据与学期安排")
            LeafyFeatureCard(
                title = "成绩与排名",
                description = "成绩明细、官方 GPA 与排名",
                icon = Icons.Outlined.School,
                onClick = {},
            )
            LeafyStatusBanner(message = "已更新到最新数据", isError = false)
            LeafyEmptyState(
                title = "还没有内容",
                message = "完成第一次同步后会显示在这里。",
                action = { Text("立即同步", color = MaterialTheme.colorScheme.primary) },
            )
        }
    }
}
