package com.myleafy.android.features.profile

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Android 应用内更新检查。MyLeafy Android 不上架应用商店，发行包由仓库的
 * GitHub Releases（tag `android-vX.Y.Z`，asset `MyLeafy-Android-X.Y.Z.apk`）提供。
 */
private const val releasesUrl = "https://api.github.com/repos/IsaacHuo/MyLeafy/releases?per_page=30"

@Serializable
private data class GithubAsset(
    val name: String,
    val browser_download_url: String,
    val size: Long = 0,
)

@Serializable
private data class GithubRelease(
    val tag_name: String,
    val name: String? = null,
    val body: String? = null,
    val draft: Boolean = false,
    val prerelease: Boolean = false,
    val assets: List<GithubAsset> = emptyList(),
)

data class AppUpdateInfo(
    val versionName: String,
    val tagName: String,
    val releaseNotes: String?,
    val apkUrl: String,
    val apkName: String,
    val sizeBytes: Long,
)

object AppVersion {
    /** 解析 `android-v1.2.3` / `1.2.3-debug` 为可比较的数字段。 */
    fun parse(value: String): List<Int>? {
        val raw = value.removePrefix("android-v").removePrefix("v")
        val numbers = raw.split('.', '-')
            .mapNotNull { it.toIntOrNull() }
        return numbers.ifEmpty { null }
    }

    fun isNewer(candidate: List<Int>, current: List<Int>): Boolean = compareVersions(candidate, current) > 0

    fun compareVersions(a: List<Int>, b: List<Int>): Int {
        for (index in 0 until maxOf(a.size, b.size)) {
            val left = a.getOrElse(index) { 0 }
            val right = b.getOrElse(index) { 0 }
            if (left != right) return left.compareTo(right)
        }
        return 0
    }
}

class AppUpdateRepository(private val context: Context) {

    private val json = Json { ignoreUnknownKeys = true }
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    /** 返回可用的新版本；已是最新或无 Android 发行包时返回 null。 */
    suspend fun check(currentVersionName: String): AppUpdateInfo? = withContext(Dispatchers.IO) {
        val current = AppVersion.parse(currentVersionName) ?: return@withContext null
        val request = Request.Builder()
            .url(releasesUrl)
            .header("Accept", "application/vnd.github+json")
            .header("User-Agent", "MyLeafy-Android")
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw IllegalStateException("检查更新失败（HTTP ${response.code}）")
            }
            val body = response.body?.string().orEmpty()
            val releases = json.decodeFromString<List<GithubRelease>>(body)
            val latest = releases.asSequence()
                .filter { !it.draft && !it.prerelease }
                .filter { it.tag_name.startsWith("android-v") }
                .mapNotNull { release ->
                    val version = AppVersion.parse(release.tag_name) ?: return@mapNotNull null
                    val asset = release.assets.firstOrNull { it.name.endsWith(".apk", ignoreCase = true) }
                        ?: return@mapNotNull null
                    Triple(release, version, asset)
                }
                .filter { AppVersion.isNewer(it.second, current) }
                .maxWithOrNull { left, right -> AppVersion.compareVersions(left.second, right.second) }
                ?: return@withContext null
            AppUpdateInfo(
                versionName = latest.second.joinToString("."),
                tagName = latest.first.tag_name,
                releaseNotes = latest.first.body?.takeIf { it.isNotBlank() },
                apkUrl = latest.third.browser_download_url,
                apkName = latest.third.name,
                sizeBytes = latest.third.size,
            )
        }
    }

    /** 下载 APK 到缓存目录，返回可用于安装的本地文件。 */
    suspend fun download(info: AppUpdateInfo, onProgress: (Float) -> Unit): File = withContext(Dispatchers.IO) {
        val directory = File(context.cacheDir, "updates").apply { mkdirs() }
        val file = File(directory, info.apkName)
        val request = Request.Builder()
            .url(info.apkUrl)
            .header("User-Agent", "MyLeafy-Android")
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw IllegalStateException("下载失败（HTTP ${response.code}）")
            }
            val body = response.body ?: throw IllegalStateException("下载响应为空")
            val total = info.sizeBytes.takeIf { it > 0 } ?: body.contentLength()
            body.byteStream().use { input ->
                file.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var read = 0L
                    var lastReported = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        read += count
                        if (total > 0 && read - lastReported >= 256 * 1024) {
                            lastReported = read
                            onProgress((read.toFloat() / total).coerceIn(0f, 1f))
                        }
                    }
                }
            }
        }
        onProgress(1f)
        file
    }
}

sealed interface UpdateUiState {
    data object Idle : UpdateUiState
    data object Checking : UpdateUiState
    data class UpToDate(val currentVersion: String) : UpdateUiState
    data class Available(val info: AppUpdateInfo) : UpdateUiState
    data class Downloading(val info: AppUpdateInfo, val progress: Float) : UpdateUiState
    data class Downloaded(val info: AppUpdateInfo, val file: File) : UpdateUiState
    data class Error(val message: String) : UpdateUiState
}

class CheckUpdatesViewModel(
    private val repository: AppUpdateRepository,
    private val currentVersionName: String,
) : ViewModel() {

    private val _uiState = MutableStateFlow<UpdateUiState>(UpdateUiState.Idle)
    val uiState: StateFlow<UpdateUiState> = _uiState.asStateFlow()

    init {
        check()
    }

    fun check() {
        if (_uiState.value is UpdateUiState.Checking || _uiState.value is UpdateUiState.Downloading) return
        _uiState.value = UpdateUiState.Checking
        viewModelScope.launch {
            _uiState.value = runCatching { repository.check(currentVersionName) }.fold(
                onSuccess = { info ->
                    if (info == null) UpdateUiState.UpToDate(currentVersionName) else UpdateUiState.Available(info)
                },
                onFailure = { UpdateUiState.Error(it.message ?: "检查更新失败") },
            )
        }
    }

    fun download(info: AppUpdateInfo) {
        if (_uiState.value is UpdateUiState.Downloading) return
        _uiState.value = UpdateUiState.Downloading(info, 0f)
        viewModelScope.launch {
            _uiState.value = runCatching {
                repository.download(info) { progress ->
                    _uiState.value = UpdateUiState.Downloading(info, progress)
                }
            }.fold(
                onSuccess = { UpdateUiState.Downloaded(info, it) },
                onFailure = { UpdateUiState.Error(it.message ?: "下载失败") },
            )
        }
    }
}
