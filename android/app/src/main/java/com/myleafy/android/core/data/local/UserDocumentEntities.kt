package com.myleafy.android.core.data.local

import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

/**
 * 「我的」/「校园」下本地用户文档：荣誉记录与综素测算。
 * 均为本机权威数据，按校园身份 scopeKey 隔离。
 */
@Entity(tableName = "honor_records", primaryKeys = ["scopeKey", "id"])
data class HonorRecordEntity(
    val scopeKey: String,
    val id: String,
    val title: String,
    val note: String,
    val awardedAt: Long?,
    val originalFilename: String,
    val localFilename: String,
    val contentType: String,
    val importedAt: Long,
    val updatedAt: Long,
)

@Entity(tableName = "comprehensive_quality_records", primaryKeys = ["scopeKey", "id"])
data class ComprehensiveQualityRecordEntity(
    val scopeKey: String,
    val id: String,
    val collegeName: String,
    val cohort: String,
    val academicStandardScore: Double?,
    val officialQualityScore: Double?,
    val officialCompositeScore: Double?,
    val note: String,
    val componentsJson: String,
    val updatedAt: Long,
)

/**
 * 教务文档缓存（教学计划 / 培养方案）。学校为权威来源，payload 为解析结果的 JSON 副本，
 * 解析失败时保留最近成功缓存。
 */
@Entity(tableName = "academic_documents", primaryKeys = ["scopeKey", "kind"])
data class AcademicDocumentEntity(
    val scopeKey: String,
    val kind: String,
    val payload: String,
    val updatedAt: Long,
)

@Dao
interface HonorRecordDao {
    @Query("SELECT * FROM honor_records WHERE scopeKey = :scopeKey ORDER BY importedAt DESC")
    fun all(scopeKey: String): Flow<List<HonorRecordEntity>>

    @Query("SELECT * FROM honor_records WHERE scopeKey = :scopeKey AND id = :id LIMIT 1")
    suspend fun byId(scopeKey: String, id: String): HonorRecordEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(record: HonorRecordEntity)

    @Query("DELETE FROM honor_records WHERE scopeKey = :scopeKey AND id = :id")
    suspend fun delete(scopeKey: String, id: String)
}

@Dao
interface ComprehensiveQualityDao {
    @Query("SELECT * FROM comprehensive_quality_records WHERE scopeKey = :scopeKey AND id = 'current' LIMIT 1")
    fun current(scopeKey: String): Flow<ComprehensiveQualityRecordEntity?>

    @Query("SELECT * FROM comprehensive_quality_records WHERE scopeKey = :scopeKey AND id = 'current' LIMIT 1")
    suspend fun currentOnce(scopeKey: String): ComprehensiveQualityRecordEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(record: ComprehensiveQualityRecordEntity)

    @Query("DELETE FROM comprehensive_quality_records WHERE scopeKey = :scopeKey AND id = 'current'")
    suspend fun clear(scopeKey: String)
}

@Dao
interface AcademicDocumentDao {
    @Query("SELECT * FROM academic_documents WHERE scopeKey = :scopeKey AND kind = :kind LIMIT 1")
    fun document(scopeKey: String, kind: String): Flow<AcademicDocumentEntity?>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(document: AcademicDocumentEntity)
}
