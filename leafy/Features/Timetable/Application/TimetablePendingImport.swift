import Foundation

nonisolated struct TimetablePendingImport: Codable {
    let records: [ParsedCourseRecord]
    let sourceSemesterID: String
    let fetchedAt: Date
    var requiredPeriods: Int { records.flatMap(\.duration).max() ?? 1 }
}

@MainActor
enum TimetablePendingImportStore {
    private static func url() throws -> URL {
        guard let identity = ActiveCampusContext.identity,
              let store = CampusStoreScope.scopedStoreURL(for: identity) else { throw CocoaError(.fileNoSuchFile) }
        return store.deletingLastPathComponent().appendingPathComponent("PendingTimetableImport.json")
    }
    static func load() throws -> TimetablePendingImport? {
        let url = try url()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let pending = try JSONDecoder().decode(TimetablePendingImport.self, from: Data(contentsOf: url))
        if let lastSync = TimetableCacheMetadata.lastSyncAt, pending.fetchedAt <= lastSync { return nil }
        return pending
    }
    static func save(records: [ParsedCourseRecord], semesterID: String) throws {
        let url = try url()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pending = TimetablePendingImport(records: records, sourceSemesterID: semesterID, fetchedAt: Date())
        try JSONEncoder().encode(pending).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func clear() throws {
        let url = try url()
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

struct TimetableConfigurationRequired: LocalizedError {
    let periods: Int
    var errorDescription: String? { "已拉取到第 \(periods) 节课程，数据已暂存。请在课表设置中补全节次与作息，保存后即可导入，不需要重新拉取。" }
}
