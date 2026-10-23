import Foundation
import SwiftData

nonisolated enum SchoolDataSyncContinuationPolicy {
    static func shouldStop(after error: Error) -> Bool {
        if case SchoolNetworkError.campusNetworkRequired = error {
            return true
        }
        return false
    }
}

enum SchoolDataSyncOutcome: Equatable {
    case success(String)
    case partialSuccess(String)
    case failure(String)
    case needsLogin
    case cancelled
    case needsReauthentication(SchoolReauthenticationContext)
}

enum SchoolDataRefreshScope: String, CaseIterable, Sendable {
    case timetable
    case grades
    case gradeSupplemental
    case exams
    case teachingPlan
    case trainingProgram
    case all
}

struct SchoolDataRefreshEvent: Sendable {
    let scopes: Set<SchoolDataRefreshScope>

    init(_ scopes: Set<SchoolDataRefreshScope>) {
        self.scopes = scopes
    }

    init(_ scope: SchoolDataRefreshScope) {
        self.init([scope])
    }

    func contains(_ scope: SchoolDataRefreshScope) -> Bool {
        scopes.contains(.all) || scopes.contains(scope)
    }
}

extension Notification.Name {
    static let schoolDataDidRefresh = Notification.Name("SchoolDataDidRefresh")
}

enum SchoolDataRefreshNotifier {
    static func post(_ scopes: Set<SchoolDataRefreshScope>) {
        guard !scopes.isEmpty else { return }
        NotificationCenter.default.post(
            name: .schoolDataDidRefresh,
            object: SchoolDataRefreshEvent(scopes)
        )
    }

    static func post(_ scope: SchoolDataRefreshScope) {
        post([scope])
    }
}

@MainActor
enum SchoolDataSyncService {
    static func syncAll(
        modelContext: ModelContext,
        language: AppLanguagePreference,
        userInitiated: Bool = false,
        progressReporter: AcademicOperationProgressReporter? = nil
    ) async -> SchoolDataSyncOutcome {
        let networkManager = ActiveCampusContext.networkManager

        if ReviewDemoMode.isEnabled {
            do {
                try ReviewDemoDataSeeder.seed(using: modelContext)
                LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: true)
                return .success(L10n.text("已刷新演示学校数据。社区数据仍使用真实服务。", language: language))
            } catch {
                return .failure(L10n.text("同步失败：%@", language: language, error.localizedDescription))
            }
        }

        if ActiveCampusContext.identity?.isCustom == true {
            return .success(L10n.text("通用入口不连接教务系统。请在课表、成绩和考试页面使用“导入”更新本地数据。", language: language))
        }

        guard networkManager.hasCachedIdentity else {
            return .needsLogin
        }

        guard networkManager.isLoggedIn else {
            return .needsReauthentication(.schoolDataSync)
        }

        let scope = CampusOperationScope()
        progressReporter?(.begin(.refreshingSemester))
        _ = await SemesterConfig.refreshRemoteIfAvailable(force: true)
        guard scope.isCurrent, !Task.isCancelled else { return .cancelled }

        var results: [String] = []
        var successfulOperationCount = 0
        var failedOperationCount = 0
        var refreshedScopes: Set<SchoolDataRefreshScope> = []
        var parsedGrades: [Grade]?
        var gradeRankingsToSave: [GradeRankingRecord]?
        var gradeCreditSummaryToSave: GradeCreditSummary?
        var examScheduleToSave: [ExamArrangement]?
        var teachingPlanToSave: [TeachingPlanSection]?
        var trainingProgramToSave: TrainingProgramDocument?

