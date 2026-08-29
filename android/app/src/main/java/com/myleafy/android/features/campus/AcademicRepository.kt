package com.myleafy.android.features.campus

import com.myleafy.android.core.data.local.ExamDao
import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.GradeDao
import com.myleafy.android.core.data.local.GradeEntity
import com.myleafy.android.core.data.local.GradeRankingDao
import com.myleafy.android.core.data.local.GradeRankingEntity
import com.myleafy.android.core.data.local.GradeSummaryDao
import com.myleafy.android.core.data.local.GradeSummaryEntity
import com.myleafy.android.core.network.SchoolNetworkClient
import java.util.UUID
import kotlinx.coroutines.flow.Flow

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
}

data class AcademicRefreshResult(
    val grades: Int?,
    val rankings: Int?,
    val exams: Int?,
    val failures: List<String>,
) {
    val hasAnySuccess: Boolean get() = grades != null || rankings != null || exams != null
}

/** 线上仓储：教务抓取（OkHttp + jsoup）→ 解析 → Room 落库。 */
class LiveAcademicRepository(
    private val client: SchoolNetworkClient,
    private val gradeDao: GradeDao,
    private val gradeRankingDao: GradeRankingDao,
    private val gradeSummaryDao: GradeSummaryDao,
    private val examDao: ExamDao,
) : AcademicRepository {

    override fun grades(): Flow<List<GradeEntity>> = gradeDao.all()

    override fun gradesForTerm(term: String): Flow<List<GradeEntity>> = gradeDao.gradesForTerm(term)

    override fun terms(): Flow<List<String>> = gradeDao.availableTerms()

    override fun rankings(): Flow<List<GradeRankingEntity>> = gradeRankingDao.all()

    override fun gradeSummary(): Flow<GradeSummaryEntity?> = gradeSummaryDao.official()

    override fun exams(): Flow<List<ExamEntity>> = examDao.all()

    override suspend fun refresh(semesterId: String): AcademicRefreshResult {
        val failures = mutableListOf<String>()
        var gradeCount: Int? = null
        var rankingCount: Int? = null
        var examCount: Int? = null

        runCatching { client.fetchAcademicResults() }
            .onSuccess { result ->
                gradeDao.clearAll()
                gradeDao.upsertAll(
                    result.grades.map { g ->
                GradeEntity(
                    id = "${g.term}|${g.courseName}|${g.credit}|${g.type}",
                    term = g.term,
                    courseName = g.courseName,
                    credit = g.credit,
                    score = g.score,
                    type = g.type,
                )
            },
                )
                gradeCount = result.grades.size

                result.rankings?.let { rankings ->
                    gradeRankingDao.clearAll()
                    gradeRankingDao.upsertAll(
                        rankings.map { ranking ->
                            GradeRankingEntity(
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
                            officialGpa = summary.officialGpa,
                            officialWeightedAverage = summary.officialWeightedAverage,
                            officialCreditPoint = summary.officialCreditPoint,
                        ),
                    )
                }
            }
            .onFailure { failures += "成绩与排名：${it.message ?: "拉取失败"}" }

        runCatching { client.fetchExams(semesterId) }
            .onSuccess { exams ->
                examDao.clearAll()
                examDao.upsertAll(
                    exams.map { e ->
                        ExamEntity(
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
            .onFailure { failures += "考试安排：${it.message ?: "拉取失败"}" }

        return AcademicRefreshResult(gradeCount, rankingCount, examCount, failures)
    }
}
