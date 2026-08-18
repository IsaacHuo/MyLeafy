package com.myleafy.android.features.community

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.ui.components.FeaturePlaceholder

@Composable
fun CommunityScreen(
    viewModel: CommunityViewModel = viewModel(
        factory = appViewModelFactory { container ->
            CommunityViewModel(repository = container.communityRepository)
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()
    FeaturePlaceholder(
        featureName = if (uiState.isAvailable) "社区" else "社区（当前校园未启用）",
        modifier = modifier,
    )
}
