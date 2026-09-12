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
        try await backend.ensureAnonymousSession()
        guard let profile = try await backend.fetchCurrentProfile() else { throw TimetableSharingError.missingProfile }
        guard profile.isProfileComplete else { throw TimetableSharingError.profileCompletionRequired }
        return profile
    }
    func publishSnapshot(courses: [SharedTimetableCourse]) async throws -> SharedTimetableSnapshot {
        guard !courses.isEmpty else { throw TimetableSharingError.emptySnapshot }
        _ = try await requireProfile()
        let semester = await SemesterConfig.refreshRemoteIfAvailable()
        struct Input: Encodable { let semester_id: String; let courses: [SharedTimetableCourse] }
        return try await backend.request("/v1/timetables", method: "PUT", body: Input(semester_id: semester.semesterID, courses: courses))
    }
    @discardableResult
    func publishExistingSnapshotIfNeeded(courses: [SharedTimetableCourse]) async -> Bool {
        guard !courses.isEmpty else { return false }
        do {
            guard try await fetchMySnapshot() != nil else { return false }
            _ = try await publishSnapshot(courses: courses)
            return true
        } catch {
            CommunityDiagnostics.log.error("Cloudflare shared timetable refresh failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    func snapshots() async throws -> [SharedTimetableSnapshot] {
        let semester = await SemesterConfig.refreshRemoteIfAvailable()
        return try await backend.get("/v1/timetables", backend.query(["semester_id":semester.semesterID]))
    }
    func fetchMySnapshot() async throws -> SharedTimetableSnapshot? {
        let profile = try await requireProfile()
        return try await snapshots().first { $0.ownerID == profile.id }
    }
    func fetchViewableSnapshots() async throws -> [SharedTimetableSnapshot] {
        let profile = try await requireProfile()
        return try await snapshots().filter { $0.ownerID != profile.id }
    }
    func fetchMyShareMembers() async throws -> [TimetableShareMember] {
        _ = try await requireProfile()
        return try await backend.get("/v1/timetables/members")
    }
    func fetchMyInvites() async throws -> [TimetableInvite] {
        _ = try await requireProfile()
        return try await backend.get("/v1/timetables/invites")
    }
    func createInvite() async throws -> TimetableInvite {
        _ = try await requireProfile()
        return try await backend.request("/v1/timetables/invites", body: CloudflareCommunityRepository.Empty())
    }
    func acceptInvite(code: String) async throws -> SharedTimetableSnapshot {
        _ = try await requireProfile()
        return try await backend.request("/v1/timetables/invites/accept", body: ["code":TimetableSharingService.normalizeInviteCode(code)])
    }
    func revokeShare(viewerID: UUID) async throws {
        let members = try await fetchMyShareMembers()
        guard let member = members.first(where: { $0.viewerID == viewerID }) else { throw TimetableSharingError.notShareOwner }
        try await backend.perform("/v1/timetables/members/\(member.id)", method: "DELETE")
    }
    func stopSharing() async throws { try await backend.perform("/v1/timetables/stop") }
    func leaveShare(ownerID: UUID) async throws {
        let members: [TimetableShareMember] = try await backend.get("/v1/timetables/members", backend.query(["direction":"viewing"]))
        guard let member = members.first(where: { $0.ownerID == ownerID }) else { throw TimetableSharingError.notShareOwner }
        try await backend.perform("/v1/timetables/members/\(member.id)/leave")
    }
}
