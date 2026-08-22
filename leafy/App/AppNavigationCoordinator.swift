import Combine
import Foundation

enum ProfileRoute: Hashable {
    case timetableSharing
    case cacheSync
    case timetableBackground
}

enum RootTab: Hashable {
    case timetable
    case community
    case schedule
    case academics
    case profile
}

nonisolated struct TeacherRatingRoute: Hashable, Sendable {
    let name: String
}

enum AppAccountDeletionOutcome: Equatable, Identifiable {
    case deleted
    case deletedWithLocalCleanupWarning(String)

    var id: Int {
        switch self {
        case .deleted:
            return 0
        case .deletedWithLocalCleanupWarning:
            return 1
        }
    }

    var title: String {
        switch self {
        case .deleted:
            return "MyLeafy 账户已删除"
        case .deletedWithLocalCleanupWarning:
            return "账户已删除，本机清理未全部完成"
        }
    }

    var message: String {
        switch self {
        case .deleted:
            return "线上账户与当前设备上的 MyLeafy 数据已永久删除。北京林业大学官方教务账户未受影响。"
        case .deletedWithLocalCleanupWarning(let detail):
            return "线上账户已永久删除，但部分本机数据未能清理：\(detail) 如仍有残留，可删除并重新安装 App。"
        }
    }
}

extension RootTab: CaseIterable, Identifiable {
    static var allCases: [RootTab] {
        [.timetable, .community, .schedule, .academics, .profile]
    }

    static func visibleCases(isCommunityEnabled: Bool) -> [RootTab] {
        allCases.filter { isCommunityEnabled || $0 != .community }
    }

    var id: RootTab { self }

    func title(language: AppLanguagePreference) -> String {
        switch self {
        case .timetable:
            return L10n.text("课表", language: language)
        case .community:
            return L10n.text("社区", language: language)
        case .schedule:
            return L10n.text("日迹", language: language)
        case .academics:
            return L10n.text("校园", language: language)
        case .profile:
            return L10n.text("我的", language: language)
        }
    }

    var systemImage: String {
        switch self {
        case .timetable: return "calendar"
        case .community: return "person.2"
        case .schedule: return "calendar.day.timeline.left"
        case .academics: return "book.closed"
        case .profile: return "person"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .timetable: return "calendar"
        case .community: return "person.2.fill"
        case .schedule: return "calendar.day.timeline.left"
        case .academics: return "book.closed.fill"
        case .profile: return "person.fill"
        }
    }
}

@MainActor
final class AppNavigationCoordinator: ObservableObject {
    @Published var selectedRootTab: RootTab = .timetable
    @Published var selectedAcademicTab: AcademicPrimaryTab = .cultivation
    @Published var requestedAcademicRoute: AcademicRoute?
    @Published var requestedAcademicDetailRoute: AcademicDetailRoute?
    @Published var requestedTeacherRatingRoute: TeacherRatingRoute?
    @Published var requestedScheduleDestination: ScheduleDestination?
    @Published var requestedClassroomLookup: ClassroomLookupRequest?
    @Published var requestedProfileRoute: ProfileRoute?
    @Published var requestedTimetableInviteCode: String?
    @Published var requestedTimetableCourseID: UUID?
    @Published var requestedCommunityPostID: UUID?
    @Published var accountDeletionOutcome: AppAccountDeletionOutcome?
    @Published private(set) var requiresLoginAfterAccountDeletion = false
    private var deferredRouteRequestTask: Task<Void, Never>?

    func completeAccountDeletion(with outcome: AppAccountDeletionOutcome) {
        requiresLoginAfterAccountDeletion = true
        selectedRootTab = .timetable
        accountDeletionOutcome = outcome
    }

    func authenticationDidResume() {
        requiresLoginAfterAccountDeletion = false
    }

    func sanitizePublicRootTab(isCommunityEnabled: Bool) {
        if selectedRootTab == .community && !isCommunityEnabled {
            selectedRootTab = .timetable
        }
    }

    func openAcademic(tab: AcademicPrimaryTab) {
        selectedAcademicTab = tab
        selectedRootTab = .academics
    }

    func openAcademicRoute(_ route: AcademicRoute) {
        switch route {
        case .grades:
            selectedAcademicTab = .cultivation
        case .emptyClassroom:
            selectedAcademicTab = .classrooms
        }
        selectedRootTab = .academics
        deferRouteRequest {
            self.requestedAcademicRoute = route
        }
    }

