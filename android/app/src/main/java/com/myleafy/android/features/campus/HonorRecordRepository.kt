package com.myleafy.android.features.campus

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.data.local.HonorRecordDao
import com.myleafy.android.core.data.local.HonorRecordEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID

/**
 * 荣誉记录（奖状证书文件）本地仓储。文件保存在 App 私有目录，按身份 scopeKey 隔离，
 * 不连接教务或 Supabase。
 */
@OptIn(ExperimentalCoroutinesApi::class)
class HonorRecordRepository(
    private val context: Context,
    private val dao: HonorRecordDao,
    private val scopeStore: ActiveAppScopeStore,
) {
    fun records(): Flow<List<HonorRecordEntity>> =
        scopeStore.scope.flatMapLatest { dao.all(it.scopeKey) }

    suspend fun importFile(uri: Uri, title: String): String = withContext(Dispatchers.IO) {
        val scopeKey = scopeStore.current.scopeKey
        val resolver = context.contentResolver
        val displayName = queryDisplayName(uri) ?: "honor"
        val mime = resolver.getType(uri) ?: "application/octet-stream"
        val id = UUID.randomUUID().toString()
        val extension = displayName.substringAfterLast('.', "").ifBlank { extensionFor(mime) }
        val localFilename = if (extension.isBlank()) id else "$id.$extension"
        val directory = File(context.filesDir, "HonorRecords/$scopeKey").apply { mkdirs() }
        resolver.openInputStream(uri)?.use { input ->
            File(directory, localFilename).outputStream().use { input.copyTo(it) }
        } ?: error("无法读取所选文件")
        val now = System.currentTimeMillis()
        dao.upsert(
            HonorRecordEntity(
                scopeKey = scopeKey,
                id = id,
                title = title.ifBlank { displayName },
                note = "",
                awardedAt = null,
                originalFilename = displayName,
                localFilename = localFilename,
                contentType = mime,
                importedAt = now,
                updatedAt = now,
            ),
        )
        id
    }

    suspend fun update(record: HonorRecordEntity, title: String, note: String, awardedAt: Long?) {
        dao.upsert(
            record.copy(
                title = title.ifBlank { record.originalFilename },
                note = note,
                awardedAt = awardedAt,
                updatedAt = System.currentTimeMillis(),
            ),
        )
    }

    suspend fun delete(record: HonorRecordEntity) = withContext(Dispatchers.IO) {
        fileFor(record).delete()
        dao.delete(record.scopeKey, record.id)
    }

    fun fileFor(record: HonorRecordEntity): File =
        File(context.filesDir, "HonorRecords/${record.scopeKey}/${record.localFilename}")

    private fun queryDisplayName(uri: Uri): String? = runCatching {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }.getOrNull()

    private fun extensionFor(mime: String): String = when (mime) {
        "application/pdf" -> "pdf"
        "image/jpeg" -> "jpg"
        "image/png" -> "png"
        "image/webp" -> "webp"
        else -> "bin"
    }
}

class HonorRecordsViewModel(
    private val repository: HonorRecordRepository,
) : ViewModel() {

    val records: StateFlow<List<HonorRecordEntity>> = repository.records()
        .catch { emit(emptyList()) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    fun import(uri: Uri, title: String) {
        viewModelScope.launch {
            runCatching { repository.importFile(uri, title) }
                .onFailure { _message.value = it.message ?: "导入失败" }
        }
    }

    fun update(record: HonorRecordEntity, title: String, note: String, awardedAt: Long?) {
        viewModelScope.launch {
            runCatching { repository.update(record, title, note, awardedAt) }
                .onFailure { _message.value = it.message ?: "保存失败" }
        }
    }

    fun delete(record: HonorRecordEntity) {
        viewModelScope.launch {
            runCatching { repository.delete(record) }
                .onFailure { _message.value = it.message ?: "删除失败" }
        }
    }

    fun fileFor(record: HonorRecordEntity): File = repository.fileFor(record)

    fun reportError(message: String) {
        _message.value = message
    }

    fun consumeMessage() {
        _message.value = null
    }
}
