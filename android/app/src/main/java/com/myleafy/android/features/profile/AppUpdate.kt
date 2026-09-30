package com.myleafy.android.features.profile

import android.app.DownloadManager
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.lifecycle.ViewModel
import com.myleafy.android.BuildConfig
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

@Serializable
data class AppUpdateInfo(
    val id: String,
    val packageName: String,
    val channel: String,
    val versionCode: Int,
    val versionName: String,
    val minSdk: Int,
    val releaseNotes: String,
    val apkUrl: String,
    val apkName: String,
    val sizeBytes: Long,
    val sha256: String,
    val certificateSha256: String,
    val githubReleaseUrl: String,
)
@Serializable private data class LatestRelease(val release: AppUpdateInfo? = null)

object UpdateIntegrity {
    fun sha256(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    fun validatePackage(info: AppUpdateInfo, archive: UpdatePackageIdentity, installedSigners: Set<String>, sdk: Int) {
        check(archive.packageName == info.packageName && archive.versionCode == info.versionCode.toLong() && archive.versionName == info.versionName) { "安装包版本或包名不一致" }
        check(archive.minSdk == info.minSdk && info.minSdk <= sdk) { "安装包系统要求不一致" }
        check(archive.signers.isNotEmpty() && archive.signers == installedSigners && archive.signers == setOf(info.certificateSha256)) { "安装包签名与当前应用不一致" }
    }
    fun validateMetadata(info: AppUpdateInfo, packageName: String, staging: Boolean) {
        require(info.packageName == packageName && info.channel == "official") { "更新包与当前应用不匹配" }
        require(info.versionCode > 0 && info.sizeBytes > 0 && info.minSdk <= Build.VERSION.SDK_INT) { "此版本不支持当前系统" }
        val expectedHost = if (staging) "downloads-staging.myleafy.space" else "downloads.myleafy.space"
        val uri = Uri.parse(info.apkUrl)
        require(uri.scheme == "https" && uri.host == expectedHost && uri.userInfo == null && uri.port == -1) { "更新下载地址无效" }
        require(info.sha256.matches(Regex("[a-f0-9]{64}")) && info.certificateSha256.matches(Regex("[a-f0-9]{64}"))) { "更新校验信息无效" }
        require(info.apkName.matches(Regex("MyLeafy-Android-\\d+\\.\\d+\\.\\d+\\.apk"))) { "更新文件名无效" }
    }
}
data class UpdatePackageIdentity(val packageName: String, val versionCode: Long, val versionName: String?, val minSdk: Int?, val signers: Set<String>)

/** Anonymous requests only: no school cookie, backend session or profile is created. */
class AppUpdateRepository(private val context: Context) {
    val json = Json { ignoreUnknownKeys = true }
    private val origin = BuildConfig.MYLEAFY_API_ORIGIN.trimEnd('/')
    private val client = OkHttpClient.Builder().connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS).callTimeout(30, TimeUnit.SECONDS).build()
    private suspend inline fun <reified T> get(path: String): T = withContext(Dispatchers.IO) {
        client.newCall(Request.Builder().url(origin + path).build()).execute().use { response ->
            check(response.isSuccessful) { if (response.code == 410) "该版本已撤回，请重新检查更新" else "检查更新失败（HTTP ${response.code}）" }
            json.decodeFromString<T>(response.body?.string() ?: error("版本信息为空"))
        }
    }
    suspend fun check(): AppUpdateInfo? = get<LatestRelease>("/v1/releases/android/latest?package=${context.packageName}").release?.also(::validate)
    private fun validate(info: AppUpdateInfo) = UpdateIntegrity.validateMetadata(info, context.packageName, origin.contains("api-staging."))
    suspend fun confirmPublished(info: AppUpdateInfo) {
        val current = get<AppUpdateInfo>("/v1/releases/android/${info.id}")
        validate(current)
        check(current == info) { "版本信息已变化，请重新检查更新" }
    }
    fun target(info: AppUpdateInfo) = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "updates/${info.apkName}")
    suspend fun verify(info: AppUpdateInfo): File = withContext(Dispatchers.IO) {
        validate(info)
        val file = target(info)
        check(file.isFile && file.length() == info.sizeBytes) { "安装包大小不一致，请重新下载" }
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream -> val buffer = ByteArray(65536); while (true) { val count = stream.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) } }
        val hash = digest.digest().joinToString("") { "%02x".format(it) }
        check(hash == info.sha256) { "安装包校验失败，请重新下载" }
        val flags = PackageManager.GET_SIGNING_CERTIFICATES
        val archive = context.packageManager.getPackageArchiveInfo(file.absolutePath, flags) ?: error("安装包无法读取")
        val installed = context.packageManager.getPackageInfo(context.packageName, flags)
        val signers = archive.signingInfo?.apkContentsSigners?.map { UpdateIntegrity.sha256(it.toByteArray()) }?.toSet().orEmpty()
        val current = installed.signingInfo?.apkContentsSigners?.map { UpdateIntegrity.sha256(it.toByteArray()) }?.toSet().orEmpty()
        UpdateIntegrity.validatePackage(info, UpdatePackageIdentity(archive.packageName, archive.longVersionCode, archive.versionName, archive.applicationInfo?.minSdkVersion, signers), current, Build.VERSION.SDK_INT)
        file
    }
}

