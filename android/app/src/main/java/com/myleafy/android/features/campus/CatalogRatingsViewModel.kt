package com.myleafy.android.features.campus

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.services.cloudflare.RatingCatalogKind
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

data class CatalogRatingsUiState(
    val scopeKey: String = "",
    val kind: RatingCatalogKind = RatingCatalogKind.TEACHER,
    val items: List<CatalogRatingItem> = emptyList(),
    val search: String = "",
    val filterValue: String? = null,
    val canteen: String? = null,
    val stars: Int? = null,
    val options: List<String> = emptyList(),
    val loading: Boolean = false,
    val saving: Boolean = false,
    val error: String? = null,
    val hasMore: Boolean = false,
)

class CatalogRatingsViewModel(private val repository: CatalogRatingRepository) : ViewModel() {
    private val mutableState = MutableStateFlow(CatalogRatingsUiState(scopeKey = repository.currentScopeKey))
    val uiState = mutableState.asStateFlow()
    val available get() = repository.isAvailable
    private var initialized = false
    private var identity = repository.currentScopeKey
    private val workspaces = mutableMapOf<RatingCatalogKind, CatalogRatingsUiState>()
    private var request: Job? = null
    private var debounce: Job? = null
    private var generation = 0
    init { viewModelScope.launch { repository.scopeKeys.collect { scope ->
        if (identity != scope.scopeKey) {
            identity = scope.scopeKey; request?.cancel(); debounce?.cancel(); generation++; workspaces.clear(); initialized = false
            mutableState.value = CatalogRatingsUiState(scopeKey = identity)
        }
    } } }
    fun initialize(search: String) {
        if (initialized) return
        initialized = true; mutableState.value = mutableState.value.copy(search = search); refresh()
    }
    fun selectKind(kind: RatingCatalogKind) {
        if (kind == mutableState.value.kind) return
        workspaces[mutableState.value.kind] = mutableState.value.copy(loading = false, saving = false)
        debounce?.cancel(); request?.cancel(); generation++
        mutableState.value = workspaces[kind] ?: CatalogRatingsUiState(scopeKey = identity, kind = kind)
        if (mutableState.value.items.isEmpty()) refresh()
    }
    fun search(query: String) {
        request?.cancel(); debounce?.cancel(); generation++
        mutableState.value = mutableState.value.copy(search = query, items = emptyList(), loading = false)
        debounce = viewModelScope.launch { delay(300); load(false) }
    }
    fun setFilter(value: String?) { mutableState.value = mutableState.value.copy(filterValue = value, items = emptyList()); refresh() }
    fun setCanteen(value: String?) { mutableState.value = mutableState.value.copy(canteen = value, filterValue = null, items = emptyList()); refresh() }
    fun setStars(value: Int?) { mutableState.value = mutableState.value.copy(stars = value) }
    fun clearFilters() { mutableState.value = mutableState.value.copy(filterValue = null, canteen = null, stars = null, items = emptyList()); refresh() }
    fun refresh() { debounce?.cancel(); load(false) }
    fun loadMore() = load(true)
    fun rate(itemId: Long, stars: Int) {
        val snapshot = mutableState.value
        if (snapshot.saving) return
        val scope = identity
        mutableState.value = snapshot.copy(saving = true, error = null)
        viewModelScope.launch {
            try {
                val updated = repository.rate(snapshot.kind, itemId, stars)
                if (scope != identity) return@launch
                val previous = mutableState.value.items.firstOrNull { it.profile.id == itemId }
                if (mutableState.value.kind == snapshot.kind) mutableState.value = mutableState.value.copy(items = mutableState.value.items.map { if (it.profile.id == itemId) updated.copy(localTeachers = previous?.localTeachers.orEmpty()) else it }, saving = false)
                else workspaces[snapshot.kind] = (workspaces[snapshot.kind] ?: snapshot).let { it.copy(items = it.items.map { row -> if (row.profile.id == itemId) updated.copy(localTeachers = row.localTeachers) else row }, saving = false) }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { if (scope == identity && mutableState.value.kind == snapshot.kind) mutableState.value = mutableState.value.copy(error = failure.message ?: "评分失败", saving = false) }
        }
    }
    fun suggest(name: String, unit: String, teacher: String?, category: String?, credit: Double?, stars: Int?, note: String?, onSaved: () -> Unit) {
        val snapshot = mutableState.value
        if (snapshot.saving) return
        val scope = identity
        mutableState.value = snapshot.copy(saving = true, error = null)
        viewModelScope.launch { try {
            repository.suggest(snapshot.kind, name, unit, teacher, category, credit, stars, note)
            if (scope == identity && mutableState.value.kind == snapshot.kind) { mutableState.value = mutableState.value.copy(saving = false, error = null); onSaved() }
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { if (scope == identity && mutableState.value.kind == snapshot.kind) mutableState.value = mutableState.value.copy(saving = false, error = failure.message ?: "建议提交失败") }
        }
    }
    private fun load(append: Boolean) {
        if (append && mutableState.value.loading) return
        request?.cancel(); val version = ++generation; val snapshot = mutableState.value
        val scope = identity
        if (!available) return
        mutableState.value = snapshot.copy(loading = true, error = null)
        request = viewModelScope.launch {
            try { val page = repository.page(snapshot.kind, snapshot.search, snapshot.filterValue, if (append) snapshot.items.size else 0, canteen = snapshot.canteen)
                if (version != generation || scope != identity) return@launch
                val options = page.mapNotNull { when (snapshot.kind) { RatingCatalogKind.TEACHER -> it.profile.unit; RatingCatalogKind.COURSE -> it.profile.category; RatingCatalogKind.DISH -> it.profile.location } }
                mutableState.value = mutableState.value.copy(items = (if (append) snapshot.items + page else page).distinctBy { it.profile.id }, options = (snapshot.options + options).distinct().sorted(), loading = false, hasMore = page.size == 20)
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { if (version == generation && scope == identity) mutableState.value = mutableState.value.copy(loading = false, error = failure.message ?: "评价列表加载失败") }
        }
    }
}
