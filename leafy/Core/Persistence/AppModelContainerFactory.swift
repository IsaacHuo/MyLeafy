import Foundation
import SwiftData

struct AppModelContainerSetup {
    let container: ModelContainer
    let recoveryMessage: String?
}

nonisolated enum AppRuntimeEnvironment {
    static let isRunningUnitTests = ProcessInfo.processInfo.environment["LEAFY_UNIT_TESTING"] == "1"
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

enum AppModelContainerFactory {
    static func make() throws -> AppModelContainerSetup {
        let schema = Schema([
            Course.self, Grade.self,
            CourseNote.self, CourseOccurrenceNote.self, CourseReminderSetting.self, TimetableCellReminder.self,
            FavoriteClassroom.self, FavoriteCampusLink.self, PostgraduateTarget.self, StudyTimeRecord.self, HonorRecord.self,
            LearningMaterialDocument.self, LearningProject.self, LearningProjectTask.self,
            CareerResumeDocument.self, CareerTask.self, CareerOpportunity.self,
            FitnessTestRecord.self,
            ComprehensiveQualityRecord.self, ComprehensiveQualityComponentEntry.self, ComprehensiveQualityEvidenceDocument.self,
            MedicalLedgerEntry.self, MedicalLedgerPhoto.self,
            ScheduleMemo.self, ScheduleMemoImage.self, ScheduleMemoAttachment.self, ScheduleMemoAudio.self,
        ])
        let modelConfiguration: ModelConfiguration
        if AppRuntimeEnvironment.isRunningUnitTests {
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            modelConfiguration = CampusStoreScope.configuration(schema: schema)
        }

        if !AppRuntimeEnvironment.isRunningUnitTests, ActiveCampusContext.identity != nil {
            try UserTimetableSettingsStore.freezeIfNeeded()
        }
        let container = try open(schema: schema, configuration: modelConfiguration)
        return AppModelContainerSetup(container: container, recoveryMessage: nil)
    }

    static func open(schema: Schema, configuration: ModelConfiguration) throws -> ModelContainer {
        if !configuration.isStoredInMemoryOnly {
            try FileManager.default.createDirectory(at: configuration.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func rebuild() throws -> AppModelContainerSetup {
        guard let identity = CampusIdentityStore.currentIdentity(),
              let url = CampusStoreScope.scopedStoreURL(for: identity) else {
            return try make()
        }
        return try rebuildStore(at: url) {
            let container = try make().container
            let syncURL = url.deletingLastPathComponent().appendingPathComponent("ICloudSync/journal.json")
            if FileManager.default.fileExists(atPath: syncURL.path) {
                let previous = try ICloudSyncJournal.load(from: syncURL)
                var reset = ICloudSyncJournal()
                reset.accountID = previous.accountID
                reset.enabled = previous.enabled
                // A recovery-created empty database must fetch cloud data, not publish deletions.
                try reset.save(to: syncURL)
            }
            return container
        }
    }

    static func rebuildStore(
        at url: URL,
        copyFile: (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) },
        open: () throws -> ModelContainer
    ) throws -> AppModelContainerSetup {
        let manager = FileManager.default
        let candidates = [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm"),
                          url.deletingLastPathComponent().appendingPathComponent("PendingLocalFileCleanup.json")]
        let files = candidates.filter { manager.fileExists(atPath: $0.path) }
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("LeafyStoreBackups", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: backup, withIntermediateDirectories: true)
        // No original is removed until every store component has a verified copy.
        for file in files {
            let destination = backup.appendingPathComponent(file.lastPathComponent)
            try copyFile(file, destination)
            guard try sameContents(file, destination) else { throw CocoaError(.fileReadCorruptFile) }
        }
        do {
            for file in files { try manager.removeItem(at: file) }
            let container = try open()
            return AppModelContainerSetup(
                container: container,
                recoveryMessage: L10n.text("已创建新的本地数据库。原数据库保留在备份 %@ 中，尚未恢复其中的个人数据。", backup.lastPathComponent)
            )
        } catch {
            let originalError = error
            for file in candidates where manager.fileExists(atPath: file.path) { try manager.removeItem(at: file) }
            for file in files {
                try copyFile(backup.appendingPathComponent(file.lastPathComponent), file)
            }
            throw originalError
        }
    }

    private static func sameContents(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let left = try FileHandle(forReadingFrom: lhs)
        let right = try FileHandle(forReadingFrom: rhs)
        defer { try? left.close(); try? right.close() }
        while true {
            let a = try left.read(upToCount: 64 * 1024) ?? Data()
            let b = try right.read(upToCount: 64 * 1024) ?? Data()
            guard a == b else { return false }
            if a.isEmpty { return true }
        }
    }
}