sealed interface UpdateUiState {
    data object Idle : UpdateUiState
    data object Checking : UpdateUiState
    data class UpToDate(val currentVersion: String) : UpdateUiState
    data object Unpublished : UpdateUiState
    data class Available(val info: AppUpdateInfo) : UpdateUiState
    data class Downloading(val info: AppUpdateInfo, val progress: Float, val message: String = "正在下载") : UpdateUiState
    data class Downloaded(val info: AppUpdateInfo, val file: File) : UpdateUiState
    data class Error(val message: String) : UpdateUiState
}

/** Application-owned downloads survive screen changes; DownloadManager survives process death. */
class AppUpdateManager(private val context: Context, private val owner: CoroutineScope) {
    private val repository = AppUpdateRepository(context)
    private val prefs = context.getSharedPreferences("app_updates", Context.MODE_PRIVATE)
    private val downloads = context.getSystemService(DownloadManager::class.java)
    private val state = MutableStateFlow<UpdateUiState>(UpdateUiState.Idle)
    val uiState = state.asStateFlow()
    private val offer = MutableStateFlow<AppUpdateInfo?>(null)
    val prompt = offer.asStateFlow()
    private var checkJob: Job? = null
    private var downloadJob: Job? = null
    val requestingInstall = MutableStateFlow(false)
    private val installedCode get() = context.packageManager.getPackageInfo(context.packageName, 0).longVersionCode

    init { owner.launch { restoreDownload() } }

