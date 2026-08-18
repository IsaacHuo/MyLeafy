package com.myleafy.android.core.di

import android.content.Context
import androidx.room.Room
import com.myleafy.android.core.data.local.AppDatabase
import com.myleafy.android.core.data.local.CourseDao
import com.myleafy.android.core.prefs.SettingsStore
import com.myleafy.android.core.security.KeystoreSchoolLoginCredentialStore
import com.myleafy.android.core.security.KeystoreSchoolSessionCookieStore
import com.myleafy.android.core.security.SchoolLoginCredentialStore
import com.myleafy.android.core.security.SchoolSessionCookieStore
import com.myleafy.android.core.security.SecureStorage
import com.myleafy.android.features.auth.AuthRepository
import com.myleafy.android.features.auth.PlaceholderAuthRepository
import com.myleafy.android.features.campus.AcademicRepository
import com.myleafy.android.features.campus.RoomAcademicRepository
import com.myleafy.android.features.community.CommunityRepository
import com.myleafy.android.features.community.PlaceholderCommunityRepository
import com.myleafy.android.features.profile.PlaceholderProfileRepository
import com.myleafy.android.features.profile.ProfileRepository
import com.myleafy.android.features.schedule.RoomScheduleRepository
import com.myleafy.android.features.schedule.ScheduleRepository
import com.myleafy.android.features.timetable.RoomTimetableRepository
import com.myleafy.android.features.timetable.TimetableRepository

/**
 * 手动组合根（对应 iOS `LeafyDependencies`）。
 *
 * 阶段 1.5：完整组装各功能仓储。不引入 Hilt/Koin（单 app module 足够），
 * 后续如出现多模块/多入口再评估 DI 框架。
 */
class AppContainer(context: Context) {

    private val database: AppDatabase = Room.databaseBuilder(
        context.applicationContext,
        AppDatabase::class.java,
        "myleafy.db",
    )
        // 本地数据库早期阶段无正式数据，schema 变更允许直接重建。
        // 正式发布前应移除并迁移为受控 migration。
        .fallbackToDestructiveMigration(dropAllTables = true)
        .build()

    val courseDao: CourseDao get() = database.courseDao()

    val settingsStore: SettingsStore = SettingsStore(context)

    val secureStorage: SecureStorage = SecureStorage(context)
    val schoolLoginCredentialStore: SchoolLoginCredentialStore =
        KeystoreSchoolLoginCredentialStore(secureStorage)
    val schoolSessionCookieStore: SchoolSessionCookieStore =
        KeystoreSchoolSessionCookieStore(secureStorage)

    val timetableRepository: TimetableRepository = RoomTimetableRepository(database.courseDao())
    val scheduleRepository: ScheduleRepository =
        RoomScheduleRepository(database.scheduleMemoDao(), database.scheduleEventDao())
    val academicRepository: AcademicRepository =
        RoomAcademicRepository(database.gradeDao(), database.examDao())
    val communityRepository: CommunityRepository = PlaceholderCommunityRepository()
    val profileRepository: ProfileRepository = PlaceholderProfileRepository()
    val authRepository: AuthRepository = PlaceholderAuthRepository()
}
