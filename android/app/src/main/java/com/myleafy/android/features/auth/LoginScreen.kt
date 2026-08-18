package com.myleafy.android.features.auth

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.ui.components.FeaturePlaceholder

/**
 * 学校登录页。阶段 1 未接入导航，仅在身份恢复（hasCachedIdentity 为假）
 * 时显示；阶段 2 接入强智/研究生登录流程与验证码。
 */
@Composable
fun LoginScreen(
    viewModel: LoginViewModel = viewModel(
        factory = appViewModelFactory { container ->
            LoginViewModel(repository = container.authRepository)
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()
    FeaturePlaceholder(
        featureName = if (uiState.hasCachedIdentity) "已登录" else "登录",
        modifier = modifier,
    )
}
