import CloudKit
import Combine
import Foundation
import SwiftData
import OSLog
import UIKit

@MainActor
final class ICloudSyncCoordinator: ObservableObject {
    static let shared = ICloudSyncCoordinator()
    static let containerIdentifier = "iCloud.com.isaachuo.leafy"
    @Published private(set) var isEnabled = false
    @Published private(set) var isBusy = false
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var failure: String?
    @Published private(set) var failureDetails: String?
    @Published private(set) var phase: ICloudSyncPhase = .idle
    private var reportedError: Error?
    @Published private(set) var pendingCount = 0
    private var context: ModelContext?
    private var identity: CampusIdentity?
    private var journal = ICloudSyncJournal()
    private var journalURL: URL?
    private var engine: CKSyncEngine?
    private var task: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var applying = false
    private var loaded = false
    private var readyToSend = false
    private var generation = UUID()
    private let log = Logger(subsystem: "com.isaachuo.leafy", category: "ICloudSync")
    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: "personal-" + (identity?.scopeKey ?? "none")) }
    private var container: CKContainer { CKContainer(identifier: Self.containerIdentifier) }

    private init() {
        guard !AppRuntimeEnvironment.isRunningUnitTests else { return }
        for name in [ModelContext.didSave, UserDefaults.didChangeNotification, .customScheduleEventsDidChange,
                     .schoolDataDidRefresh, .semesterRuntimeConfigDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.localDataChanged() }
            })
        }
    }
    func configure(context: ModelContext) {
        let current = ActiveCampusContext.identity
        guard identity != current || self.context !== context else { return }
        stop()
        self.context = context; identity = current; loaded = false
        guard let current, !ReviewDemoMode.isEnabled,
              let store = CampusStoreScope.scopedStoreURL(for: current) else { publish(); return }
        journalURL = store.deletingLastPathComponent().appendingPathComponent("ICloudSync/journal.json")
        do {
            journal = try ICloudSyncJournal.load(from: journalURL!)
            loaded = true; failure = nil; failureDetails = nil; publish()
            if journal.enabled { retry() }
        } catch { report(error) }
    }
    func setEnabled(_ enabled: Bool) {
        guard loaded, !ReviewDemoMode.isEnabled else { failure = "当前本地数据不可用，不能开启同步。"; return }
        stop()
        if !enabled {
            journal.enabled = false
            do { try persist() } catch { report(error) }
            publish(); return
        }
        journal.enabled = true
        do { try persist(); retry(userConfirmed: true) } catch { report(error) }
    }
    func pauseForLocalCacheClear() throws {
        guard loaded else { return }
        stop(); journal.enabled = false
        // Clearing a local cache is not an instruction to erase the user's cloud copy.
        journal.records = [:]; journal.pending = []; journal.inbox = [:]; journal.refetch = []
        journal.engineState = nil; journal.systemFields = [:]
        try persist()
    }
    private func stop() {
        generation = UUID(); task?.cancel(); task = nil
        if let old = engine { Task { await old.cancelOperations() } }
        engine = nil; readyToSend = false; isBusy = false; phase = .idle
    }
    func retry(userConfirmed: Bool = false) {
        guard loaded, journal.enabled, context != nil, task == nil else { return }
        let token = generation
        task = Task { @MainActor in
            isBusy = true; phase = .account
            failure = nil; failureDetails = nil; reportedError = nil
            defer { if generation == token { isBusy = false; phase = .idle; task = nil; publish() } }
            do {
                guard try await container.accountStatus() == .available else {
                    throw ICloudSyncFailure.message("iCloud 暂不可用。请检查系统中的 Apple 账号、iCloud 设置和网络后重试。")
                }
                let account = try await container.userRecordID().recordName
                try check(token)
                if journal.accountID != nil && journal.accountID != account && !userConfirmed {
                    journal.enabled = false; try persist()
                    throw ICloudSyncFailure.message("Apple 账号已变化，同步已暂停。请重新开启以确认同步到当前账号。")
                }
                if journal.accountID != account {
                    journal.engineState = nil; journal.systemFields = [:]
                    // Pending downloads belong to the previous private database.
                    // Only the confirmed local records may be uploaded to the new account.
                    journal.inbox = [:]; journal.refetch = []; journal.lastSuccess = nil
                    journal.pending.formUnion(journal.records.keys)
                }
                journal.accountID = account
                UIApplication.shared.registerForRemoteNotifications()
                phase = .localData
                try capture()
                phase = .assets
                try await recoverInboxAssets(token: token)
                phase = .merge
                try applyInbox()
                if engine == nil {
                    let serialization = try journal.engineState.map { try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
                    var config = CKSyncEngine.Configuration(database: container.privateCloudDatabase, stateSerialization: serialization, delegate: self)
                    // No send is permitted until the initial remote fetch and merge finishes.
                    config.automaticallySync = false
                    engine = CKSyncEngine(config)
                }
                guard let engine else { return }
                phase = .cloudSpace
                let database = container.privateCloudDatabase
                let zone = zoneID
                try await ICloudZonePreparation.ensure(fetch: {
                    _ = try await database.recordZone(for: zone)
                }, create: {
                    try self.check(token)
                    _ = try await database.save(CKRecordZone(zoneID: zone))
                })
                try check(token)
                phase = .download
                try await engine.fetchChanges(.init(scope: .zoneIDs([zoneID])))
                try check(token)
                if let reportedError { throw reportedError }
                phase = .merge
                try applyInbox()
                if journal.inbox["school/courses"] == nil, journal.records["school/courses"] != nil, let context {
                    let committed = ModelContext(context.container)
                    try ICloudLocalData.markUnlinkedEdits(in: committed)
                    try capture()
                }
                readyToSend = true
                queuePending(on: engine)
                phase = .upload
                try await engine.sendChanges(.init(scope: .zoneIDs([zoneID])))
                try check(token)
                if let reportedError { throw reportedError }
                if journal.pending.isEmpty && journal.inbox.isEmpty && journal.refetch.isEmpty && failure == nil { journal.lastSuccess = Date() }
                try persist()
                try check(token)
                let state = try journal.engineState.map { try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
                var automatic = CKSyncEngine.Configuration(database: container.privateCloudDatabase, stateSerialization: state, delegate: self)
                automatic.automaticallySync = true
                self.engine = CKSyncEngine(automatic)
                queuePending(on: self.engine!)
                await engine.cancelOperations()
            } catch { if generation == token && !(error is CancellationError) { report(error) } }
        }
    }
    private func check(_ token: UUID) throws {
        guard generation == token, identity == ActiveCampusContext.identity, !Task.isCancelled else { throw CancellationError() }
    }
    private func localDataChanged() {
        guard loaded, journal.enabled, !applying, identity == ActiveCampusContext.identity else { return }
        let changed: Bool
        do { changed = try capture() } catch { report(error); return }
        // Unrelated defaults notifications must not repeatedly retry a rejected request.
        if changed && task == nil && (!journal.pending.isEmpty || !journal.inbox.isEmpty || !journal.refetch.isEmpty) { retry() }
    }
    @discardableResult
    private func capture() throws -> Bool {
        guard let context, journal.inbox.isEmpty else { return false }
        let committed = ModelContext(context.container)
        committed.autosaveEnabled = false
        let changed = journal.capture(try ICloudLocalData.capture(context: committed, journal: journal))
        if changed { try persist() }
        return changed
    }
    private func persist() throws {
        guard loaded, let journalURL else { throw ICloudSyncFailure.message("同步记录不可用。") }
        try journal.save(to: journalURL); publish()
    }
    private func publish() {
        isEnabled = loaded && journal.enabled; lastSuccess = journal.lastSuccess
        pendingCount = journal.pending.count + journal.inbox.count + journal.refetch.count
    }
    private func report(_ error: Error) {
        reportedError = error
        let diagnostic = ICloudSyncDiagnostic(error: error, phase: phase, container: Self.containerIdentifier,
            environment: Bundle.main.object(forInfoDictionaryKey: "LeafyCloudKitEnvironment") as? String ?? "未指定")
        failure = diagnostic.message; failureDetails = diagnostic.details
        log.error("Sync failed phase=\(self.phase.rawValue, privacy: .public) domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code) details=\(diagnostic.details, privacy: .private)")
        publish()
    }
    private func queuePending(on engine: CKSyncEngine) {
        guard readyToSend else { return }
        engine.state.add(pendingRecordZoneChanges: journal.pending.compactMap { key in
            journal.records[key].map { .saveRecord(CKRecord.ID(recordName: $0.recordName, zoneID: zoneID)) }
        })
    }
    private func fields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder); coder.finishEncoding(); return coder.encodedData
    }
    private func cloudRecord(_ value: ICloudSyncValue) throws -> CKRecord {
        let record: CKRecord
        if let data = journal.systemFields[value.key] {
            let coder = try NSKeyedUnarchiver(forReadingFrom: data)
            coder.requiresSecureCoding = true
            guard let restored = CKRecord(coder: coder) else { throw CocoaError(.fileReadCorruptFile) }
            coder.finishDecoding(); record = restored
        } else { record = CKRecord(recordType: "PersonalValue", recordID: CKRecord.ID(recordName: value.recordName, zoneID: zoneID)) }
        var header = value
        if value.payload.count > 600_000 {
            let payloadURL = journalURL!.deletingLastPathComponent().appendingPathComponent(value.recordName + ".payload")
            try value.payload.write(to: payloadURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            record["payloadAsset"] = CKAsset(fileURL: payloadURL)
            record["payloadDigest"] = ICloudSyncValue.digest(value.payload) as NSString
            header.payload = Data()
        } else { record["payloadAsset"] = nil; record["payloadDigest"] = nil }
        record["value"] = try ICloudLocalData.encode(header) as NSData
        if let path = value.filePath, !value.deleted {
            let url = try ICloudLocalData.fileURL(path)
            guard try ICloudLocalData.fileDigest(url) == value.fileDigest else { throw ICloudSyncFailure.message("附件在同步期间发生变化，请重试。") }
            record["asset"] = CKAsset(fileURL: url)
        } else { record["asset"] = nil }
        return record
    }
    private func receive(_ record: CKRecord) throws {
        guard record.recordID.zoneID == zoneID else { return }
        journal.refetch.insert(record.recordID.recordName)
        try persist()
        guard let data = record["value"] as? Data else { throw CocoaError(.fileReadCorruptFile) }
        var value = try JSONDecoder().decode(ICloudSyncValue.self, from: data)
        if record["payloadAsset"] != nil || record["payloadDigest"] != nil {
            guard let payload = (record["payloadAsset"] as? CKAsset)?.fileURL else {
                throw ICloudSyncFailure.message("iCloud 文本附件尚未下载完成，请重试。")
            }
            value.payload = try Data(contentsOf: payload)
            guard ICloudSyncValue.digest(value.payload) == record["payloadDigest"] as? String else { throw CocoaError(.fileReadCorruptFile) }
        }
        guard value.deleted || value.key.hasPrefix("file/") || !value.payload.isEmpty else {
            throw ICloudSyncFailure.message("iCloud 数据尚未下载完整，请重试。")
        }
        guard value.recordName == record.recordID.recordName,
              value.filePath == nil || value.key == "file/" + value.filePath! else { throw CocoaError(.fileReadCorruptFile) }
        journal.systemFields[value.key] = fields(of: record)
        journal.inbox[value.key] = value
        try persist()
        if let path = value.filePath, !value.deleted {
            guard let url = (record["asset"] as? CKAsset)?.fileURL,
                  try ICloudLocalData.fileDigest(url) == value.fileDigest else { throw ICloudSyncFailure.message("iCloud 附件下载校验失败，请重试。") }
            let target = try ICloudLocalData.fileURL(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Stage before advancing the engine's fetch token. Local files remain untouched until merge.
            let staged = journalURL!.deletingLastPathComponent().appendingPathComponent(value.recordName + ".asset")
            try Data(contentsOf: url, options: .mappedIfSafe).write(to: staged, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        journal.systemFields[value.key] = fields(of: record)
        journal.inbox[value.key] = value
        journal.refetch.remove(record.recordID.recordName)
        try persist()
    }
    private func recoverInboxAssets(token: UUID) async throws {
        for name in journal.refetch {
            let record = try await container.privateCloudDatabase.record(for: CKRecord.ID(recordName: name, zoneID: zoneID))
            try check(token); try receive(record)
        }
        let needed = try Set(journal.inbox.values.flatMap { try ICloudLocalData.requiredFiles(for: $0) })
        for path in needed where !FileManager.default.fileExists(atPath: try ICloudLocalData.fileURL(path).path) {
            let name = ICloudSyncValue.digest(Data(("file/" + path).utf8))
            let record = try await container.privateCloudDatabase.record(for: CKRecord.ID(recordName: name, zoneID: zoneID))
            try check(token); try receive(record)
        }
        for value in journal.inbox.values where value.filePath != nil && !value.deleted {
            let staged = journalURL!.deletingLastPathComponent().appendingPathComponent(value.recordName + ".asset")
            if FileManager.default.fileExists(atPath: staged.path), try ICloudLocalData.fileDigest(staged) == value.fileDigest { continue }
            let record = try await container.privateCloudDatabase.record(for: CKRecord.ID(recordName: value.recordName, zoneID: zoneID))
            try check(token)
            try receive(record)
        }
    }
    private func applyInbox() throws {
        guard let sourceContext = context, !journal.inbox.isEmpty else { return }
        let context = ModelContext(sourceContext.container)
        context.autosaveEnabled = false
        applying = true
        defer { applying = false }
        // Files precede metadata so existing readers never observe a missing received attachment.
        let values = journal.inbox.values.sorted { ($0.filePath == nil ? 1 : 0, $0.key) < ($1.filePath == nil ? 1 : 0, $1.key) }
        let notificationChange = values.contains { $0.key == "school/courses" || $0.key.hasPrefix("settings/timetable/") || $0.key.hasPrefix("CourseReminderSetting/") || $0.key.hasPrefix("TimetableCellReminder/") || $0.key.hasPrefix("CustomSchedule/") || $0.key.hasPrefix("ManualExam/") }
        let oldCourses = notificationChange ? try context.fetch(FetchDescriptor<Course>()).map(TimetableReminderRefreshPlan.courseSnapshot) : []
        let oldCells = notificationChange ? try context.fetch(FetchDescriptor<TimetableCellReminder>()).map { SyncedTimetableCellReminder($0).make() } : []
        let oldEvents = notificationChange ? try CustomScheduleStore.loadForSync() : []
        var notificationsInvalidated = false
        for remote in values {
            var chosen = remote
            if let local = journal.records[remote.key], local.revision != remote.revision {
                chosen = ICloudSyncValue.winner(local: local, remote: remote)
                if journal.pending.contains(local.key), local.payload != remote.payload,
                   !local.deleted, !remote.deleted, local.isPersonalText,
                   let copy = try ICloudLocalData.conflictCopy(chosen == local ? remote : local, context: context) {
                    journal.records[copy.key] = copy; journal.pending.insert(copy.key)
                }
            }
            do {
                if chosen == remote {
                    let files = try ICloudLocalData.requiredFiles(for: remote)
                    if try files.contains(where: { path in
                        let url = try ICloudLocalData.fileURL(path)
                        guard FileManager.default.fileExists(atPath: url.path) else { return true }
                        if let expected = (journal.inbox["file/" + path] ?? journal.records["file/" + path])?.fileDigest {
                            return try ICloudLocalData.fileDigest(url) != expected
                        }
                        return false
                    }) { continue }

                    if let path = remote.filePath, !remote.deleted {
                        let staged = journalURL!.deletingLastPathComponent().appendingPathComponent(remote.recordName + ".asset")
                        guard try ICloudLocalData.fileDigest(staged) == remote.fileDigest else { throw CocoaError(.fileReadCorruptFile) }
                        let target = try ICloudLocalData.fileURL(path)
                        try Data(contentsOf: staged, options: .mappedIfSafe).write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    }
                    try ICloudLocalData.apply(remote, context: context)
                    journal.records[remote.key] = remote; journal.pending.remove(remote.key)
                } else { journal.pending.insert(chosen.key) }
                try context.save()
                if notificationChange && chosen == remote && !notificationsInvalidated {
                    TimetableNotificationManager.cancelAllCourseReminders(courses: oldCourses)
                    TimetableNotificationManager.cancelAllCellReminders(oldCells)
                    TimetableNotificationManager.cancelAllCustomScheduleEvents(oldEvents)
                    notificationsInvalidated = true
                    NotificationCenter.default.post(name: .semesterRuntimeConfigDidChange, object: nil)
                }
                try LocalFileCleanup().retry(in: context)
                if chosen == remote {
                    if remote.key == "school/courses" { TimetableCacheMetadata.lastSyncAt = remote.modifiedAt; TimetableCacheMetadata.lastFailureMessage = nil }
                    if remote.key == "school/grades" { SchoolDataCache.markGradeDetailsSynced(at: remote.modifiedAt) }
                }
                journal.inbox.removeValue(forKey: remote.key)
                try persist()
            } catch { context.rollback(); throw error }
        }
        LeafyWidgetSnapshotBuilder.publish(from: context, isAuthenticated: true)
        NotificationCenter.default.post(name: .semesterRuntimeConfigDidChange, object: nil)
        NotificationCenter.default.post(name: .customScheduleEventsDidChange, object: nil)
        TimetableBackgroundStore.notifySettingsDidChange()
    }
    func receiveRemoteNotification() async -> Bool {
        guard journal.enabled else { return false }
        let previous = journal.lastSuccess
        retry()
        await task?.value
        return journal.lastSuccess != previous
    }
    func deleteCloudData() async {
        guard loaded, let identity, identity == ActiveCampusContext.identity else { return }
        let zone = zoneID
        stop(); journal.enabled = false
        do {
            try persist(); isBusy = true
            defer { isBusy = false }
            do { _ = try await container.privateCloudDatabase.deleteRecordZone(withID: zone) }
            catch let error as CKError where error.code == .zoneNotFound { /* Already deleted. */ }
            guard identity == ActiveCampusContext.identity else { return }
            journal.engineState = nil; journal.systemFields = [:]; journal.inbox = [:]; journal.refetch = []; journal.lastSuccess = nil
            journal.pending = Set(journal.records.keys)
            failure = nil; failureDetails = nil; try persist()
        } catch { report(error) }
    }
}

extension ICloudSyncCoordinator: CKSyncEngineDelegate {
    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await process(event, engine: syncEngine)
    }
    private func process(_ event: CKSyncEngine.Event, engine source: CKSyncEngine) {
        guard source === engine, loaded, journal.enabled, identity == ActiveCampusContext.identity else { return }
        do {
            switch event {
            case .stateUpdate(let update): journal.engineState = try JSONEncoder().encode(update.stateSerialization); try persist()
            case .accountChange(let change):
                switch change.changeType {
                case .signIn(let current) where current.recordName == journal.accountID: break
                default:
                    stop(); journal.enabled = false; try persist()
                    failure = "Apple 账号已变化，同步已暂停。请重新开启以确认同步到当前账号。"; failureDetails = nil
                }
            case .fetchedRecordZoneChanges(let changes):
                // Persist record IDs before staging any attachment. Even a decoding or
                // download failure can be fetched again after the engine advances its cursor.
                journal.refetch.formUnion(changes.modifications.filter { $0.record.recordID.zoneID == zoneID }.map { $0.record.recordID.recordName })
                try persist()
                for item in changes.modifications {
                    do { try receive(item.record) } catch { report(error) }
                }
                for deletion in changes.deletions where deletion.recordID.zoneID == zoneID {
                    if let local = journal.records.values.first(where: { $0.recordName == deletion.recordID.recordName }) {
                        var tombstone = local; tombstone.deleted = true; tombstone.modifiedAt = Date(); tombstone.revision = UUID().uuidString
                        journal.inbox[local.key] = tombstone
                    }
                }
                try persist(); try applyInbox()
            case .fetchedDatabaseChanges(let changes):
                if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                    stop(); journal.enabled = false
                    journal.engineState = nil; journal.systemFields = [:]
                    journal.pending = Set(journal.records.keys)
                    try persist()
                    failure = "此身份的 iCloud 数据已被删除，同步已暂停。本机数据已保留。"; failureDetails = nil
                }
            case .sentRecordZoneChanges(let changes):
                for record in changes.savedRecords {
                    guard let data = record["value"] as? Data else { continue }
                    let saved = try JSONDecoder().decode(ICloudSyncValue.self, from: data)
                    journal.systemFields[saved.key] = fields(of: record)
                    if journal.records[saved.key]?.revision == saved.revision { journal.pending.remove(saved.key) }
                }
                for failed in changes.failedRecordSaves {
                    if failed.error.code == .serverRecordChanged, let server = failed.error.serverRecord {
                        try receive(server)
                    } else { report(failed.error) }
                }
                try applyInbox(); try persist()
                if changes.failedRecordSaves.allSatisfy({ $0.error.code == .serverRecordChanged }) { queuePending(on: source) }
            case .sentDatabaseChanges(let changes):
                for failed in changes.failedZoneSaves { report(failed.error) }
            case .didFetchChanges:
                if readyToSend, journal.inbox["school/courses"] == nil, journal.records["school/courses"] != nil, let context {
                    let committed = ModelContext(context.container)
                    try ICloudLocalData.markUnlinkedEdits(in: committed)
                    try capture(); queuePending(on: source)
                }
            case .didSendChanges:
                if journal.pending.isEmpty && journal.inbox.isEmpty && journal.refetch.isEmpty && failure == nil { journal.lastSuccess = Date(); try persist() }
            case .didFetchRecordZoneChanges(let result):
                if let error = result.error, error.code != .zoneNotFound { report(error) }
            default: break
            }
        } catch { report(error) }
    }
    nonisolated func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await batch(context, engine: syncEngine)
    }
    private func batch(_ context: CKSyncEngine.SendChangesContext, engine source: CKSyncEngine) -> CKSyncEngine.RecordZoneChangeBatch? {
        guard source === engine, readyToSend, journal.enabled, identity == ActiveCampusContext.identity else { return nil }
        do {
            let pendingIDs = Set(source.state.pendingRecordZoneChanges.compactMap { change -> CKRecord.ID? in
                if case .saveRecord(let id) = change { return id }; return nil
            })
            let values = journal.pending.sorted().compactMap { journal.records[$0] }.filter {
                let id = CKRecord.ID(recordName: $0.recordName, zoneID: zoneID)
                return pendingIDs.contains(id) && context.options.scope.contains(id)
            }.prefix(100)
            guard !values.isEmpty else { return nil }
            return CKSyncEngine.RecordZoneChangeBatch(recordsToSave: try values.map(cloudRecord))
        } catch { report(error); return nil }
    }
    nonisolated func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        await fetchOptions()
    }
    private func fetchOptions() -> CKSyncEngine.FetchChangesOptions { .init(scope: .zoneIDs([zoneID])) }
}
