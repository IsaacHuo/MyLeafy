package com.myleafy.android.core.di

import android.content.Context
import androidx.room.Room
import com.myleafy.android.core.data.local.AppDatabase
import com.myleafy.android.core.data.local.CourseDao
import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.campus.CampusCapabilities
import com.myleafy.android.core.network.SchoolNetworkClient
import com.myleafy.android.core.network.SchoolSessionState
import com.myleafy.android.core.network.CampusIdentity
import com.myleafy.android.core.network.SchoolPortal
import com.myleafy.android.core.campus.CampusID
import com.myleafy.android.core.network.okhttp.OkHttpSchoolNetworkClient
import com.myleafy.android.core.prefs.SettingsStore
import com.myleafy.android.parsers.HtmlParser
import com.myleafy.android.parsers.JsoupHtmlParser
import com.myleafy.android.core.security.KeystoreSchoolLoginCredentialStore
import com.myleafy.android.core.security.KeystoreSchoolSessionCookieStore
import com.myleafy.android.core.security.SchoolLoginCredentialStore
import com.myleafy.android.core.security.SchoolSessionCookieStore
import com.myleafy.android.core.security.SecureStorage
import com.myleafy.android.features.auth.AuthRepository
import com.myleafy.android.features.auth.SchoolAuthRepository
import com.myleafy.android.features.campus.AcademicRepository
import com.myleafy.android.features.campus.ClassroomRepository
import com.myleafy.android.features.campus.LiveAcademicRepository
import com.myleafy.android.features.campus.LiveClassroomRepository
import com.myleafy.android.features.community.CommunityRepository
import com.myleafy.android.features.community.LiveCommunityRepository
import com.myleafy.android.features.profile.LiveProfileRepository
import com.myleafy.android.features.profile.ProfileRepository
import com.myleafy.android.features.schedule.RoomScheduleRepository
import com.myleafy.android.features.schedule.ScheduleRepository
import com.myleafy.android.features.timetable.LiveTimetableRepository
import com.myleafy.android.features.timetable.TimetableRepository
import com.myleafy.android.services.supabase.CommunityService
import com.myleafy.android.services.supabase.SupabaseClientProvider

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
        // Android 尚未发布，仅已知的预发布 schema 1–3 可破坏性重建。
        // 未来版本缺少 migration 时必须直接失败，不能静默丢数据。
        .fallbackToDestructiveMigrationFrom(true, 1, 2, 3)
        .build()

    val courseDao: CourseDao get() = database.courseDao()

    val settingsStore: SettingsStore = SettingsStore(context)

    val secureStorage: SecureStorage = SecureStorage(context)
    val schoolLoginCredentialStore: SchoolLoginCredentialStore =
        KeystoreSchoolLoginCredentialStore(secureStorage)
    val schoolSessionCookieStore: SchoolSessionCookieStore =
        KeystoreSchoolSessionCookieStore(secureStorage)

    // 教务会话状态：身份驱动 Cookie 作用域（M2.2 登录成功后写入）
    val activeAppScopeStore = ActiveAppScopeStore()
    val schoolSessionState = SchoolSessionState(activeAppScopeStore)

    init {
        schoolLoginCredentialStore.loadMostRecent(CampusID.bjfu.rawValue)?.let { cached ->
            schoolSessionState.identity = CampusIdentity(
                campusId = CampusID.bjfu,
                eduId = cached.account,
                displayName = null,
                portal = SchoolPortal.UNDERGRADUATE,
                kind = CampusIdentity.IdentityKind.SCHOOL_PORTAL,
            )
        }
    }

    // 教务 HTML 解析器（jsoup，M2.3）
    val htmlParser: HtmlParser = JsoupHtmlParser()

    // 教务 OkHttp 客户端：登录（M2.2）+ 课表抓取（M2.3）
    val schoolNetworkClient: SchoolNetworkClient = OkHttpSchoolNetworkClient(
        cookieStore = schoolSessionCookieStore,
        sessionState = schoolSessionState,
        baseUrl = com.myleafy.android.core.campus.ActiveCampusContext.descriptor.undergraduateBaseUrl,
        graduateBaseUrl = com.myleafy.android.core.campus.ActiveCampusContext.descriptor.graduateBaseUrl,
        parser = htmlParser,
    )

    val timetableRepository: TimetableRepository =
        LiveTimetableRepository(schoolNetworkClient, database.courseDao(), activeAppScopeStore)
    val scheduleRepository: ScheduleRepository =
        RoomScheduleRepository(database.scheduleMemoDao(), database.scheduleEventDao(), activeAppScopeStore)
    val academicRepository: AcademicRepository =
        LiveAcademicRepository(
            schoolNetworkClient,
            database.gradeDao(),
            database.gradeRankingDao(),
            database.gradeSummaryDao(),
            database.examDao(),
            activeAppScopeStore,
        )
    val classroomRepository: ClassroomRepository = LiveClassroomRepository(schoolNetworkClient)

    // 社区客户端按 capability 延迟创建；guest/无权限身份不会初始化 Supabase。
    private var cachedCommunityService: CommunityService? = null

    private fun communityServiceForActiveScope(): CommunityService? {
        val scope = activeAppScopeStore.current
        if (scope.isGuest || !scope.supports(CampusCapabilities.COMMUNITY)) return null
        return cachedCommunityService
            ?: SupabaseClientProvider.create()?.let(::CommunityService)?.also { cachedCommunityService = it }
    }

    val communityRepository: CommunityRepository =
        LiveCommunityRepository(::communityServiceForActiveScope, schoolSessionState, activeAppScopeStore)

    val profileRepository: ProfileRepository =
        LiveProfileRepository(::communityServiceForActiveScope, schoolSessionState)
    val authRepository: AuthRepository = SchoolAuthRepository(
        client = schoolNetworkClient,
        sessionState = schoolSessionState,
        credentialStore = schoolLoginCredentialStore,
        settingsStore = settingsStore,
    )
}