    func openAcademicDetailRoute(_ route: AcademicDetailRoute) {
        selectedAcademicTab = route.tab
        selectedRootTab = .academics
        deferRouteRequest {
            self.requestedAcademicDetailRoute = route
        }
    }

    func openTeacherRating(name: String) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return }
        selectedAcademicTab = .ratings
        selectedRootTab = .academics
        deferRouteRequest {
            self.requestedTeacherRatingRoute = TeacherRatingRoute(name: normalizedName)
        }
    }

    func openTimetableProcessing() {
        selectedRootTab = .timetable
    }

    func openScheduleDestination(_ destination: ScheduleDestination) {
        deferredRouteRequestTask?.cancel()
        requestedAcademicRoute = nil
        requestedAcademicDetailRoute = nil
        requestedTeacherRatingRoute = nil
        requestedClassroomLookup = nil
        requestedProfileRoute = nil
        requestedScheduleDestination = destination
        selectedRootTab = .schedule
    }

    func openProfileRoute(_ route: ProfileRoute) {
        selectedRootTab = .profile
        deferRouteRequest {
            self.requestedProfileRoute = route
        }
    }

    func openTimetableSharing(inviteCode: String? = nil) {
        requestedTimetableInviteCode = inviteCode
        openProfileRoute(.timetableSharing)
    }

    func openClassroomLookup(building: String, room: String) {
        let request = ClassroomLookupRequest(building: building, room: room)
        selectedAcademicTab = .classrooms
        selectedRootTab = .academics
        deferRouteRequest {
            self.requestedClassroomLookup = request
        }
    }

    func openCommunityPost(id: UUID) {
        requestedCommunityPostID = id
        selectedRootTab = .community
    }

    func handle(url: URL) {
        if let postID = CommunityPostDeepLink(url: url)?.postID {
            openCommunityPost(id: postID)
            return
        }

        if let invite = TimetableInviteDeepLink(url: url) {
            openTimetableSharing(inviteCode: invite.code)
            return
        }

        guard let route = LeafyWidgetRoute(url: url) else { return }

        switch route {
        case .timetable:
            selectedRootTab = .timetable
        case .course(let id):
            requestedTimetableCourseID = id
            selectedRootTab = .timetable
        case .timetableSharing:
            openTimetableSharing()
        case .cacheSync:
            openProfileRoute(.cacheSync)
        case .scheduleReports:
            openScheduleDestination(.scheduleReports)
        }
    }

    private func deferRouteRequest(_ request: @escaping @MainActor () -> Void) {
        requestedAcademicRoute = nil
        requestedAcademicDetailRoute = nil
        requestedTeacherRatingRoute = nil
        requestedScheduleDestination = nil
        requestedClassroomLookup = nil
        requestedProfileRoute = nil
        deferredRouteRequestTask?.cancel()
        deferredRouteRequestTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            request()
        }
    }
}

nonisolated struct TimetableInviteDeepLink: Equatable {
    let code: String

    init?(url: URL) {
        if url.scheme == "leafy", url.host == "timetable-invite" {
            guard let codeValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "code" })?
                .value
            else { return nil }
            let normalized = TimetableSharingService.normalizeInviteCode(codeValue)
            guard normalized.count == 12 else { return nil }
            code = normalized
            return
        }

        guard url.scheme == "https",
              url.host == "myleafy.space"
        else { return nil }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 3,
              components[0] == "share",
              components[1] == "timetable"
        else { return nil }

        let normalized = TimetableSharingService.normalizeInviteCode(components[2])
        guard normalized.count == 12 else { return nil }
        code = normalized
    }
}

nonisolated struct CommunityPostDeepLink: Equatable {
    let postID: UUID

    init?(url: URL) {
        if url.scheme == "leafy", url.host == "community-post" {
            guard let idValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "id" })?
                .value,
                  let postID = UUID(uuidString: idValue)
            else { return nil }
            self.postID = postID
            return
        }

        guard url.scheme == "https",
              url.host == "myleafy.space"
        else { return nil }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 4,
              components[0] == "share",
              components[1] == "community",
              components[2] == "post",
              let postID = UUID(uuidString: components[3])
        else { return nil }

        self.postID = postID
    }
}