        do {
            progressReporter?(.begin(.fetchingTimetable))
            let document = try await networkManager.fetchTimetable()
            try scope.check()
            progressReporter?(.begin(.processingTimetable))
            let records = try await TimetableRefreshUseCase.parseRecords(html: document.html)
            try scope.check()
            progressReporter?(.begin(.savingTimetable))
            let persisted = try await persistTimetable(
                records,
                semesterID: document.sourceSemesterID,
                modelContext: modelContext,
                scope: scope
            )
            successfulOperationCount += 1
            results.append(L10n.text(
                "课表 %d 门",
                language: language,
                Set(persisted.sharedCourses.map(\.courseName)).count
            ))
            if let warning = persisted.reminderWarning {
                failedOperationCount += 1
                results.append(warning)
                progressReporter?(.fail(.savingTimetable, warning))
            }
            try scope.check()
            if await TimetableSharingService.shared.publishExistingSnapshotIfNeeded(
                courses: persisted.sharedCourses
            ) {
                results.append(L10n.text("共享课表已更新", language: language))
            }
            try scope.check()
        } catch {
            if scope.wasCancelled(error) { return .cancelled }
            if SchoolDataSyncContinuationPolicy.shouldStop(after: error) {
                progressReporter?(.fail(.fetchingTimetable, error.localizedDescription))
                return campusNetworkFailure(language: language)
            }
            if requiresReauthentication(error, userInitiated: userInitiated) {
                progressReporter?(.fail(.fetchingTimetable, error.localizedDescription))
                return .needsReauthentication(.schoolDataSync)
            }
            progressReporter?(.fail(.fetchingTimetable, error.localizedDescription))
            TimetableCacheMetadata.lastFailureMessage = error.localizedDescription
            failedOperationCount += 1
            results.append(L10n.text("课表失败：%@", language: language, error.localizedDescription))
        }

