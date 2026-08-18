package com.myleafy.android.features.campus

import com.myleafy.android.core.data.local.ExamDao
import com.myleafy.android.core.data.local.ExamEntity
import com.myleafy.android.core.data.local.GradeDao
import com.myleafy.android.core.data.local.GradeEntity
import kotlinx.coroutines.flow.Flow

/**
 * 校园学业仓储（成绩/考试）。学校教务为权威来源，Room 为本地缓存副本；
 * 阶段 2 接入教务抓取后写入 Room。
 */
interface AcademicRepository {
    fun gradesForTerm(term: String): Flow<List<GradeEntity>>
    fun terms(): Flow<List<String>>
    fun exams(): Flow<List<ExamEntity>>
}

class RoomAcademicRepository(
    private val gradeDao: GradeDao,
    private val examDao: ExamDao,
) : AcademicRepository {

    override fun gradesForTerm(term: String): Flow<List<GradeEntity>> = gradeDao.gradesForTerm(term)

    override fun terms(): Flow<List<String>> = gradeDao.availableTerms()

    override fun exams(): Flow<List<ExamEntity>> = examDao.all()
}
