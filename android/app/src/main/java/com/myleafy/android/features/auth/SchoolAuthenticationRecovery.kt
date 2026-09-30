package com.myleafy.android.features.auth

import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.network.*
import com.myleafy.android.core.security.SchoolLoginCredentialStore
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

sealed interface SchoolRecoveryResult {
    data object Authenticated : SchoolRecoveryResult
    data class Manual(val challenge: SchoolCaptchaChallenge?, val message: String) : SchoolRecoveryResult
}

class SchoolAuthenticationRecovery(
    private val client: SchoolNetworkClient,
    private val credentials: SchoolLoginCredentialStore,
    private val scopes: ActiveAppScopeStore,
    private val owner: CoroutineScope,
    private val recognizer: CaptchaRecognizer,
) {
    private val mutex = Mutex()
    private var flight: Deferred<SchoolRecoveryResult>? = null
    private var flightScope: String? = null
    @Volatile var revision = 0L
        private set
    private val mutableProgress = MutableStateFlow<String?>(null)
    val progress = mutableProgress.asStateFlow()
    private var manual: SchoolRecoveryResult.Manual? = null
    private var flightRevision = -1L

    suspend fun manualAuthenticationCompleted() = mutex.withLock {
        revision++
        flight = null
        manual = null
    }

    init {
        owner.launch {
            scopes.scope.collect { scope -> mutex.withLock {
                if (flightScope != null && flightScope != scope.scopeKey) {
                    flight?.cancel(); flight = null; manual = null; mutableProgress.value = null; flightScope = null
                }
            } }
        }
    }

    suspend fun manualChallenge(): SchoolCaptchaChallenge {
        val cached = mutex.withLock {
            manual?.challenge?.takeIf { !it.consumed.get() && flightScope == scopes.current.scopeKey }.also { manual = null }
        }
        return cached ?: client.prepareUndergraduateChallenge()
    }

    suspend fun recover(expectedRevision: Long): SchoolRecoveryResult {
        val key = scopes.current.scopeKey
        val task = mutex.withLock {
            if (revision != expectedRevision) return SchoolRecoveryResult.Authenticated
            flight?.takeIf { !it.isCancelled && flightScope == key && flightRevision == expectedRevision } ?: owner.async {
                try {
                    recoverOnce(key).also { result -> mutex.withLock {
                        if (scopes.current.scopeKey != key) throw CancellationException("Identity changed")
                        if (result == SchoolRecoveryResult.Authenticated) revision++ else manual = result as SchoolRecoveryResult.Manual
                    } }
                } finally { if (scopes.current.scopeKey == key) mutableProgress.value = null }
            }.also { flight = it; flightScope = key; flightRevision = expectedRevision }
        }
        return task.await()
    }

    private suspend fun recoverOnce(scopeKey: String): SchoolRecoveryResult {
        val scope = scopes.current
        if (scope.isGuest || scope.campusId?.rawValue != "bjfu" || scope.eduId.isNullOrBlank()) throw SchoolNetworkError.SessionExpired
        val credential = withContext(Dispatchers.IO) { credentials.load("bjfu", "undergraduate", scope.eduId) }
            ?: return SchoolRecoveryResult.Manual(null, "请重新登录教务系统。")
        for (attempt in 1..3) {
            currentCoroutineContext().ensureActive()
            if (scopeKey != scopes.current.scopeKey) throw CancellationException("Identity changed")
            if (attempt > 1) delay(300)
            mutableProgress.value = "正在连接教务系统"
            val challenge = client.prepareUndergraduateChallenge()
            mutableProgress.value = "正在识别验证码（$attempt/3）"
            val captcha = try { recognizer.recognize(challenge.imageBytes) }
                catch (cancelled: CancellationException) { throw cancelled }
                catch (error: Exception) { android.util.Log.w("SchoolRecovery", "Captcha recognition failed: ${error.javaClass.simpleName}"); null }
            if (captcha == null) {
                if (attempt == 3) return SchoolRecoveryResult.Manual(challenge, "自动识别未通过，请手动输入验证码。")
                continue
            }
            mutableProgress.value = "正在验证登录"
            try {
                client.loginUndergraduate(challenge, credential.account, credential.password, captcha)
                return SchoolRecoveryResult.Authenticated
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: SchoolNetworkError.LoginFailed) {
                val message = error.message.orEmpty()
                val captchaRejected = listOf("验证码", "随机码", "校验码", "captcha", "verification code").any { message.contains(it, true) }
                if (!captchaRejected || attempt == 3) return SchoolRecoveryResult.Manual(null, message.ifBlank { "请重新登录教务系统。" })
            }
        }
        error("Unreachable")
    }
}

/** Every retry preserves the caller's exact query and only retries explicit session expiry. */
class RecoveringSchoolNetworkClient(
    private val delegate: SchoolNetworkClient,
    private val recovery: SchoolAuthenticationRecovery,
    private val scopes: ActiveAppScopeStore,
) : SchoolNetworkClient by delegate {
    private suspend fun <T> request(block: suspend () -> T): T {
        val scope = scopes.current.scopeKey
        val revision = recovery.revision
        try { return block() } catch (error: SchoolNetworkError.AuthenticationExpired) {
            if (scope != scopes.current.scopeKey) throw CancellationException("Identity changed")
            val result = recovery.recover(revision)
            if (result is SchoolRecoveryResult.Manual) throw SchoolNetworkError.AuthenticationRequired(result.message)
            if (scope != scopes.current.scopeKey) throw CancellationException("Identity changed")
            return block()
        }
    }
    override suspend fun fetchTimetable(semesterId: String) = request { delegate.fetchTimetable(semesterId) }
    override suspend fun fetchTimetable(semesterId: String, onStage: (AcademicStage) -> Unit) = request { delegate.fetchTimetable(semesterId, onStage) }
    override suspend fun fetchGrades() = request { delegate.fetchGrades() }
    override suspend fun fetchGradeRankings() = request { delegate.fetchGradeRankings() }
    override suspend fun fetchAcademicResults() = request { delegate.fetchAcademicResults() }
    override suspend fun fetchExams(semesterId: String) = request { delegate.fetchExams(semesterId) }
    override suspend fun fetchEmptyClassrooms(semesterId: String, week: Int, day: Int, startPeriod: Int, endPeriod: Int) =
        request { delegate.fetchEmptyClassrooms(semesterId, week, day, startPeriod, endPeriod) }
    override suspend fun fetchTeachingPlan() = request { delegate.fetchTeachingPlan() }
    override suspend fun fetchTrainingProgram() = request { delegate.fetchTrainingProgram() }
}
