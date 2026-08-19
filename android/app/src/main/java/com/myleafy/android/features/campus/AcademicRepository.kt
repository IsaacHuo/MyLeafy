package com.myleafy.android.features.campus

import com.myleafy.android.core.data.local.ExamDao
import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.GradeDao
import com.myleafy.android.core.data.local.GradeEntity
import com.myleafy.android.core.network.SchoolNetworkClient
import java.util.UUID
import kotlinx.coroutines.flow.Flow

/**
 * 校园学业仓储（成绩/考试）。学校教务为权威来源，Room 为本地缓存副本。
 */
interface AcademicRepository {
    fun gradesForTerm(term: String): Flow<List<GradeEntity>>
    fun terms(): Flow<List<String>>
    fun exams(): Flow<List<ExamEntity>>

    /** 从教务抓取当前学期成绩与考试并写入 Room。失败时抛出 [Exception]。 */
    suspend fun refresh(semesterId: String)
}

/** 线上仓储：教务抓取（OkHttp + jsoup）→ 解析 → Room 落库。 */
class LiveAcademicRepository(
    private val client: SchoolNetworkClient,
    private val gradeDao: GradeDao,
    private val examDao: ExamDao,
) : AcademicRepository {

    override fun gradesForTerm(term: String): Flow<List<GradeEntity>> = gradeDao.gradesForTerm(term)

    override fun terms(): Flow<List<String>> = gradeDao.availableTerms()

    override fun exams(): Flow<List<ExamEntity>> = examDao.all()

    override suspend fun refresh(semesterId: String) {
        val grades = client.fetchGrades()
        val exams = client.fetchExams(semesterId)

        gradeDao.clearAll()
        gradeDao.upsertAll(
            grades.map { g ->
                GradeEntity(
                    id = UUID.randomUUID().toString(),
                    term = g.term,
                    courseName = g.courseName,
                    credit = g.credit,
                    score = g.score,
                    type = g.type,
                )
            },
        )
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
    }
}
