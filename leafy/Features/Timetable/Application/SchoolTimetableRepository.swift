import Foundation

protocol SchoolTimetableRepository: Sendable {
    func fetchTimetableDocument() async throws -> FetchedTimetableDocument
}

struct LiveSchoolTimetableRepository: SchoolTimetableRepository {
    nonisolated init() {}

    @MainActor
    func fetchTimetableDocument() async throws -> FetchedTimetableDocument {
        try await Self.activeManagerForRefresh().fetchTimetable()
    }

    @MainActor
    static func activeManagerForRefresh() -> SchoolNetworkManager {
        SchoolTimetableConnection.shared.manager(portal: ActiveCampusContext.networkManager.currentPortal)
    }
}
