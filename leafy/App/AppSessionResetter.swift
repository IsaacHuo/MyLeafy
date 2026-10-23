import Foundation
import SwiftData

nonisolated enum AppAccountDeletionPolicy {
    static func canDelete(isReviewDemoMode: Bool, eduID: String?) -> Bool {
        if isReviewDemoMode || ReviewDemoDataSeeder.isDemoEduID(eduID) {
            return ReviewDemoDataSeeder.isInstallationScopedDemoEduID(eduID)
        }
        return true
    }
}

@MainActor
enum AppAccountDeletionCoordinator {
    static func delete(
        remotely: () async throws -> Void,
        locally: () throws -> Void
    ) async throws -> Error? {
        let ownerScope = ActiveCampusContext.identity?.scopeKey
        try await remotely()
        guard ActiveCampusContext.identity?.scopeKey == ownerScope else {
            throw AppLocalDataDeletionError(failures: [L10n.text("线上账户已删除，但当前身份已变化，尚未清理新身份的数据。")])
        }
        do {
            try locally()
            return nil
        } catch {
            return error
        }
    }
}

@MainActor
enum AppSessionResetter {
    static func returnToLogin(modelContext: ModelContext? = nil) throws {
        if ReviewDemoMode.isEnabled ||
            ReviewDemoDataSeeder.isDemoEduID(ActiveCampusContext.networkManager.authenticatedEduID) {
            try ReviewDemoDataSeeder.exit(using: modelContext)
        }
        ActiveCampusContext.networkManager.clearSession()
        LeafyWidgetSnapshotBuilder.publishNeedsLogin()
        CommunitySessionManager.shared.detachFromSchoolSession()
    }

    static func deleteAllUserData(modelContext: ModelContext) throws {
        var cleanupFailures: [String] = []
        func attempt(_ name: String, operation: () throws -> Void) {
            do {
                try operation()
            } catch {
                cleanupFailures.append("\(name): \(error.localizedDescription)")
            }
        }

        try ICloudSyncCoordinator.shared.pauseForLocalCacheClear()
        let courses = try modelContext.fetch(FetchDescriptor<Course>()).map(TimetableReminderRefreshPlan.courseSnapshot)
        let cellReminders = try modelContext.fetch(FetchDescriptor<TimetableCellReminder>()).map { SyncedTimetableCellReminder($0).make() }
        if let warning = try deleteLocalRecords(in: modelContext) { cleanupFailures.append(warning) }
        TimetableNotificationManager.cancelAllCourseReminders(courses: courses)
        TimetableNotificationManager.cancelAllCellReminders(cellReminders)
        attempt("日程通知") { try ScheduleReportNotificationManager.clearScheduledNotifications() }

        attempt("课表背景") {
            try TimetableBackgroundStore.deleteAllBackgroundFiles()
        }
        attempt("社区草稿") {
            try LocalCommunityPostDraftRepository.shared.deleteAllDraftData()
        }
        attempt("教务登录凭据") {
            try SchoolLoginCredentialStore.deleteAll()
        }
        CommunityPostCardGenerator.cleanupStaleRenderedFiles()

        SchoolDataCache.clearDiscoverCaches()
        TimetableCacheMetadata.clear()
        CustomScheduleStore.clear()
        let sunshineRunSettings = SunshineRunStore.loadReminderSettings()
        SunshineRunNotificationManager.cancelScheduledNotifications(settings: sunshineRunSettings)
        SunshineRunStore.clear()
        ScheduleReportSettingsStore.clear()

        ReviewDemoMode.disable()
        ActiveCampusContext.networkManager.clearSession()
        LeafyWidgetSnapshotBuilder.publishNeedsLogin()
        CommunitySessionManager.shared.detachFromSchoolSession()

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }
        // Keep Demo disabled after the domain wipe so the active process cannot
        // re-persist its pre-deletion state before the root view changes.
        ReviewDemoMode.disable()

        if !cleanupFailures.isEmpty {
            throw AppLocalDataDeletionError(failures: cleanupFailures)
        }
    }

    /// Database failures preserve records/files; a returned warning means deletion committed.
    static func deleteLocalRecords(
        in modelContext: ModelContext,
        cleanup: LocalFileCleanup? = nil,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> String? {
        let records = try localRecords(in: modelContext)
        let files = records.compactMap { record -> LocalFileCleanup.File? in
            switch record {
            case let value as ScheduleMemoImage:
                return .init(value, url: ScheduleMemoImageStore.directoryURL().appendingPathComponent(value.localFilename))
            case let value as ScheduleMemoAttachment:
                return ScheduleMemoAttachmentStore.fileURL(for: value).map { .init(value, url: $0) }
            case let value as ScheduleMemoAudio:
                return ScheduleMemoAudioStore.fileURL(named: value.localFilename).map { .init(value, url: $0) }
            case let value as LearningMaterialDocument:
                return .init(value, url: LearningMaterialFileStore.fileURL(named: value.localFilename))
            case let value as HonorRecord:
                return HonorRecordFileStore.fileURL(for: value).map { .init(value, url: $0) }
            case let value as ComprehensiveQualityEvidenceDocument:
                return .init(value, url: ComprehensiveQualityEvidenceFileStore.fileURL(named: value.localFilename))
            case let value as MedicalLedgerPhoto:
                return MedicalLedgerPhotoStore.fileURL(for: value).map { .init(value, url: $0) }
            case let value as CareerResumeDocument:
                return CareerDocumentFileStore.fileURL(for: value).map { .init(value, url: $0) }
            default: return nil
            }
        }
        let cleanup = cleanup ?? LocalFileCleanup()
        try cleanup.enqueue(files)
        records.forEach { modelContext.delete($0) }
        try LocalModelSave.save(modelContext, undo: {
            records.forEach { modelContext.insert($0) }
        }, using: save)
        do { try cleanup.retry(in: modelContext); return nil }
        catch { return error.localizedDescription }
    }

    private static func localRecords(in context: ModelContext) throws -> [any PersistentModel] {
        var records: [any PersistentModel] = []
        func append<T: PersistentModel>(_ type: T.Type) throws {
            guard context.container.schema.entitiesByName[String(describing: type)] != nil else { return }
            records.append(contentsOf: try context.fetch(FetchDescriptor<T>()))
        }
        try append(Course.self)
        try append(Grade.self)
        try append(CourseNote.self)
        try append(CourseOccurrenceNote.self)
        try append(CourseReminderSetting.self)
        try append(TimetableCellReminder.self)
        try append(FavoriteClassroom.self)
        try append(FavoriteCampusLink.self)
        try append(PostgraduateTarget.self)
        try append(StudyTimeRecord.self)
        try append(HonorRecord.self)
        try append(LearningMaterialDocument.self)
        try append(LearningProject.self)
        try append(LearningProjectTask.self)
        try append(CareerResumeDocument.self)
        try append(CareerTask.self)
        try append(CareerOpportunity.self)
        try append(FitnessTestRecord.self)
        try append(ComprehensiveQualityRecord.self)
        try append(ComprehensiveQualityComponentEntry.self)
        try append(ComprehensiveQualityEvidenceDocument.self)
        try append(MedicalLedgerEntry.self)
        try append(MedicalLedgerPhoto.self)
        try append(ScheduleMemo.self)
        try append(ScheduleMemoImage.self)
        try append(ScheduleMemoAttachment.self)
        try append(ScheduleMemoAudio.self)
        return records
    }

}

private struct AppLocalDataDeletionError: LocalizedError {
    let failures: [String]

    var errorDescription: String? {
        "部分本机数据清理失败：\(failures.joined(separator: "；"))"
    }
}