        if networkManager.currentPortal == .undergraduate {
            do {
                progressReporter?(.begin(.fetchingGrades))
                let html = try await networkManager.fetchGrades()
                try scope.check()
                progressReporter?(.begin(.processingGrades))
                let parsed = try HTMLParser.parseGrades(html: html)
                let rankings = (try? HTMLParser.parseGradeRankings(html: html)) ?? []
                let creditSummary = try? HTMLParser.parseGradeCreditSummary(html: html)
                if !rankings.isEmpty {
                    gradeRankingsToSave = rankings
                }
                if let creditSummary {
                    gradeCreditSummaryToSave = creditSummary
                }
                parsedGrades = parsed
            } catch {
                if scope.wasCancelled(error) { return .cancelled }
                if SchoolDataSyncContinuationPolicy.shouldStop(after: error) {
                    progressReporter?(.fail(.fetchingGrades, error.localizedDescription))
                    return campusNetworkFailure(language: language)
                }
                if requiresReauthentication(error, userInitiated: userInitiated) {
                    progressReporter?(.fail(.fetchingGrades, error.localizedDescription))
                    return .needsReauthentication(.schoolDataSync)
                }
                progressReporter?(.fail(.fetchingGrades, error.localizedDescription))
                failedOperationCount += 1
                results.append(L10n.text("成绩失败：%@", language: language, error.localizedDescription))
            }

            do {
                progressReporter?(.begin(.fetchingRankings))
                let html = try await networkManager.fetchGradeRankings()
                try scope.check()
                let parsed = try HTMLParser.parseGradeRankings(html: html)
                gradeRankingsToSave = parsed
                if let creditSummary = try? HTMLParser.parseGradeCreditSummary(html: html) {
                    gradeCreditSummaryToSave = creditSummary
                }
                successfulOperationCount += 1
                results.append(L10n.text("排名 %d 条", language: language, parsed.count))
            } catch {
                if scope.wasCancelled(error) { return .cancelled }
                if SchoolDataSyncContinuationPolicy.shouldStop(after: error) {
                    progressReporter?(.fail(.fetchingRankings, error.localizedDescription))
                    return campusNetworkFailure(language: language)
                }
                if requiresReauthentication(error, userInitiated: userInitiated) {
                    progressReporter?(.fail(.fetchingRankings, error.localizedDescription))
                    return .needsReauthentication(.schoolDataSync)
                }
                progressReporter?(.fail(.fetchingRankings, error.localizedDescription))
                failedOperationCount += 1
                results.append(L10n.text("排名失败：%@", language: language, error.localizedDescription))
            }

            do {
                progressReporter?(.begin(.fetchingExams))
                let html = try await networkManager.fetchExamSchedule()
                try scope.check()
                progressReporter?(.begin(.processingExams))
                let parsed = try HTMLParser.parseExams(html: html)
                examScheduleToSave = parsed
            } catch {
                if scope.wasCancelled(error) { return .cancelled }
                if SchoolDataSyncContinuationPolicy.shouldStop(after: error) {
                    progressReporter?(.fail(.fetchingExams, error.localizedDescription))
                    return campusNetworkFailure(language: language)
                }
                if requiresReauthentication(error, userInitiated: userInitiated) {
                    progressReporter?(.fail(.fetchingExams, error.localizedDescription))
                    return .needsReauthentication(.schoolDataSync)
                }
                progressReporter?(.fail(.fetchingExams, error.localizedDescription))
                failedOperationCount += 1
                results.append(L10n.text("考试失败：%@", language: language, error.localizedDescription))
            }

            do {
                progressReporter?(.begin(.fetchingTeachingPlan))
                let html = try await networkManager.fetchTeachingPlan()
                try scope.check()
                progressReporter?(.begin(.processingTeachingPlan))
                let parsed = try HTMLParser.parseTeachingPlan(html: html)
                teachingPlanToSave = parsed
                successfulOperationCount += 1
                results.append(L10n.text("教学计划 %d 学期", language: language, parsed.count))
            } catch {
                if scope.wasCancelled(error) { return .cancelled }
                if SchoolDataSyncContinuationPolicy.shouldStop(after: error) {
                    progressReporter?(.fail(.fetchingTeachingPlan, error.localizedDescription))
                    return campusNetworkFailure(language: language)
                }
                if requiresReauthentication(error, userInitiated: userInitiated) {
                    progressReporter?(.fail(.fetchingTeachingPlan, error.localizedDescription))
                    return .needsReauthentication(.schoolDataSync)
                }
                progressReporter?(.fail(.fetchingTeachingPlan, error.localizedDescription))
                failedOperationCount += 1
                results.append(L10n.text("教学计划失败：%@", language: language, error.localizedDescription))
            }

            do {
                progressReporter?(.begin(.fetchingTrainingProgram))
                let html = try await networkManager.fetchGraduationRequirements()
                try scope.check()
                progressReporter?(.begin(.processingTrainingProgram))
                let document = try HTMLParser.parseTrainingProgram(html: html)
                trainingProgramToSave = document
                successfulOperationCount += 1
                results.append(L10n.text("培养方案 %d 类", language: language, document.creditRequirements.count))
            } catch {
                if scope.wasCancelled(error) { return .cancelled }
                if SchoolDataSyncContinuationPolicy.shouldStop(after: error) {
                    progressReporter?(.fail(.fetchingTrainingProgram, error.localizedDescription))
                    return campusNetworkFailure(language: language)
                }
                if requiresReauthentication(error, userInitiated: userInitiated) {
                    progressReporter?(.fail(.fetchingTrainingProgram, error.localizedDescription))
                    return .needsReauthentication(.schoolDataSync)
                }
                progressReporter?(.fail(.fetchingTrainingProgram, error.localizedDescription))
                failedOperationCount += 1
                results.append(L10n.text("培养方案失败：%@", language: language, error.localizedDescription))
            }
        }

        guard scope.isCurrent, !Task.isCancelled else { return .cancelled }
        progressReporter?(.begin(.savingResults))
        if let parsedGrades {
            do {
                try persistGrades(parsedGrades, modelContext: modelContext)
                SchoolDataCache.markGradeDetailsSynced()
                refreshedScopes.insert(.grades)
                successfulOperationCount += 1
                results.append(L10n.text("成绩 %d 条", language: language, parsedGrades.count))
            } catch {
                progressReporter?(.fail(.savingResults, error.localizedDescription))
                failedOperationCount += 1
                results.append(L10n.text("成绩保存失败：%@", language: language, error.localizedDescription))
            }
        }

