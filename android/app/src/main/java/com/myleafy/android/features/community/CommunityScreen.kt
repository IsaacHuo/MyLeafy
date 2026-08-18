package com.myleafy.android.features.community

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.campus.ActiveCampusContext
import com.myleafy.android.core.di.appViewModelFactory

@Composable
fun CommunityScreen(
    viewModel: CommunityViewModel = viewModel(
        factory = appViewModelFactory { container ->
            CommunityViewModel(
                repository = container.communityRepository,
                campusId = ActiveCampusContext.descriptor.id.rawValue,
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
        Text(text = "社区", style = MaterialTheme.typography.headlineMedium)
        Spacer(modifier = Modifier.height(12.dp))

        when (val state = uiState) {
            is CommunityUiState.Loading -> {
                CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
            }

            is CommunityUiState.Error -> {
                Text(
                    text = state.message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            is CommunityUiState.Placeholder -> {
                Column(modifier = Modifier.padding(top = 24.dp)) {
                    Text(
                        text = state.message,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.outline,
                    )
                }
            }

            is CommunityUiState.Loaded -> {
                LazyColumn {
                    items(state.posts, key = { it.id }) { post ->
                        Card(modifier = Modifier.padding(bottom = 8.dp)) {
                            Column(modifier = Modifier.padding(12.dp)) {
                                Text(text = post.title, style = MaterialTheme.typography.titleSmall)
                                Text(
                                    text = post.body,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
