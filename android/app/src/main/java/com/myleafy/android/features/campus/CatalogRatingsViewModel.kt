package com.myleafy.android.features.campus

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.services.supabase.RatingCatalogKind
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class CatalogRatingsUiState(
    val kind: RatingCatalogKind = RatingCatalogKind.TEACHER,
    val items: List<CatalogRatingItem> = emptyList(),
    val search: String = "",
    val filterValue: String? = null,
    val loading: Boolean = false,
    val error: String? = null,
    val hasMore: Boolean = false,
)

class CatalogRatingsViewModel(private val repository: CatalogRatingRepository) : ViewModel() {
    private val mutableState = MutableStateFlow(CatalogRatingsUiState())
    val uiState: StateFlow<CatalogRatingsUiState> = mutableState.asStateFlow()
    val available: Boolean get() = repository.isAvailable

    fun selectKind(kind: RatingCatalogKind) {
        mutableState.value = CatalogRatingsUiState(kind = kind)
        refresh()
    }

    fun search(query: String) {
        mutableState.value = mutableState.value.copy(search = query)
    }

    fun setFilter(value: String?) {
        mutableState.value = mutableState.value.copy(filterValue = value)
        refresh()
    }

    fun refresh() = load(append = false)
    fun loadMore() = load(append = true)

    fun rate(itemId: Long, stars: Int) = viewModelScope.launch {
        runCatching { repository.rate(mutableState.value.kind, itemId, stars) }
            .onSuccess { refresh() }
            .onFailure { mutableState.value = mutableState.value.copy(error = it.message ?: "评分失败") }
    }

    fun suggest(name: String, unit: String, teacher: String?, category: String?, credit: Double?, stars: Int, note: String?) =
        viewModelScope.launch {
            runCatching { repository.suggest(mutableState.value.kind, name, unit, teacher, category, credit, stars, note) }
                .onSuccess { mutableState.value = mutableState.value.copy(error = null) }
                .onFailure { mutableState.value = mutableState.value.copy(error = it.message ?: "建议提交失败") }
        }

    private fun load(append: Boolean) = viewModelScope.launch {
        val snapshot = mutableState.value
        if (snapshot.loading || !available) return@launch
        mutableState.value = snapshot.copy(loading = true, error = null)
        val offset = if (append) snapshot.items.size else 0
        runCatching {
            repository.page(snapshot.kind, snapshot.search, snapshot.filterValue, offset)
        }.onSuccess { page ->
            mutableState.value = snapshot.copy(
                items = if (append) snapshot.items + page else page,
                loading = false,
                hasMore = page.size == 20,
                error = null,
            )
        }.onFailure {
            mutableState.value = snapshot.copy(loading = false, error = it.message ?: "评价列表加载失败")
        }
    }
}
