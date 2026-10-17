import CryptoKit
import Foundation

nonisolated struct ICloudSyncValue: Codable, Equatable, Sendable {
    var key: String
    var payload: Data
    var modifiedAt: Date
    var revision: String = UUID().uuidString
    var deleted = false
    var filePath: String?
    var fileDigest: String?
    var isPersonalText: Bool { ["ScheduleMemo/", "CourseNote/", "CourseOccurrenceNote/", "CustomSchedule/", "TimetableCellReminder/", "ManualExam/"].contains { key.hasPrefix($0) } }
    var recordName: String { Self.digest(Data(key.utf8)) }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    var isSingleton: Bool { key.hasPrefix("preference/") || key.hasPrefix("settings/") || key.hasPrefix("school/") }
    static func winner(local: Self, remote: Self) -> Self {
        if local.isSingleton, local.modifiedAt != remote.modifiedAt { return local.modifiedAt > remote.modifiedAt ? local : remote }
        if local.deleted != remote.deleted { return local.deleted ? local : remote }
        if local.modifiedAt != remote.modifiedAt { return local.modifiedAt > remote.modifiedAt ? local : remote }
        if local.modifiedAt == .distantPast { return remote }
        return local.revision > remote.revision ? local : remote
    }
}

nonisolated struct ICloudSyncJournal: Codable {
    var records: [String: ICloudSyncValue] = [:]
    var pending: Set<String> = []
    var inbox: [String: ICloudSyncValue] = [:]
    var refetch: Set<String> = []
    var systemFields: [String: Data] = [:]
    var engineState: Data?
    var accountID: String?
    var lastSuccess: Date?
    var automaticRetryAt: Date?
    var enabled = false

    static func load(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    @discardableResult
    mutating func capture(_ values: [ICloudSyncValue], now: Date = Date()) -> Bool {
        var changed = false
        let live = Dictionary(uniqueKeysWithValues: values.map { ($0.key, $0) })
        for var value in values {
            if let previous = records[value.key], previous.payload == value.payload,
               previous.fileDigest == value.fileDigest, !previous.deleted { continue }
            // IDs are never reused after deletion.
            if records[value.key]?.deleted == true && !value.isSingleton { continue }
            // Initial caches retain their real fetch date. Later committed changes are
            // new data even if reminder restoration has not updated cache metadata yet.
            if records[value.key] != nil { value.modifiedAt = max(now, value.modifiedAt) }
            records[value.key] = value
            pending.insert(value.key)
            changed = true
        }
        for (key, var value) in records where !value.deleted && live[key] == nil {
            value.deleted = true; value.payload = Data(); value.modifiedAt = now; value.revision = UUID().uuidString
            records[key] = value; pending.insert(key); changed = true
        }
        return changed
    }
}
