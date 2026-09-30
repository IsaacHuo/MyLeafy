package com.myleafy.android.features.campus

import com.myleafy.android.core.data.local.ExamDao
import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.GradeDao
import com.myleafy.android.core.data.local.GradeEntity
import com.myleafy.android.core.data.local.GradeRankingDao
import com.myleafy.android.core.data.local.GradeRankingEntity
import com.myleafy.android.core.data.local.GradeSummaryDao
import com.myleafy.android.core.data.local.GradeSummaryEntity
import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.network.SchoolNetworkClient
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.ExperimentalCoroutinesApi

/**
 * 校园学业仓储（成绩/考试）。学校教务为权威来源，Room 为本地缓存副本。
 */
interface AcademicRepository {
    fun grades(): Flow<List<GradeEntity>>
    fun gradesForTerm(term: String): Flow<List<GradeEntity>>
    fun terms(): Flow<List<String>>
    fun rankings(): Flow<List<GradeRankingEntity>>
    fun gradeSummary(): Flow<GradeSummaryEntity?>
    fun exams(): Flow<List<ExamEntity>>

    /** 从教务抓取成绩、官方排名/汇总与考试；各范围独立保留最近成功缓存。 */
    suspend fun refresh(semesterId: String): AcademicRefreshResult
    suspend fun refreshGradesAndRankings(): AcademicRefreshResult
    suspend fun refreshExams(semesterId: String): AcademicRefreshResult
    suspend fun refreshRankings(): AcademicRefreshResult
}

data class AcademicRefreshResult(
    val grades: Int?,
    val rankings: Int?,
    val exams: Int?,
    val failures: List<String>,
    val needsAuthentication: Boolean = false,
) {
    val hasAnySuccess: Boolean get() = grades != null || rankings != null || exams != null
}

