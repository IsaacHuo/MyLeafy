package com.myleafy.android.features.profile

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory

@Composable
fun ProfileScreen(
    onLoginClick: () -> Unit = {},
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

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(20.dp),
    ) {
        Text(text = "我的", style = MaterialTheme.typography.headlineMedium)
        Spacer(modifier = Modifier.height(12.dp))

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(text = uiState.campusId, style = MaterialTheme.typography.titleMedium)
                Text(
                    text = if (uiState.eduId.isNullOrBlank()) "未绑定学校身份" else "学号 ${uiState.eduId}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (uiState.isCommunityPlaceholder) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "社区资料将在阶段 4 接入 Supabase",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.outline,
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
        Row {
            Button(onClick = onLoginClick) {
                Text("去登录")
            }
        }
    }
}
