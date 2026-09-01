package com.myleafy.android.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Construction
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.myleafy.android.navigation.FeatureDestination

/** 明确标记为未实现的二级功能页，不生成或伪装任何业务数据。 */
@Composable
fun FeaturePlaceholder(
    destination: FeatureDestination,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LeafySecondaryScaffold(title = destination.title, onBack = onBack, modifier = modifier) { contentModifier ->
        Column(modifier = contentModifier.fillMaxSize().padding(com.myleafy.android.ui.theme.LeafySpacing.page)) {
            LeafyEmptyState(
                title = "界面框架已就绪",
                message = destination.description,
                icon = Icons.Outlined.Construction,
            )
        }
    }
}
