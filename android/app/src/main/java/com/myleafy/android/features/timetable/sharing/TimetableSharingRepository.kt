package com.myleafy.android.features.timetable.sharing

import com.myleafy.android.core.campus.ActiveAppScopeStore
import com.myleafy.android.core.campus.CampusCapabilities
import com.myleafy.android.features.community.CommunityRepository
import com.myleafy.android.features.timetable.TimetableRepository
import com.myleafy.android.features.timetable.domain.SemesterConfig
import com.myleafy.android.services.supabase.SharedTimetableCourseDto
import com.myleafy.android.services.supabase.SharedTimetableSnapshotDto
import com.myleafy.android.services.supabase.TimetableInviteDto
import com.myleafy.android.services.supabase.TimetableShareMemberDto
import com.myleafy.android.services.supabase.TimetableSharingService
import kotlinx.coroutines.flow.first

data class TimetableSharingSnapshot(
    val mine: SharedTimetableSnapshotDto?,
    val viewable: List<SharedTimetableSnapshotDto>,
    val members: List<TimetableShareMemberDto>,
    val invites: List<TimetableInviteDto>,
)

class TimetableSharingRepository(
    private val serviceProvider: () -> TimetableSharingService?,
    private val communityRepository: CommunityRepository,
    private val timetableRepository: TimetableRepository,
    private val scopeStore: ActiveAppScopeStore,
) {
    val isLocallyAvailable: Boolean
        get() = scopeStore.current.supports(CampusCapabilities.COMMUNITY) &&
            scopeStore.current.supports(CampusCapabilities.SHARED_TIMETABLE)

    suspend fun backendAvailable(): Boolean = serviceProvider()?.isBackendAvailable() == true

    suspend fun refresh(): TimetableSharingSnapshot {
        val context = requireContext()
        val service = requireService()
        return TimetableSharingSnapshot(
            mine = service.mySnapshot(context.campusId, context.profileId, SemesterConfig.currentSemesterId),
            viewable = service.viewableSnapshots(context.campusId, context.profileId, SemesterConfig.currentSemesterId),
            members = service.members(context.campusId, context.profileId),
            invites = service.invites(context.campusId, context.profileId),
        )
    }

    suspend fun publish(): SharedTimetableSnapshotDto {
        val context = requireContext()
        val courses = timetableRepository.coursesForSemester(SemesterConfig.currentSemesterId).first().map { course ->
            SharedTimetableCourseDto(
                id = course.id,
                course_name = course.courseName,
                teacher = course.teacher,
                room = course.room,
                location = course.location,
                day_of_week = course.dayOfWeek,
                weeks = course.weeks.sorted(),
                duration = course.duration.sorted(),
            )
        }
        require(courses.isNotEmpty()) { "本地课表为空，请先在课表页同步课表" }
        return requireService().publish(
            campusId = context.campusId,
            ownerId = context.profileId,
            semesterId = SemesterConfig.currentSemesterId,
            courses = courses,
        )
    }

    suspend fun createInvite(): TimetableInviteDto {
        requireContext()
        return requireService().createInvite()
    }

    suspend fun accept(code: String): SharedTimetableSnapshotDto {
        require(TimetableSharingService.normalizeCode(code).length == 12) { "请输入 12 位邀请码" }
        requireContext()
        return requireService().accept(code)
    }

    suspend fun revoke(viewerId: String) {
        val context = requireContext()
        requireService().revoke(context.profileId, viewerId)
    }

    suspend fun stopSharing() {
        requireContext()
        requireService().stopSharing()
    }

    suspend fun leave(ownerId: String) {
        requireContext()
        requireService().leave(ownerId)
    }

    private suspend fun requireContext(): SharingContext {
        require(isLocallyAvailable) { "当前校园或身份暂不支持共享课表" }
        val profile = communityRepository.currentProfile()
        require(profile.is_profile_complete && profile.nickname.isNotBlank()) { "请先完善社区昵称后再使用共享课表" }
        require(backendAvailable()) { "共享课表服务正在更新，请稍后重试" }
        return SharingContext(profile.id, profile.campus_id)
    }

    private fun requireService(): TimetableSharingService =
        requireNotNull(serviceProvider()) { "共享课表服务未配置" }

    private data class SharingContext(val profileId: String, val campusId: String)
}
