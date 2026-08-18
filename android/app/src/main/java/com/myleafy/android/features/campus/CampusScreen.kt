package com.myleafy.android.features.campus

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.ui.components.FeaturePlaceholder

@Composable
fun CampusScreen(
    viewModel: CampusViewModel = viewModel(
        factory = appViewModelFactory { CampusViewModel() },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()
    FeaturePlaceholder(featureName = uiState.featureName, modifier = modifier)
}