        if let gradeRankingsToSave {
            SchoolDataCache.saveGradeRankings(gradeRankingsToSave, notifies: false)
            refreshedScopes.insert(.gradeSupplemental)
        }
        if let gradeCreditSummaryToSave {
            SchoolDataCache.saveGradeCreditSummary(gradeCreditSummaryToSave, notifies: false)
            refreshedScopes.insert(.gradeSupplemental)
        }
        if let examScheduleToSave {
            do {
                try SchoolDataCache.saveRemoteExamSchedule(examScheduleToSave, notifies: false)
                refreshedScopes.insert(.exams)
                successfulOperationCount += 1
                results.append(L10n.text("考试 %d 条", language: language, examScheduleToSave.count))
            } catch {
                failedOperationCount += 1
                progressReporter?(.fail(.savingResults, error.localizedDescription))
                results.append(L10n.text("考试保存失败：%@", language: language, error.localizedDescription))
            }
        }
        if let teachingPlanToSave {
            SchoolDataCache.saveTeachingPlan(teachingPlanToSave, notifies: false)
            refreshedScopes.insert(.teachingPlan)
        }
        if let trainingProgramToSave {
            SchoolDataCache.saveTrainingProgram(trainingProgramToSave, notifies: false)
            refreshedScopes.insert(.trainingProgram)
        }

        if refreshedScopes.contains(.exams) {
            LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: true)
        }
        SchoolDataRefreshNotifier.post(refreshedScopes)

        let message = L10n.text(
            failedOperationCount == 0 ? "同步完成：%@。" : "同步结果：%@。",
            language: language,
            results.joined(separator: L10n.text("，", language: language))
        )
        if failedOperationCount == 0 {
            return .success(message)
        }
        if successfulOperationCount > 0 {
            return .partialSuccess(message)
        }
        return .failure(message)
    }

    private static func persistTimetable(
        _ records: [ParsedCourseRecord],
        semesterID: String,
        modelContext: ModelContext,
        scope: CampusOperationScope
    ) async throws -> (sharedCourses: [SharedTimetableCourse], reminderWarning: String?) {
        try scope.check()
        let saved = try TimetableRefreshUseCase().persist(
            records: records,
            existingCourses: modelContext.fetch(FetchDescriptor<Course>()),
            modelContext: modelContext,
            semesterID: semesterID
        )

        let reminderWarning = await saved.reminders.restore()
        try scope.check()
        let now = Date()
        TimetableCacheMetadata.lastSyncAt = now
        TimetableCacheMetadata.lastFailureMessage = reminderWarning
        TimetableCacheMetadata.lastSyncedSemesterID = semesterID
        AppStoreReviewCoordinator.recordSuccessfulSync(kind: .timetable, date: now)
        LeafyWidgetSnapshotBuilder.publish(from: modelContext, isAuthenticated: true)
        SchoolDataRefreshNotifier.post(.timetable)
        return (saved.sharedCourses, reminderWarning)
    }

    static func persistGrades(
        _ grades: [Grade], modelContext: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let previous = try modelContext.fetch(FetchDescriptor<Grade>())
        for grade in previous { modelContext.delete(grade) }
        for grade in grades { modelContext.insert(grade) }
        try LocalModelSave.save(modelContext, undo: {
            for grade in grades { modelContext.delete(grade) }
            for grade in previous { modelContext.insert(grade) }
        }, using: save)
    }

    private static func requiresReauthentication(
        _ error: Error,
        userInitiated: Bool
    ) -> Bool {
        userInitiated
            ? SchoolReauthentication.shouldPromptForUserInitiatedAccess(error)
            : SchoolReauthentication.requiresReauthentication(error)
    }

    private static func campusNetworkFailure(
        language: AppLanguagePreference
    ) -> SchoolDataSyncOutcome {
        .failure(
            L10n.text(
                "暂时无法访问教务系统。请连接 bjfu-wifi 或北林 VPN 后，再次点击同步或刷新。",
                language: language
            )
        )
    }
}
