package com.myleafy.android.features.campus

import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class CampusUiState(
    val featureName: String = "校园",
)

class CampusViewModel : ViewModel() {
    private val _uiState = MutableStateFlow(CampusUiState())
    val uiState: StateFlow<CampusUiState> = _uiState.asStateFlow()
}
