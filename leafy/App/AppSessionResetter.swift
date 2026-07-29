import Foundation
import SwiftData

nonisolated enum AppAccountDeletionPolicy {
    static func canDelete(isReviewDemoMode: Bool) -> Bool {
        !isReviewDemoMode
    }
}

@MainActor
enum AppAccountDeletionCoordinator {
    static func delete(
        remotely: () async throws -> Void,
        locally: () throws -> Void
    ) async throws -> Error? {
        try await remotely()
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
    static func returnToLogin(modelContext: ModelContext? = nil) {
        if ReviewDemoMode.isEnabled {
            ReviewDemoDataSeeder.exit(using: modelContext)
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

        var courses: [Course] = []
        var cellReminders: [TimetableCellReminder] = []
        attempt("课程提醒数据") {
            courses = try modelContext.fetch(FetchDescriptor<Course>())
        }
        attempt("课表格提醒数据") {
            cellReminders = try modelContext.fetch(FetchDescriptor<TimetableCellReminder>())
        }
        TimetableNotificationManager.cancelAllCourseReminders(courses: courses)
        TimetableNotificationManager.cancelAllCellReminders(cellReminders)
        ScheduleReportNotificationManager.clearScheduledNotifications()

        attempt("SwiftData") {
            try deleteAllModels(in: modelContext)
        }
        attempt("求职文件") {
            try CareerDocumentFileStore.deleteAllFiles()
        }
        attempt("学习资料") {
            try LearningMaterialFileStore.deleteAllFiles()
        }
        attempt("综测材料") {
            try ComprehensiveQualityEvidenceFileStore.deleteAllFiles()
        }
        MedicalLedgerPhotoStore.deleteAllFiles()
        attempt("课表背景") {
            try TimetableBackgroundStore.deleteAllBackgroundFiles()
        }
        attempt("社区草稿") {
            try LocalCommunityPostDraftRepository.shared.deleteAllDraftData()
        }
        CommunityPostCardGenerator.cleanupStaleRenderedFiles()
        attempt("MyLeafy AI Keychain") {
            try CampusAIKeychainStore.deleteAll()
        }

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

        if !cleanupFailures.isEmpty {
            throw AppLocalDataDeletionError(failures: cleanupFailures)
        }
    }

    private static func deleteAllModels(in modelContext: ModelContext) throws {
        try modelContext.delete(model: Course.self)
        try modelContext.delete(model: Grade.self)
        try modelContext.delete(model: CourseNote.self)
        try modelContext.delete(model: CourseOccurrenceNote.self)
        try modelContext.delete(model: CourseReminderSetting.self)
        try modelContext.delete(model: TimetableCellReminder.self)
        try modelContext.delete(model: FavoriteClassroom.self)
        try modelContext.delete(model: FavoriteCampusLink.self)
        try modelContext.delete(model: PostgraduateTarget.self)
        try modelContext.delete(model: StudyTimeRecord.self)
        try modelContext.delete(model: HonorRecord.self)
        try modelContext.delete(model: LearningMaterialDocument.self)
        try modelContext.delete(model: LearningProject.self)
        try modelContext.delete(model: LearningProjectTask.self)
        try modelContext.delete(model: CareerResumeDocument.self)
        try modelContext.delete(model: CareerTask.self)
        try modelContext.delete(model: CareerOpportunity.self)
        try modelContext.delete(model: FitnessTestRecord.self)
        try modelContext.delete(model: ComprehensiveQualityRecord.self)
        try modelContext.delete(model: ComprehensiveQualityComponentEntry.self)
        try modelContext.delete(model: ComprehensiveQualityEvidenceDocument.self)
        try modelContext.delete(model: CampusAIConversation.self)
        try modelContext.delete(model: CampusAIMessage.self)
        try modelContext.delete(model: CampusAIActionRecord.self)
        try modelContext.delete(model: MedicalLedgerEntry.self)
        try modelContext.delete(model: MedicalLedgerPhoto.self)
        try modelContext.save()
    }
}

private struct AppLocalDataDeletionError: LocalizedError {
    let failures: [String]

    var errorDescription: String? {
        "部分本机数据清理失败：\(failures.joined(separator: "；"))"
    }
}