/** 线上仓储：教务抓取（OkHttp + jsoup）→ 解析 → Room 落库。 */
@OptIn(ExperimentalCoroutinesApi::class)
class LiveAcademicRepository(
    private val client: SchoolNetworkClient,
    private val gradeDao: GradeDao,
    private val gradeRankingDao: GradeRankingDao,
    private val gradeSummaryDao: GradeSummaryDao,
    private val examDao: ExamDao,
    private val activeAppScopeStore: ActiveAppScopeStore,
) : AcademicRepository {

    override fun grades(): Flow<List<GradeEntity>> =
        activeAppScopeStore.scope.flatMapLatest { gradeDao.all(it.scopeKey) }

    override fun gradesForTerm(term: String): Flow<List<GradeEntity>> =
        activeAppScopeStore.scope.flatMapLatest { gradeDao.gradesForTerm(it.scopeKey, term) }

    override fun terms(): Flow<List<String>> =
        activeAppScopeStore.scope.flatMapLatest { gradeDao.availableTerms(it.scopeKey) }

    override fun rankings(): Flow<List<GradeRankingEntity>> =
        activeAppScopeStore.scope.flatMapLatest { gradeRankingDao.all(it.scopeKey) }

    override fun gradeSummary(): Flow<GradeSummaryEntity?> =
        activeAppScopeStore.scope.flatMapLatest { gradeSummaryDao.official(it.scopeKey) }

    override fun exams(): Flow<List<ExamEntity>> =
        activeAppScopeStore.scope.flatMapLatest { examDao.all(it.scopeKey) }

    override suspend fun refresh(semesterId: String): AcademicRefreshResult {
        val grades = refreshGradesAndRankings()
        val exams = refreshExams(semesterId)
        return AcademicRefreshResult(
            grades = grades.grades,
            rankings = grades.rankings,
            exams = exams.exams,
            failures = grades.failures + exams.failures,
            needsAuthentication = grades.needsAuthentication || exams.needsAuthentication,
        )
    }

    override suspend fun refreshGradesAndRankings(): AcademicRefreshResult {
        val scopeKey = activeAppScopeStore.current.scopeKey
        val failures = mutableListOf<String>()
        var needsAuthentication = false
        var gradeCount: Int? = null
        var rankingCount: Int? = null

        runCatching { client.fetchAcademicResults() }
            .onSuccess { result ->
                ensureScope(scopeKey)
                gradeDao.replaceAll(scopeKey,
                    result.grades.map { g ->
                GradeEntity(
                    scopeKey = scopeKey,
                    id = "${g.term}|${g.courseCode}|${g.courseName}|${g.credit}|${g.examNature}|${g.score}",
                    term = g.term,
                    courseName = g.courseName,
                    credit = g.credit,
                    score = g.score,
                    type = g.type,
                    courseCode = g.courseCode,
                    courseAttribute = g.courseAttribute,
                    courseCategory = g.courseCategory,
                    examNature = g.examNature,
                )
            },
                )
                gradeCount = result.grades.size

                result.rankings?.let { rankings ->
                    gradeRankingDao.replaceAll(scopeKey,
                        rankings.map { ranking ->
                            GradeRankingEntity(
                                scopeKey = scopeKey,
                                id = "${ranking.term}|${ranking.rankingRange}|${ranking.rank}|${ranking.metricText}",
                                term = ranking.term,
                                rankingRange = ranking.rankingRange,
                                rank = ranking.rank,
                                totalCount = ranking.totalCount,
                                metricText = ranking.metricText,
                            )
                        },
                    )
                    rankingCount = rankings.size
                }
                result.summary?.let { summary ->
                    gradeSummaryDao.upsert(
                        GradeSummaryEntity(
                            scopeKey = scopeKey,
                            officialGpa = summary.officialGpa,
                            officialWeightedAverage = summary.officialWeightedAverage,
                            officialCreditPoint = summary.officialCreditPoint,
                        ),
                    )
                }
            }
            .onFailure { if (it is kotlinx.coroutines.CancellationException) throw it; needsAuthentication = it is com.myleafy.android.core.network.SchoolNetworkError.AuthenticationExpired; failures += "成绩与排名：${it.message ?: "拉取失败"}" }

        return AcademicRefreshResult(
            grades = gradeCount,
            rankings = rankingCount,
            exams = null,
            failures = failures,
            needsAuthentication = needsAuthentication,
        )
    }

    override suspend fun refreshExams(semesterId: String): AcademicRefreshResult {
        val scopeKey = activeAppScopeStore.current.scopeKey
        val failures = mutableListOf<String>()
        var needsAuthentication = false
        var examCount: Int? = null

        runCatching { client.fetchExams(semesterId) }
            .onSuccess { exams ->
                ensureScope(scopeKey)
                examDao.replaceAll(scopeKey,
                    exams.map { e ->
                        ExamEntity(
                            scopeKey = scopeKey,
                            id = e.id,
                            courseId = e.courseId,
                            name = e.name,
                            date = e.date,
                            start = e.start,
                            end = e.end,
                            location = e.location,
                        )
                    },
                )
                examCount = exams.size
            }
            .onFailure { if (it is kotlinx.coroutines.CancellationException) throw it; needsAuthentication = it is com.myleafy.android.core.network.SchoolNetworkError.AuthenticationExpired; failures += "考试安排：${it.message ?: "拉取失败"}" }

        return AcademicRefreshResult(
            grades = null,
            rankings = null,
            exams = examCount,
            failures = failures,
            needsAuthentication = needsAuthentication,
        )
    }
    override suspend fun refreshRankings(): AcademicRefreshResult {
        val scopeKey = activeAppScopeStore.current.scopeKey
        return try {
            val rankings = client.fetchGradeRankings()
            ensureScope(scopeKey)
            gradeRankingDao.replaceAll(scopeKey, rankings.map { ranking ->
                GradeRankingEntity(scopeKey, "${ranking.term}|${ranking.rankingRange}|${ranking.rank}|${ranking.metricText}",
                    ranking.term, ranking.rankingRange, ranking.rank, ranking.totalCount, ranking.metricText)
            })
            AcademicRefreshResult(null, rankings.size, null, emptyList())
        } catch (error: Exception) {
            if (error is kotlinx.coroutines.CancellationException) throw error
            AcademicRefreshResult(null, null, null, listOf(error.message ?: "排名刷新失败"))
        }
    }

    private suspend fun ensureScope(scopeKey: String) {
        kotlinx.coroutines.currentCoroutineContext().ensureActive()
        if (activeAppScopeStore.current.scopeKey != scopeKey) throw kotlinx.coroutines.CancellationException("Identity changed")
    }

}
