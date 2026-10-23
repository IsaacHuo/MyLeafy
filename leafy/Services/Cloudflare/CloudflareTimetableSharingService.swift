import Foundation
import OSLog

nonisolated protocol TimetableSharing: Sendable {
    func publishSnapshot(courses: [SharedTimetableCourse]) async throws -> SharedTimetableSnapshot
    @discardableResult func publishExistingSnapshotIfNeeded(courses: [SharedTimetableCourse]) async -> Bool
    func fetchMySnapshot() async throws -> SharedTimetableSnapshot?
    func fetchViewableSnapshots() async throws -> [SharedTimetableSnapshot]
    func fetchMyShareMembers() async throws -> [TimetableShareMember]
    func fetchMyInvites() async throws -> [TimetableInvite]
    func createInvite() async throws -> TimetableInvite
    func acceptInvite(code: String) async throws -> SharedTimetableSnapshot
    func revokeShare(viewerID: UUID) async throws
    func stopSharing() async throws
    func leaveShare(ownerID: UUID) async throws
}

nonisolated struct CloudflareTimetableSharingService: TimetableSharing {
    private let backend = CloudflareCommunityRepository()
    private func requireProfile() async throws -> CommunityProfile {
        let scope = await CampusOperationScope()
        try await backend.ensureAnonymousSession()
        try await scope.check()
        guard let profile = try await backend.fetchCurrentProfile() else { throw TimetableSharingError.missingProfile }
        try await scope.check()
        guard profile.isProfileComplete else { throw TimetableSharingError.profileCompletionRequired }
        return profile
    }
    func publishSnapshot(courses: [SharedTimetableCourse]) async throws -> SharedTimetableSnapshot {
        let scope = await CampusOperationScope()
        _ = try await requireProfile()
        try await scope.check()
        let calendar = SharedTimetableCalendar.current
        let semesterID = SemesterConfig.currentSemesterID
        try await scope.check()
        struct Input: Encodable {
            let semester_id: String; let courses: [SharedTimetableCourse]; let calendar_config: SharedTimetableCalendar
        }
        return try await backend.request(
            "/v1/timetables",
            method: "PUT",
            body: Input(semester_id: semesterID, courses: courses, calendar_config: calendar)
        )
    }
    @discardableResult
    func publishExistingSnapshotIfNeeded(courses: [SharedTimetableCourse]) async -> Bool {
        let scope = await CampusOperationScope()
        do {
            guard try await fetchMySnapshot() != nil else { return false }
            try await scope.check()
            _ = try await publishSnapshot(courses: courses)
            return true
        } catch {
            CommunityDiagnostics.log
                .error("Cloudflare shared timetable refresh failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    func snapshots() async throws -> [SharedTimetableSnapshot] {
        let all: [SharedTimetableSnapshot] = try await backend.get("/v1/timetables")
        // The server orders newest first; each owner exposes one current container.
        var seen = Set<UUID>()
        return all.filter { seen.insert($0.ownerID).inserted }
    }
    func fetchMySnapshot() async throws -> SharedTimetableSnapshot? {
        let scope = await CampusOperationScope()
        let profile = try await requireProfile()
        try await scope.check()
        return try await snapshots().first { $0.ownerID == profile.id }
    }
    func fetchViewableSnapshots() async throws -> [SharedTimetableSnapshot] {
        let scope = await CampusOperationScope()
        let profile = try await requireProfile()
        try await scope.check()
        return try await snapshots().filter { $0.ownerID != profile.id }
    }
    func fetchMyShareMembers() async throws -> [TimetableShareMember] {
        let scope = await CampusOperationScope()
        _ = try await requireProfile()
        try await scope.check()
        return try await backend.get("/v1/timetables/members")
    }
    func fetchMyInvites() async throws -> [TimetableInvite] {
        let scope = await CampusOperationScope()
        _ = try await requireProfile()
        try await scope.check()
        return try await backend.get("/v1/timetables/invites")
    }
    func createInvite() async throws -> TimetableInvite {
        let scope = await CampusOperationScope()
        _ = try await requireProfile()
        try await scope.check()
        return try await backend.request("/v1/timetables/invites", body: CloudflareCommunityRepository.Empty())
    }
    func acceptInvite(code: String) async throws -> SharedTimetableSnapshot {
        let scope = await CampusOperationScope()
        _ = try await requireProfile()
        try await scope.check()
        return try await backend.request(
            "/v1/timetables/invites/accept",
            body: ["code": TimetableSharingService.normalizeInviteCode(code)]
        )
    }
    func revokeShare(viewerID: UUID) async throws {
        let scope = await CampusOperationScope()
        let members = try await fetchMyShareMembers()
        try await scope.check()
        guard let member = members.first(where: { $0.viewerID == viewerID })
        else { throw TimetableSharingError.notShareOwner }
        try await backend.perform("/v1/timetables/members/\(member.id)", method: "DELETE")
    }
    func stopSharing() async throws { try await backend.perform("/v1/timetables/stop") }
    func leaveShare(ownerID: UUID) async throws {
        let scope = await CampusOperationScope()
        let members: [TimetableShareMember] = try await backend.get(
            "/v1/timetables/members",
            backend.query(["direction": "viewing"])
        )
        try await scope.check()
        guard let member = members.first(where: { $0.ownerID == ownerID })
        else { throw TimetableSharingError.notShareOwner }
        try await backend.perform("/v1/timetables/members/\(member.id)/leave")
    }
}