    fun check(manual: Boolean = true) {
        if (checkJob?.isActive == true || state.value is UpdateUiState.Downloading || (!manual && state.value is UpdateUiState.Downloaded)) return
        val now = System.currentTimeMillis()
        if (!manual && now - prefs.getLong("last_check", 0) in 0 until DAY) return
        prefs.edit().putLong("last_check", now).apply()
        if (manual) { state.value = UpdateUiState.Checking; offer.value = null }
        checkJob = owner.launch {
            try {
                val info = repository.check()
                if (manual) state.value = when { info == null -> UpdateUiState.Unpublished; info.versionCode <= installedCode -> UpdateUiState.UpToDate(BuildConfig.VERSION_NAME); else -> UpdateUiState.Available(info) }
                else if (info != null && info.versionCode > installedCode &&
                    !(prefs.getInt("snooze_code", 0) == info.versionCode && now < prefs.getLong("snooze_until", 0))) offer.value = info
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) { if (manual) state.value = UpdateUiState.Error(error.message ?: "检查更新失败") }
        }
    }
    fun later(info: AppUpdateInfo) {
        prefs.edit().putInt("snooze_code", info.versionCode).putLong("snooze_until", System.currentTimeMillis() + DAY).apply()
        offer.value = null
    }
    fun download(info: AppUpdateInfo) {
        if (downloadJob?.isActive == true) return
        offer.value = null
        state.value = UpdateUiState.Downloading(info, 0f)
        downloadJob = owner.launch {
            try {
                repository.confirmPublished(info)
                val previous = prefs.getLong("download_id", -1)
                val stored = prefs.getString("release", null)?.let { repository.json.decodeFromString<AppUpdateInfo>(it) }
                if (previous >= 0 && stored == info) { watch(previous, info, true); return@launch }
                if (previous >= 0) downloads.remove(previous)
                val file = repository.target(info)
                file.parentFile?.mkdirs()
                if (file.exists()) check(file.delete()) { "无法替换旧安装包" }
                val request = DownloadManager.Request(Uri.parse(info.apkUrl))
                    .setTitle("MyLeafy ${info.versionName}")
                    .setMimeType("application/vnd.android.package-archive")
                    .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
                    .setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, "updates/${info.apkName}")
                val id = downloads.enqueue(request)
                prefs.edit().putLong("download_id", id).putString("release", repository.json.encodeToString(info)).commit()
                watch(id, info, true)
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) { state.value = UpdateUiState.Error(error.message ?: "下载失败") }
        }
    }
    private suspend fun restoreDownload() {
        val encoded = prefs.getString("release", null) ?: return
        try {
            val info = repository.json.decodeFromString<AppUpdateInfo>(encoded)
            if (installedCode >= info.versionCode) { clearDownload(); return }
            val id = prefs.getLong("download_id", -1)
            if (id < 0) return
            downloadJob = owner.launch {
                try { watch(id, info) }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (error: Exception) { state.value = UpdateUiState.Error(error.message ?: "无法恢复下载") }
            }
        } catch (error: Exception) { state.value = UpdateUiState.Error(error.message ?: "无法恢复下载") }
    }
    private suspend fun watch(id: Long, info: AppUpdateInfo, autoInstall: Boolean = false) {
        while (true) {
            currentCoroutineContext().ensureActive()
            val progress = withContext(Dispatchers.IO) {
                downloads.query(DownloadManager.Query().setFilterById(id)).use { cursor ->
                    check(cursor.moveToFirst()) { "下载任务已移除，请重新下载" }
                    val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                    val bytes = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                    val reason = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
                    Triple(status, bytes, reason)
                }
            }
            if (progress.first == DownloadManager.STATUS_SUCCESSFUL) {
                try { state.value = UpdateUiState.Downloaded(info, repository.verify(info)); if (autoInstall) requestingInstall.value = true }
                catch (error: Exception) { clearDownload(); throw error }
                return
            }
            if (progress.first == DownloadManager.STATUS_FAILED) {
                clearDownload()
                error(if (progress.third == DownloadManager.ERROR_INSUFFICIENT_SPACE) "存储空间不足，请腾出空间后重试" else "下载失败（${progress.third}），请重试")
            }
            val message = if (progress.first == DownloadManager.STATUS_PAUSED) when (progress.third) {
                DownloadManager.PAUSED_WAITING_FOR_NETWORK -> "等待网络连接"
                DownloadManager.PAUSED_QUEUED_FOR_WIFI -> "等待 Wi-Fi 连接"
                else -> "连接中断，等待重试"
            } else "正在下载"
            state.value = UpdateUiState.Downloading(info, (progress.second.toFloat() / info.sizeBytes).coerceIn(0f, 1f), message)
            delay(500)
        }
    }
    private fun clearDownload() {
        val id = prefs.getLong("download_id", -1)
        if (id >= 0) downloads.remove(id)
        prefs.edit().remove("download_id").remove("release").apply()
    }
    suspend fun installationFile(): File {
        val ready = state.value as? UpdateUiState.Downloaded ?: error("安装包尚未就绪")
        repository.confirmPublished(ready.info)
        return repository.verify(ready.info)
    }
    fun requestInstall() { requestingInstall.value = true }
    fun installationOpened() { requestingInstall.value = false }
    companion object { private const val DAY = 24 * 60 * 60 * 1000L }
}

class CheckUpdatesViewModel(val manager: AppUpdateManager) : ViewModel() {
    val uiState = manager.uiState
    init { if (manager.uiState.value is UpdateUiState.Idle) manager.check() }
    fun check() = manager.check()
    fun download(info: AppUpdateInfo) = manager.download(info)
}
